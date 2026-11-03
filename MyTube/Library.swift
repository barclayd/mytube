import AVFoundation
import Observation
import UIKit
import YouTubeKit

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

  var qualityLabel: String { resolution >= 2160 ? "4K" : "\(resolution)p" }

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
  private(set) var progress: Double?
  private(set) var activityTitle = "Preparing video…"
  private(set) var activityStatus = "Finding video…"
  var preferredQuality: DownloadQuality = .fullHD {
    didSet { UserDefaults.standard.set(preferredQuality.rawValue, forKey: "downloadQuality") }
  }
  var errorMessage: String?
  private var task: Task<Void, Never>?
  private let directory: URL
  private var index: URL { directory.appendingPathComponent("library.json") }

  init(directory: URL? = nil) {
    preferredQuality =
      DownloadQuality(rawValue: UserDefaults.standard.integer(forKey: "downloadQuality")) ?? .fullHD
    self.directory =
      directory ?? URL.documentsDirectory.appendingPathComponent("Videos", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: index.path) {
        videos = try JSONDecoder().decode([SavedVideo].self, from: Data(contentsOf: index))
          .filter {
            FileManager.default.fileExists(
              atPath: self.directory.appendingPathComponent($0.filename).path)
          }
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
    guard !isDownloading else { return }
    let quality = preferredQuality
    if let existing = videos.first(where: { $0.id == link.videoID }),
      existing.resolution >= quality.rawValue
    {
      errorMessage = "A download at this quality or better is already in your library."
      return
    }
    isDownloading = true
    progress = nil
    activityTitle = "Preparing video…"
    activityStatus = "Finding video…"
    task = Task { [self] in
      let background = UIApplication.shared.beginBackgroundTask(withName: "Save video") {
        [weak library = self] in
        Task { @MainActor in library?.cancel() }
      }
      defer {
        if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        isDownloading = false
        progress = nil
        task = nil
      }
      var createdFiles: [URL] = []
      let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString, isDirectory: true)
      defer { try? FileManager.default.removeItem(at: workspace) }
      do {
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let (title, plan) = try await VideoResolver.resolve(link.videoID, quality: quality)
        activityTitle = title
        if let existing = videos.first(where: { $0.id == link.videoID }),
          existing.resolution >= plan.resolution
        {
          errorMessage =
            "The saved video is already at the best available quality for this selection."
          return
        }
        activityStatus = "Downloading video · \(plan.resolution)p"
        let videoFile = workspace.appendingPathComponent("video.mp4")
        try await transfer(plan.video, to: videoFile)
        let destination = directory.appendingPathComponent(
          "\(link.videoID)-\(UUID().uuidString).mp4")
        createdFiles.append(destination)
        if let audio = plan.audio {
          activityStatus = "Downloading audio"
          progress = nil
          let audioFile = workspace.appendingPathComponent("audio.m4a")
          try await transfer(audio, to: audioFile)
          activityStatus = "Combining video and audio…"
          progress = nil
          try await MediaAssembler.combine(video: videoFile, audio: audioFile, output: destination)
        } else {
          try FileManager.default.moveItem(at: videoFile, to: destination)
        }
        try Task.checkCancellation()
        activityStatus = "Saving video…"
        progress = nil
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
          try data.write(to: file, options: .atomic)
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
          errorMessage = "Couldn’t download this video. \(error.localizedDescription)"
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
  }

  func cancel() { task?.cancel() }

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
    try JSONEncoder().encode(videos).write(to: index, options: .atomic)
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
