import Foundation
import Testing

@testable import MyTube

@MainActor private final class DownloadLease: DownloadBackgroundWork {
  var starts = 0
  var completions: [Bool] = []
  var expiration: (@MainActor () -> Void)?
  func begin(title: String, onExpiration: @escaping @MainActor () -> Void) async throws {
    starts += 1
    expiration = onExpiration
  }
  func report(completed: Int64, total: Int64, subtitle: String) {}
  func finish(success: Bool) { completions.append(success) }
}

@MainActor struct BackgroundDownloadTests {
  private enum Failure: Error { case unavailable }
  private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  private func idle(_ library: Library) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while library.isDownloading, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(!library.isDownloading)
  }
  @Test func onlyOneDownloadCanStartAtATime() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let lease = DownloadLease()
    let library = Library(directory: directory, backgroundWork: lease) { _, _ in
      throw Failure.unavailable
    }
    library.download(YouTubeLink("https://youtu.be/jNQXAC9IVRw")!)
    library.download(YouTubeLink("https://youtu.be/HOfdboHvshg")!)
    try await idle(library)
    #expect(lease.starts == 1)
    #expect(lease.completions == [false])
    #expect(library.videos.isEmpty)
    #expect(library.errorMessage != nil)
  }
  @Test func duplicateDoesNotQueryYouTubeOrReplaceOriginalFile() throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let video = SavedVideo(
      id: "jNQXAC9IVRw", title: "Existing", filename: "old.mp4", savedAt: .now, bytes: 3,
      duration: 18, resolution: 360)
    try Data([1, 2, 3]).write(to: directory.appendingPathComponent(video.filename))
    try JSONEncoder().encode([video]).write(to: directory.appendingPathComponent("library.json"))
    let lease = DownloadLease()
    let library = Library(directory: directory, backgroundWork: lease) { _, _ in
      Issue.record("Duplicate video must not reach extraction")
      throw Failure.unavailable
    }
    library.download(YouTubeLink("https://youtu.be/jNQXAC9IVRw")!)
    #expect(!library.isDownloading)
    #expect(lease.starts == 0)
    #expect(library.videos == [video])
    #expect(try Data(contentsOf: library.url(for: video)) == Data([1, 2, 3]))
  }
  @Test func retiresBatchCheckpointWithoutStartingWork() throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let checkpoint = directory.appendingPathComponent("upgrades.json")
    try Data("old pending batch".utf8).write(to: checkpoint)
    let lease = DownloadLease()
    let library = Library(directory: directory, backgroundWork: lease)
    #expect(library.errorMessage == nil)
    #expect(!FileManager.default.fileExists(atPath: checkpoint.path))
    #expect(lease.starts == 0)
  }
}
