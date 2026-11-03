import Foundation

/// A resolution ceiling: never upscale or silently label a lower-resolution source as HD.
enum DownloadQuality: Int, CaseIterable, Identifiable, Codable {
  case maximum = 16384
  case small = 360
  case hd = 720
  case fullHD = 1080
  case ultraHD = 2160

  var id: Int { rawValue }
  var label: String {
    switch self {
    case .maximum: "Maximum Available"
    case .small: "360p · Smaller Files"
    case .hd: "720p · HD"
    case .fullHD: "1080p · Full HD"
    case .ultraHD: "2160p · 4K"
    }
  }

  func resolution(from available: [Int]) -> Int? {
    available.filter { $0 > 0 && $0 <= rawValue }.max()
  }
}
