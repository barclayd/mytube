import SwiftUI

@main
struct MyTubeApp: App {
  @State private var library = Library()
  var body: some Scene {
    WindowGroup { LibraryView(library: library) }
  }
}
