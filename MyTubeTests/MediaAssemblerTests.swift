import AVFoundation
import Foundation
import Testing

@testable import MyTube

private final class MediaFixtureBundle: NSObject {}

@MainActor struct MediaAssemblerTests {
  @Test(arguments: ["Video1080", "Fragmented1080", "Long1080"])
  func combinesFullHDVideoWithAudibleAudioWithoutReducingResolution(_ filename: String) async throws
  {
    let bundle = Bundle(for: MediaFixtureBundle.self)
    let video = try #require(bundle.url(forResource: filename, withExtension: "mp4"))
    let audio = try #require(bundle.url(forResource: "Audio", withExtension: "m4a"))
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: output) }
    try await MediaAssembler.combine(video: video, audio: audio, output: output)
    let asset = AVURLAsset(url: output)
    #expect(try await asset.load(.isPlayable))
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    #expect(videoTracks.count == 1)
    #expect(audioTracks.count == 1)
    let track = try #require(videoTracks.first)
    let size = try await track.load(.naturalSize)
    #expect(size.width == 1920 && size.height == 1080)
    let duration = try await asset.load(.duration).seconds
    #expect(abs(duration - 1) < 0.1)
  }

  @Test func rejectsMissingAudioTrack() async throws {
    let bundle = Bundle(for: MediaFixtureBundle.self)
    let video = try #require(bundle.url(forResource: "Video1080", withExtension: "mp4"))
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: output) }
    await #expect(throws: MediaAssembler.MediaError.self) {
      try await MediaAssembler.combine(video: video, audio: video, output: output)
    }
    #expect(!FileManager.default.fileExists(atPath: output.path))
  }
}
