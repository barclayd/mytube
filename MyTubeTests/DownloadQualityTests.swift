import Testing

@testable import MyTube

struct DownloadQualityTests {
  @Test func choosesHDInsteadOfCombinedSD() {
    #expect(DownloadQuality.fullHD.resolution(from: [144, 360, 720, 1080, 1440, 2160]) == 1080)
  }
  @Test func maximumUsesHighestSourceBeyondNormalPreference() {
    #expect(DownloadQuality.maximum.resolution(from: [360, 1080, 2160, 4320]) == 4320)
    #expect(DownloadQuality.maximum.resolution(from: [360]) == 360)
    #expect(DownloadQuality.maximum.resolution(from: []) == nil)
  }
  @Test func respectsSmallerFilePreference() {
    #expect(DownloadQuality.hd.resolution(from: [360, 720, 1080, 2160]) == 720)
  }
  @Test func usesAvailableResolutionWithoutUpscaling() {
    #expect(DownloadQuality.fullHD.resolution(from: [144, 240, 360]) == 360)
    #expect(DownloadQuality.ultraHD.resolution(from: [720, 1440]) == 1440)
  }
  @Test func rejectsUnavailableOrOverLimitSources() {
    #expect(DownloadQuality.hd.resolution(from: [1080, 2160]) == nil)
    #expect(DownloadQuality.fullHD.resolution(from: [0, -1]) == nil)
  }
}
