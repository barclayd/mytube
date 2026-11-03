import AVFoundation
import Observation
import UIKit
import YouTubeKit

struct UpgradeQueue: Codable {
  var remainingIDs: [String]
  var total: Int
  var upgraded = 0
  var alreadyAtMaximum = 0
  var failed = 0
  var failures: [UpgradeFailure]? = nil
  var pauseReason: String? = nil
}

struct UpgradeFailure: Codable, Identifiable {
  var id: String
  var title: String
  var message: String
}

struct SavedVideo: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var filename: String
  var thumbnailFilename: String?
  var savedAt: Date
  var bytes: Int64
  var duration: Double
  var resolution: Int
  var pixelWidth: Int? = nil
  var pixelHeight: Int? = nil

  var dimensionsLabel: String? {
    guard let pixelWidth, let pixelHeight else { return nil }
    return "\(pixelWidth) × \(pixelHeight)"
  }

  var qualityLabel: String {
    switch resolution {
    case 4320...: "8K"
    case 2160..<4320: "4K"
    default: "\(resolution)p"
    }
  }

  var subtitle: String {
    let seconds = Int(duration.isFinite ? duration : 0)
    return
      "\(seconds / 60):\(String(format: "%02d", seconds % 60)) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
  }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
  let update: @Sendable (Double?) -> Void
  init(update: @escaping @Sendable (Double?) -> Void) { self.update = update }
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    update(
      totalBytesExpectedToWrite > 0
        ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : nil)
  }
}

@MainActor @Observable
final class Library {
  private(set) var videos: [SavedVideo] = []
  private(set) var isDownloading = false
  private(set) var progress: Double? { didSet { reportBackgroundProgress() } }
  private(set) var activityTitle = "Preparing video…"
  private(set) var activityStatus = "Finding video…"
  var preferredQuality: DownloadQuality = .fullHD {
    didSet { UserDefaults.standard.set(preferredQuality.rawValue, forKey: "downloadQuality") }
  }
  var errorMessage: String?
  private var task: Task<Void, Never>?
  private var upgradeTask: Task<Void, Never>?
  private(set) var isUpgrading = false
  private(set) var upgradeIndex = 0
  private(set) var upgradeTotal = 0
  private(set) var upgradeSummary: String?
  private(set) var upgradeErrors: [UpgradeFailure] = []
  private(set) var upgradePauseReason: String?
  private(set) var backgroundNotice: String?
  private var pendingUpgrades: UpgradeQueue?
  var hasPendingUpgrades: Bool { pendingUpgrades != nil }
  private var upgradeFailures = 0
  @ObservationIgnored private let backgroundWork: any DownloadBackgroundWork
  @ObservationIgnored private let resolve:
    @Sendable (String, DownloadQuality) async throws -> (String, VideoStreamPlan)
  private var phaseStart = 0.0
  private var phaseWeight = 0.0
  private let directory: URL
  private var index: URL { directory.appendingPathComponent("library.json") }
  private var upgradeIndexFile: URL { directory.appendingPathComponent("upgrades.json") }

  init(
    directory: URL? = nil,
    backgroundWork: (any DownloadBackgroundWork)? = nil,
    resolve:
      @escaping @Sendable (String, DownloadQuality) async throws -> (String, VideoStreamPlan) = {
        try await VideoResolver.resolve($0, quality: $1)
      }
  ) {
    self.backgroundWork = backgroundWork ?? ContinuedDownload.shared
    self.resolve = resolve
    preferredQuality =
      DownloadQuality(rawValue: UserDefaults.standard.integer(forKey: "downloadQuality")) ?? .fullHD
    self.directory =
      directory ?? URL.documentsDirectory.appendingPathComponent("Videos", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: self.directory.path)
      if FileManager.default.fileExists(atPath: index.path) {
        videos = try JSONDecoder().decode([SavedVideo].self, from: Data(contentsOf: index))
          .filter {
            FileManager.default.fileExists(
              atPath: self.directory.appendingPathComponent($0.filename).path)
          }
      }
      if FileManager.default.fileExists(atPath: upgradeIndexFile.path) {
        pendingUpgrades = try JSONDecoder().decode(
          UpgradeQueue.self, from: Data(contentsOf: upgradeIndexFile))
        upgradePauseReason = pendingUpgrades?.pauseReason
        upgradeErrors = pendingUpgrades?.failures ?? []
      }
      // Keep large, redownloadable media out of iCloud device backups.
      var folder = self.directory
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try folder.setResourceValues(values)
    } catch { errorMessage = "Your library couldn’t be opened. \(error.localizedDescription)" }
  }

  func url(for video: SavedVideo) -> URL { directory.appendingPathComponent(video.filename) }
  func thumbnail(for video: SavedVideo) -> URL? {
    video.thumbnailFilename.map { directory.appendingPathComponent($0) }
  }

  func download(_ link: YouTubeLink) {
    guard !isUpgrading else { return }
    startDownload(link, quality: preferredQuality)
  }

  private func startDownload(_ link: YouTubeLink, quality: DownloadQuality, quietly: Bool = false) {
    guard !isDownloading else { return }
    if let existing = videos.first(where: { $0.id == link.videoID }),
      existing.resolution >= quality.rawValue
    {
      errorMessage = "A download at this quality or better is already in your library."
      return
    }
    isDownloading = true
    progress = nil
    activityTitle = "Preparing video…"
    setPhase("Finding video…", start: 0, weight: 0)
    let ownsBackgroundWork = !isUpgrading
    task = Task { [self] in
      var fallback = UIBackgroundTaskIdentifier.invalid
      var succeeded = false
      defer {
        if ownsBackgroundWork { backgroundWork.finish(success: succeeded && !Task.isCancelled) }
        if fallback != .invalid { UIApplication.shared.endBackgroundTask(fallback) }
        isDownloading = false
        progress = nil
        task = nil
      }
      var createdFiles: [URL] = []
      let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString, isDirectory: true)
      defer { try? FileManager.default.removeItem(at: workspace) }
      do {
        if ownsBackgroundWork {
          fallback = try await beginBackgroundWork(title: "Downloading Video")
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
          at: workspace, withIntermediateDirectories: true,
          attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let (title, plan) = try await resolve(link.videoID, quality)
        activityTitle = title
        if let existing = videos.first(where: { $0.id == link.videoID }),
          existing.resolution >= plan.resolution
        {
          if !quietly {
            errorMessage =
              "The saved video is already at the best available quality for this selection."
          }
          succeeded = true
          return
        }
        setPhase("Downloading video · \(plan.resolution)p", start: 0.02, weight: 0.8)
        let videoFile = workspace.appendingPathComponent("video.mp4")
        try await transfer(plan.video, to: videoFile)
        let destination = directory.appendingPathComponent(
          "\(link.videoID)-\(UUID().uuidString).mp4")
        createdFiles.append(destination)
        if let audio = plan.audio {
          setPhase("Downloading audio", start: 0.82, weight: 0.1)
          let audioFile = workspace.appendingPathComponent("audio.m4a")
          try await transfer(audio, to: audioFile)
          setPhase("Combining video and audio…", start: 0.92, weight: 0)
          try await MediaAssembler.combine(video: videoFile, audio: audioFile, output: destination)
        } else {
          try FileManager.default.moveItem(at: videoFile, to: destination)
        }
        try Task.checkCancellation()
        setPhase("Saving video…", start: 0.98, weight: 0)
        let asset = AVURLAsset(url: destination)
        guard try await asset.load(.isPlayable) else { throw DownloadError.invalidMedia }
        let duration = try await asset.load(.duration).seconds
        guard let picture = try await asset.loadTracks(withMediaType: .video).first,
          !(try await asset.loadTracks(withMediaType: .audio)).isEmpty,
          duration.isFinite, duration > 0
        else { throw DownloadError.invalidMedia }
        let dimensions = try await picture.load(.naturalSize)
        // Generate a local thumbnail so the entire library works offline.
        var thumbnailFilename: String?
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: destination))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        if let frame = try? await generator.image(at: .zero),
          let data = UIImage(cgImage: frame.image).jpegData(compressionQuality: 0.8)
        {
          let filename = "\(link.videoID)-\(UUID().uuidString).jpg"
          let file = directory.appendingPathComponent(filename)
          try data.write(
            to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
          createdFiles.append(file)
          thumbnailFilename = filename
        }
        try Task.checkCancellation()
        let bytes = (try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        let video = SavedVideo(
          id: link.videoID, title: title, filename: destination.lastPathComponent,
          thumbnailFilename: thumbnailFilename, savedAt: .now,
          bytes: Int64(bytes), duration: duration, resolution: plan.resolution,
          pixelWidth: Int(abs(dimensions.width)), pixelHeight: Int(abs(dimensions.height)))
        let oldVersion = videos.first { $0.id == video.id }
        let updated = [video] + videos.filter { $0.id != video.id }
        try persist(updated)
        videos = updated
        succeeded = true
        // Keep the old download intact until the upgraded file and index are safely stored.
        if let oldVersion {
          try? FileManager.default.removeItem(at: url(for: oldVersion))
          if let image = thumbnail(for: oldVersion) {
            try? FileManager.default.removeItem(at: image)
          }
        }
      } catch {
        for file in createdFiles { try? FileManager.default.removeItem(at: file) }
        if !Task.isCancelled {
          if quietly {
            if error as? YouTubeKitError == .requestBlocked {
              upgradePauseReason = error.localizedDescription
              return
            }
            upgradeFailures += 1
            upgradeErrors.append(
              UpgradeFailure(
                id: link.videoID,
                title: videos.first(where: { $0.id == link.videoID })?.title ?? link.videoID,
                message: "\(activityStatus) \(error.localizedDescription)"))
          } else {
            errorMessage = "Couldn’t download this video. \(error.localizedDescription)"
          }
        }
      }
    }
  }

  private func transfer(_ stream: YouTubeKit.Stream, to destination: URL) async throws {
    try await stream.waitUntilAvailable()
    try Task.checkCancellation()
    let delegate = DownloadProgress { [weak library = self] value in
      Task { @MainActor in library?.progress = value }
    }
    var request = URLRequest(url: stream.url)
    request.timeoutInterval = 60
    let (temporary, response) = try await URLSession.shared.download(
      for: request, delegate: delegate)
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw DownloadError.rejected
    }
    try Task.checkCancellation()
    try FileManager.default.moveItem(at: temporary, to: destination)
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: destination.path)
  }

  private func beginBackgroundWork(title: String) async throws -> UIBackgroundTaskIdentifier {
    backgroundNotice = "Requesting background access…"
    do {
      try await backgroundWork.begin(title: title) { [weak self] in self?.cancel() }
      backgroundNotice = "You can lock your screen while this runs."
      reportBackgroundProgress()
      return .invalid
    } catch {
      try Task.checkCancellation()
      // A denied request must not silently promise locked-screen execution.
      backgroundNotice = "Keep MyTube open. iOS couldn’t allow background processing right now."
      return UIApplication.shared.beginBackgroundTask(withName: title) { [weak self] in
        Task { @MainActor in self?.cancel() }
      }
    }
  }

  private func setPhase(_ status: String, start: Double, weight: Double) {
    activityStatus = status
    phaseStart = start
    phaseWeight = weight
    progress = nil
  }

  private func reportBackgroundProgress() {
    let count = isUpgrading ? max(upgradeTotal, 1) : 1
    let index = isUpgrading ? max(upgradeIndex - 1, 0) : 0
    let fraction = phaseStart + (progress ?? 0) * phaseWeight
    let subtitle =
      isUpgrading
      ? "Video \(upgradeIndex) of \(upgradeTotal) · \(activityStatus)" : activityStatus
    backgroundWork.report(
      completed: Int64(index * 1000) + Int64(fraction * 1000),
      total: Int64(count * 1000), subtitle: subtitle)
  }

  func cancel() {
    upgradeTask?.cancel()
    task?.cancel()
  }

  func upgradeAllToMaximumQuality() {
    guard !isDownloading, !isUpgrading, !videos.isEmpty else { return }
    var queue = pendingUpgrades ?? UpgradeQueue(remainingIDs: videos.map(\.id), total: videos.count)
    queue.pauseReason = nil
    do { try saveUpgradeQueue(queue) } catch {
      errorMessage = "Couldn’t save upgrade progress. \(error.localizedDescription)"
      return
    }
    isUpgrading = true
    upgradeIndex = queue.total - queue.remainingIDs.count + 1
    upgradeTotal = queue.total
    upgradeFailures = 0
    upgradeErrors = queue.failures ?? []
    upgradePauseReason = nil
    upgradeSummary = nil
    upgradeTask = Task { [self] in
      var fallback = UIBackgroundTaskIdentifier.invalid
      var finished = false
      defer {
        backgroundWork.finish(success: finished && queue.failed == 0)
        if fallback != .invalid { UIApplication.shared.endBackgroundTask(fallback) }
        isUpgrading = false
        upgradeTask = nil
        upgradeSummary =
          "\(finished ? "Finished. " : "Paused. Tap Resume Quality Upgrades to continue. ")\(queue.upgraded) upgraded, \(queue.alreadyAtMaximum) already at maximum, \(queue.failed) failed."
      }
      do {
        fallback = try await beginBackgroundWork(title: "Upgrading Videos")
        while let id = queue.remainingIDs.first {
          try Task.checkCancellation()
          upgradeIndex = queue.total - queue.remainingIDs.count + 1
          if let video = videos.first(where: { $0.id == id }),
            let link = YouTubeLink("https://youtu.be/\(id)")
          {
            let failuresBefore = upgradeFailures
            startDownload(link, quality: .maximum, quietly: true)
            await task?.value
            try Task.checkCancellation()
            if let reason = upgradePauseReason {
              queue.pauseReason = reason
              try saveUpgradeQueue(queue)
              return
            }
            if let current = videos.first(where: { $0.id == id }) {
              if current.filename != video.filename {
                queue.upgraded += 1
              } else if upgradeFailures == failuresBefore {
                queue.alreadyAtMaximum += 1
              } else {
                queue.failed += 1
              }
            }
          }
          queue.remainingIDs.removeFirst()
          queue.failures = upgradeErrors
          try saveUpgradeQueue(queue)
        }
        try saveUpgradeQueue(nil)
        finished = true
      } catch is CancellationError {
        // The current video's old copy and pending queue are still safely on disk.
      } catch {
        errorMessage = "Couldn’t save upgrade progress. \(error.localizedDescription)"
      }
    }
  }

  private func saveUpgradeQueue(_ queue: UpgradeQueue?) throws {
    if let queue {
      try JSONEncoder().encode(queue).write(
        to: upgradeIndexFile,
        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    } else if FileManager.default.fileExists(atPath: upgradeIndexFile.path) {
      try FileManager.default.removeItem(at: upgradeIndexFile)
    }
    pendingUpgrades = queue
  }

  func delete(_ video: SavedVideo) {
    do {
      let updated = videos.filter { $0.id != video.id }
      try persist(updated)
      videos = updated
      try FileManager.default.removeItem(at: url(for: video))
      if let thumbnail = thumbnail(for: video) {
        try? FileManager.default.removeItem(at: thumbnail)
      }
    } catch { errorMessage = "Couldn’t remove the video. \(error.localizedDescription)" }
  }

  private func persist(_ videos: [SavedVideo]) throws {
    try JSONEncoder().encode(videos).write(
      to: index, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}

private enum DownloadError: LocalizedError {
  case noStream, rejected, invalidMedia
  var errorDescription: String? {
    switch self {
    case .noStream:
      "YouTube didn’t provide compatible video and audio at this quality. Try a lower quality."
    case .rejected: "YouTube refused the download. Please try again later."
    case .invalidMedia: "The downloaded file couldn’t be played. Please try again."
    }
  }
}

struct VideoStreamPlan: Sendable {
  let video: YouTubeKit.Stream
  let audio: YouTubeKit.Stream?
  var resolution: Int { video.videoResolution ?? 0 }
}

// Keep YouTubeKit's non-Sendable extractor off the UI actor.
private enum VideoResolver {
  static func resolve(_ videoID: String, quality: DownloadQuality) async throws -> (
    String, VideoStreamPlan
  ) {
    let youtube = YouTube(videoID: videoID, methods: [.local])
    let metadata = try await youtube.metadata
    let streams = try await youtube.streams
    let candidates = streams.filter {
      $0.includesVideoTrack && $0.isNativelyPlayable && $0.fileExtension == .mp4
    }
    guard let resolution = quality.resolution(from: candidates.compactMap(\.videoResolution)),
      let video = candidates.filter({ $0.videoResolution == resolution }).max(by: { lhs, rhs in
        // Prefer H.264 at the same resolution for broad MP4 export and playback support.
        let leftAVC = isAVC(lhs)
        let rightAVC = isAVC(rhs)
        if leftAVC != rightAVC { return !leftAVC }
        return (lhs.bitrate ?? 0) < (rhs.bitrate ?? 0)
      })
    else { throw DownloadError.noStream }
    let audio: YouTubeKit.Stream?
    if video.includesAudioTrack {
      audio = nil
    } else {
      guard
        let track = streams.filter({
          !$0.includesVideoTrack && $0.includesAudioTrack && $0.isNativelyPlayable
            && $0.fileExtension == .m4a
        })
        .highestAudioBitrateStream()
      else { throw DownloadError.noStream }
      audio = track
    }
    return (metadata?.title ?? "YouTube video", VideoStreamPlan(video: video, audio: audio))
  }

  private static func isAVC(_ stream: YouTubeKit.Stream) -> Bool {
    if case .avc1 = stream.videoCodec { return true }
    return false
  }
}
