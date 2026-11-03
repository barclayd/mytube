import XCTest
@testable import YouTubeKit

final class RemoteMetadataTests: XCTestCase {
    func testRemoteTitleSurvivesStreamDecoding() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let json = #"{"url":"https://example.com/media?ticket=signed","itag":18,"ext":"mp4","video_codec":"avc1.42001E","audio_codec":"mp4a.40.2","video_title":"A remote video"}"#
        let remote = try decoder.decode(RemoteStream.self, from: Data(json.utf8))
        let stream = try Stream(remoteStream: remote)
        XCTAssertEqual(stream.videoTitle, "A remote video")
        XCTAssertTrue(stream.includesVideoAndAudioTrack)
    }
    func testOlderServerResponseRemainsSupported() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let json = #"{"url":"https://example.com/video.mp4","itag":18,"ext":"mp4","video_codec":"avc1.42001E","audio_codec":"mp4a.40.2"}"#
        let remote = try decoder.decode(RemoteStream.self, from: Data(json.utf8))
        XCTAssertNil(try Stream(remoteStream: remote).videoTitle)
    }
}
