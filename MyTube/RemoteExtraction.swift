import Foundation
import YouTubeKit

struct RemoteExtractionConfiguration: Sendable {
  let endpoint: URL
  let token: String

  init?(bundle: Bundle = .main) {
    guard let value = bundle.object(forInfoDictionaryKey: "MyTubeRemoteURL") as? String,
      let url = URL(string: value), url.scheme == "https", url.host != nil,
      let token = bundle.object(forInfoDictionaryKey: "MyTubeRemoteToken") as? String,
      !token.isEmpty
    else { return nil }
    self.endpoint = url
    self.token = token
  }

  var methods: [YouTube.ExtractionMethod] { [.remote(serverURL: endpoint)] }
  var headers: [String: String] { ["Authorization": "Bearer \(token)"] }
}
