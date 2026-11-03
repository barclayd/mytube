import Foundation
import Testing

@testable import MyTube

@MainActor struct LibraryTests {
  private func fixture() throws -> (URL, SavedVideo) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let video = SavedVideo(
      id: "jNQXAC9IVRw", title: "A saved video", filename: "video.mp4",
      thumbnailFilename: "video.jpg", savedAt: .now, bytes: 1024, duration: 61, resolution: 360)
    try Data([1, 2, 3]).write(to: directory.appendingPathComponent(video.filename))
    try Data([4]).write(to: directory.appendingPathComponent("video.jpg"))
    try JSONEncoder().encode([video]).write(to: directory.appendingPathComponent("library.json"))
    return (directory, video)
  }

  @Test func restoresAndDeletesLocalMedia() throws {
    let (directory, video) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = Library(directory: directory)
    #expect(library.videos == [video])
    library.delete(video)
    #expect(library.videos.isEmpty)
    #expect(
      !FileManager.default.fileExists(atPath: directory.appendingPathComponent(video.filename).path)
    )
    #expect(
      !FileManager.default.fileExists(atPath: directory.appendingPathComponent("video.jpg").path))
    #expect(Library(directory: directory).videos.isEmpty)
  }

  @Test func ignoresMissingMedia() throws {
    let (directory, video) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.removeItem(at: directory.appendingPathComponent(video.filename))
    #expect(Library(directory: directory).videos.isEmpty)
  }

  @Test func reportsCorruptIndexWithoutOverwritingIt() throws {
    let (directory, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = directory.appendingPathComponent("library.json")
    let corrupt = Data("invalid".utf8)
    try corrupt.write(to: index)
    let library = Library(directory: directory)
    #expect(library.errorMessage != nil)
    #expect(try Data(contentsOf: index) == corrupt)
  }
}
