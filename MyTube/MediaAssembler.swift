import AVFoundation

@MainActor enum MediaAssembler {
  /// Remuxes the original tracks without re-encoding or reducing their resolution.
  static func combine(video videoURL: URL, audio audioURL: URL, output: URL) async throws {
    let video = AVURLAsset(url: videoURL)
    let audio = AVURLAsset(url: audioURL)
    guard let sourceVideo = try await video.loadTracks(withMediaType: .video).first,
      let sourceAudio = try await audio.loadTracks(withMediaType: .audio).first
    else {
      throw MediaError.missingTracks
    }
    let composition = AVMutableComposition()
    guard
      let videoTrack = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
      let audioTrack = composition.addMutableTrack(
        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      throw MediaError.missingTracks
    }
    let videoRange = try await sourceVideo.load(.timeRange)
    let audioRange = try await sourceAudio.load(.timeRange)
    // Some YouTube DASH MP4s report a phantom empty video tail in AVFoundation.
    // Use the shared timeline so the result has audio for its entire duration.
    let duration = CMTimeMinimum(videoRange.duration, audioRange.duration)
    try videoTrack.insertTimeRange(
      CMTimeRange(start: videoRange.start, duration: duration), of: sourceVideo, at: .zero)
    try audioTrack.insertTimeRange(
      CMTimeRange(start: audioRange.start, duration: duration), of: sourceAudio, at: .zero)
    videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
    guard
      let export = AVAssetExportSession(
        asset: composition, presetName: AVAssetExportPresetPassthrough)
    else {
      throw MediaError.unsupportedContainer
    }
    export.shouldOptimizeForNetworkUse = true
    try Task.checkCancellation()
    try await export.export(to: output, as: .mp4)
    try Task.checkCancellation()
  }

  enum MediaError: LocalizedError {
    case missingTracks, unsupportedContainer
    var errorDescription: String? {
      switch self {
      case .missingTracks: "The downloaded video or audio track is missing. Please try again."
      case .unsupportedContainer:
        "This quality can’t be saved as an MP4 on this device. Choose a lower quality."
      }
    }
  }
}
