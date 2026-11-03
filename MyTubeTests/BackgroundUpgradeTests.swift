import Foundation
import Testing
import YouTubeKit

@testable import MyTube

@MainActor private final class BackgroundLease: DownloadBackgroundWork {
  var starts = 0
  var completions: [Bool] = []
  var totals: [Int64] = []
  var expire: (@MainActor () -> Void)?
  var rejection: Error?

  func begin(title: String, onExpiration: @escaping @MainActor () -> Void) async throws {
    starts += 1
    if let rejection { throw rejection }
    expire = onExpiration
  }
  func report(completed: Int64, total: Int64, subtitle: String) { totals.append(total) }
  func finish(success: Bool) { completions.append(success) }
}

private actor Attempts {
  var ids: [String] = []
  var qualities: [DownloadQuality] = []
  func add(_ id: String, _ quality: DownloadQuality) {
    ids.append(id)
    qualities.append(quality)
  }
}

@MainActor struct BackgroundUpgradeTests {
  private enum Failure: Error { case unavailable }

  private func fixture() throws -> (URL, [SavedVideo]) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let videos = ["jNQXAC9IVRw", "HOfdboHvshg"].map { id in
      SavedVideo(
        id: id, title: id, filename: "\(id).mp4", savedAt: .now,
        bytes: 3, duration: 18, resolution: 360)
    }
    for video in videos {
      try Data([1, 2, 3]).write(to: directory.appendingPathComponent(video.filename))
    }
    try JSONEncoder().encode(videos).write(to: directory.appendingPathComponent("library.json"))
    return (directory, videos)
  }

  private func wait(until condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(condition())
  }

  @Test func oneBackgroundLeaseCoversEntireBatchAndFailuresKeepOriginals() async throws {
    let (directory, videos) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let background = BackgroundLease()
    let attempts = Attempts()
    let library = Library(directory: directory, backgroundWork: background) { id, quality in
      await attempts.add(id, quality)
      throw Failure.unavailable
    }
    library.upgradeAllToMaximumQuality()
    try await wait { !library.isUpgrading }
    #expect(background.starts == 1)
    #expect(background.completions == [false])
    #expect(background.totals.allSatisfy { $0 == 2000 })
    #expect(await attempts.ids == videos.map(\.id))
    #expect(await attempts.qualities == [.maximum, .maximum])
    #expect(library.videos == videos)
    #expect(library.upgradeSummary?.contains("2 failed") == true)
    #expect(!library.hasPendingUpgrades)
    for video in videos {
      #expect(try Data(contentsOf: library.url(for: video)) == Data([1, 2, 3]))
    }
  }

  @Test func systemExpirationPreservesQueueForRelaunch() async throws {
    let (directory, videos) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let background = BackgroundLease()
    let library = Library(directory: directory, backgroundWork: background) { _, _ in
      try await Task.sleep(for: .seconds(60))
      throw Failure.unavailable
    }
    library.upgradeAllToMaximumQuality()
    try await wait { library.isDownloading }
    background.expire?()
    try await wait { !library.isUpgrading }
    #expect(library.hasPendingUpgrades)
    #expect(library.videos == videos)
    #expect(background.completions == [false])

    let attempts = Attempts()
    let restored = Library(directory: directory, backgroundWork: BackgroundLease()) { id, quality in
      await attempts.add(id, quality)
      throw Failure.unavailable
    }
    #expect(restored.hasPendingUpgrades)
    #expect(!restored.isUpgrading)
    restored.upgradeAllToMaximumQuality()
    try await wait { !restored.isUpgrading }
    #expect(await attempts.ids == videos.map(\.id))
    #expect(!restored.hasPendingUpgrades)
  }

  @Test func resumesOnlyRemainingVideosFromCheckpoint() async throws {
    let (directory, videos) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let checkpoint = UpgradeQueue(remainingIDs: [videos[1].id], total: 2, upgraded: 1)
    try JSONEncoder().encode(checkpoint).write(
      to: directory.appendingPathComponent("upgrades.json"))
    let attempts = Attempts()
    let library = Library(directory: directory, backgroundWork: BackgroundLease()) { id, quality in
      await attempts.add(id, quality)
      throw Failure.unavailable
    }
    library.upgradeAllToMaximumQuality()
    try await wait { !library.isUpgrading }
    #expect(await attempts.ids == [videos[1].id])
    #expect(library.upgradeSummary?.contains("1 upgraded") == true)
    #expect(
      !FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("upgrades.json").path))
  }

  @Test func botChallengePausesBeforeFailingEveryVideo() async throws {
    let (directory, videos) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let attempts = Attempts()
    let library = Library(directory: directory, backgroundWork: BackgroundLease()) { id, quality in
      await attempts.add(id, quality)
      throw YouTubeKitError.requestBlocked
    }
    library.upgradeAllToMaximumQuality()
    try await wait { !library.isUpgrading }
    #expect(await attempts.ids == [videos[0].id])
    #expect(library.hasPendingUpgrades)
    #expect(library.upgradeErrors.isEmpty)
    #expect(library.upgradePauseReason?.contains("not a bot") == true)
    let checkpoint = try JSONDecoder().decode(
      UpgradeQueue.self, from: Data(contentsOf: directory.appendingPathComponent("upgrades.json")))
    #expect(checkpoint.remainingIDs == videos.map(\.id))
    #expect(checkpoint.failed == 0)
    let restored = Library(directory: directory, backgroundWork: BackgroundLease())
    #expect(restored.upgradePauseReason == library.upgradePauseReason)
    #expect(restored.videos == videos)
  }

  @Test func deniedBackgroundAccessIsVisibleAndDoesNotPreventForegroundWork() async throws {
    let (directory, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let background = BackgroundLease()
    background.rejection = Failure.unavailable
    let library = Library(directory: directory, backgroundWork: background) { _, _ in
      throw Failure.unavailable
    }
    library.upgradeAllToMaximumQuality()
    try await wait { !library.isUpgrading }
    #expect(library.backgroundNotice?.contains("Keep MyTube open") == true)
    #expect(library.upgradeErrors.count == 2)
    #expect(library.upgradeSummary?.contains("2 failed") == true)
  }
}
