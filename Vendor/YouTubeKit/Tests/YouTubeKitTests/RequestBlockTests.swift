import XCTest
@testable import YouTubeKit

final class RequestBlockTests: XCTestCase {
    private func response(_ json: String) throws -> InnerTube.VideoInfo {
        try JSONDecoder().decode(InnerTube.VideoInfo.self, from: Data(json.utf8))
    }

    func testReportsExplicitBotChallenge() throws {
        let blocked = try response(#"{"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"Sign in to confirm you’re not a bot"}}"#)
        XCTAssertThrowsError(try Extraction.checkForRequestBlock(videoID: "jNQXAC9IVRw", responses: [blocked])) {
            XCTAssertEqual($0 as? YouTubeKitError, .requestBlocked)
        }
    }

    func testDoesNotMisclassifyPrivateOrAgeRestrictedVideos() throws {
        for reason in ["Private video", "Sign in to confirm your age"] {
            let json = try JSONSerialization.data(withJSONObject: ["playabilityStatus": ["status": "LOGIN_REQUIRED", "reason": reason]])
            let response = try JSONDecoder().decode(InnerTube.VideoInfo.self, from: json)
            XCTAssertNoThrow(try Extraction.checkForRequestBlock(videoID: "jNQXAC9IVRw", responses: [response]))
        }
    }

    func testKeepsUsableResponseFromAnotherClient() throws {
        let blocked = try response(#"{"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"Sign in to confirm you’re not a bot"}}"#)
        let usable = try response(#"{"videoDetails":{"videoId":"jNQXAC9IVRw","title":"Me at the zoo","thumbnail":{"thumbnails":[]}}}"#)
        XCTAssertNoThrow(try Extraction.checkForRequestBlock(videoID: "jNQXAC9IVRw", responses: [blocked, usable]))
    }
}
