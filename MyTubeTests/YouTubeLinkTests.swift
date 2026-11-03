import Testing

@testable import MyTube

struct YouTubeLinkTests {
  @Test(arguments: [
    "https://www.youtube.com/watch?v=jNQXAC9IVRw&list=123",
    "https://youtu.be/jNQXAC9IVRw?t=12",
    "https://m.youtube.com/watch?v=jNQXAC9IVRw",
    "https://youtube.com/shorts/jNQXAC9IVRw",
    "https://youtube.com/live/jNQXAC9IVRw",
    "  https://youtube.com/embed/jNQXAC9IVRw\n",
  ])
  func validLinks(_ value: String) {
    #expect(YouTubeLink(value)?.videoID == "jNQXAC9IVRw")
  }

  @Test(arguments: [
    "", "jNQXAC9IVRw", "https://youtube.com/playlist?list=123",
    "https://youtube.com.evil.test/watch?v=jNQXAC9IVRw",
    "https://example.com/watch?v=jNQXAC9IVRw", "file:///watch?v=jNQXAC9IVRw",
    "https://youtube.com/watch?v=short", "https://youtu.be/jNQXAC9IVRw/extra",
  ])
  func invalidLinks(_ value: String) { #expect(YouTubeLink(value) == nil) }
}
