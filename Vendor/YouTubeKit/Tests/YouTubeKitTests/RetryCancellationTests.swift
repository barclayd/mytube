import XCTest
@testable import YouTubeKit

final class RetryCancellationTests: XCTestCase {
    func testCancellationDoesNotStartAnotherExtractor() async {
        do {
            _ = try await Task<Int, Never>.retry(with: [0, 1]) { method in
                if method == 0 { throw CancellationError() }
                XCTFail("Cancelled extraction must not start a fallback request")
                return 1
            }
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
