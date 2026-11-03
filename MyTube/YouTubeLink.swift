import Foundation

/// Accept only individual YouTube videos, never arbitrary hosts or playlist URLs.
struct YouTubeLink: Equatable {
  let videoID: String

  init?(_ text: String) {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
      let host = url.host?.lowercased(),
      ["https", "http"].contains(url.scheme?.lowercased() ?? "")
    else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    let candidate: String?
    switch host {
    case "youtu.be", "www.youtu.be":
      candidate = parts.count == 1 ? parts.first : nil
    case "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com":
      if parts == ["watch"] {
        candidate =
          URLComponents(url: url, resolvingAgainstBaseURL: false)?
          .queryItems?.first(where: { $0.name == "v" })?.value
      } else if parts.count == 2, ["shorts", "embed", "live"].contains(parts[0]) {
        candidate = parts[1]
      } else {
        candidate = nil
      }
    default: return nil
    }
    guard let candidate,
      candidate.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    else { return nil }
    videoID = candidate
  }
}
