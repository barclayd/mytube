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
  var errorMessage: String?
  private var task: Task<Void, Never>?
  private let directory: URL
  private var index: URL { directory.appendingPathComponent("library.json") }

  init(directory: URL? = nil) {
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
    guard !videos.contains(where: { $0.id == link.videoID }) else {
      errorMessage = "This video is already in your library."
      return
    }
    isDownloading = true
    progress = nil
    activityTitle = "Preparing video…"
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
      do {
        let (title, stream) = try await VideoResolver.resolve(link.videoID)
        activityTitle = title
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
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode)
        else {
          throw DownloadError.rejected
        }
        try Task.checkCancellation()
        // AVFoundation needs the MP4 extension, rather than URLSession's .tmp suffix.
        let destination = directory.appendingPathComponent("\(link.videoID).mp4")
        try FileManager.default.moveItem(at: temporary, to: destination)
        createdFiles.append(destination)
        let asset = AVURLAsset(url: destination)
        guard try await asset.load(.isPlayable) else { throw DownloadError.invalidMedia }
        let duration = try await asset.load(.duration).seconds
        // Generate a local thumbnail so the entire library works offline.
        var thumbnailFilename: String?
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: destination))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        if let frame = try? await generator.image(at: .zero),
          let data = UIImage(cgImage: frame.image).jpegData(compressionQuality: 0.8)
        {
          let filename = "\(link.videoID).jpg"
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
          bytes: Int64(bytes), duration: duration, resolution: stream.videoResolution ?? 0)
        let updated = [video] + videos
        try persist(updated)
        videos = updated
      } catch {
        for file in createdFiles { try? FileManager.default.removeItem(at: file) }
        if !Task.isCancelled {
          errorMessage = "Couldn’t download this video. \(error.localizedDescription)"
        }
      }
    }
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
    case .noStream: "YouTube didn’t provide an MP4 with both video and audio. Try another video."
    case .rejected: "YouTube refused the download. Please try again later."
    case .invalidMedia: "The downloaded file couldn’t be played. Please try again."
    }
  }
}

// Keep YouTubeKit's non-Sendable extractor on the generic executor, off the UI actor.
private enum VideoResolver {
  static func resolve(_ videoID: String) async throws -> (String, YouTubeKit.Stream) {
    let youtube = YouTube(videoID: videoID, methods: [.local])
    let metadata = try await youtube.metadata
    guard
      let stream = try await youtube.streams
        .filter({
          $0.includesVideoAndAudioTrack && $0.isNativelyPlayable && $0.fileExtension == .mp4
        })
        .highestResolutionStream()
    else { throw DownloadError.noStream }
    return (metadata?.title ?? "YouTube video", stream)
  }
}
