import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
  @Bindable var library: Library
  @State private var selection: SavedVideo.ID?
  @State private var link = ""
  @State private var search = ""
  @State private var pendingDeletion: SavedVideo?
  @FocusState private var editingLink: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var visibleVideos: [SavedVideo] {
    library.videos.filter { search.isEmpty || $0.title.localizedStandardContains(search) }
  }
  private var selectedVideo: SavedVideo? { library.videos.first { $0.id == selection } }

  var body: some View {
    NavigationSplitView {
      Group {
        if library.videos.isEmpty {
          emptyLibrary
        } else {
          videoList
        }
      }
      .navigationTitle("Downloads")
      .safeAreaInset(edge: .bottom, spacing: 0) { composer }
      .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)

    } detail: {
      if let video = selectedVideo {
        PlaybackView(video: video, url: library.url(for: video))
      } else {
        ContentUnavailableView {
          Label("A little time offline.", systemImage: "play.rectangle")
        } description: {
          Text("Choose a video from your library.\nMake room for what you love.")
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .alert(
      "Unable to complete action",
      isPresented: Binding(
        get: { library.errorMessage != nil },
        set: { if !$0 { library.errorMessage = nil } }
      )
    ) {
      Button("OK") { library.errorMessage = nil }
    } message: {
      Text(library.errorMessage ?? "")
    }
    .confirmationDialog(
      "Delete this download?",
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } }
      ), titleVisibility: .visible
    ) {
      if let video = pendingDeletion {
        Button("Delete Download", role: .destructive) {
          if selection == video.id { selection = nil }
          library.delete(video)
          pendingDeletion = nil
        }
      }
    } message: {
      Text("The video will be removed from this device.")
    }
    .sensoryFeedback(.success, trigger: library.videos.count) { old, new in new > old }
    .onChange(of: library.videos.count) { old, new in
      if new > old { link = "" }
    }
    .onOpenURL { url in
      // Accept pasted/shared links without starting a download unexpectedly.
      link = url.absoluteString
    }
  }

  private var emptyLibrary: some View {
    GeometryReader { geometry in
      ScrollView {
        emptyContent(minimumHeight: geometry.size.height)
      }
      .scrollIndicators(.hidden)
    }
  }

  private func emptyContent(minimumHeight: CGFloat) -> some View {
    VStack(spacing: 18) {
      Spacer(minLength: 24)
      Image(systemName: "arrow.down")
        .font(.system(size: 36, weight: .medium))
        .foregroundStyle(.tint)
        .frame(width: 88, height: 88)
        .background(.tint.opacity(0.08), in: .rect(cornerRadius: 26))
        .padding(.bottom, 6)
        .accessibilityHidden(true)
      Text("Good videos.\nYours to keep.")
        .font(.largeTitle.bold())
        .tracking(-0.8)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      Text("Add a YouTube link to watch\nwhenever, wherever.")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 24)
      Label("Saved on this device", systemImage: "iphone")
        .font(.footnote)
        .foregroundStyle(.tertiary)
        .padding(.bottom, 24)
    }
    .padding(.horizontal, 24)
    .frame(maxWidth: .infinity, minHeight: minimumHeight)
    .background(Color(.systemBackground))
  }

  private var videoList: some View {
    List(selection: $selection) {
      Section {
        ForEach(visibleVideos) { video in
          NavigationLink(value: video.id) {
            VideoRow(video: video, thumbnail: library.thumbnail(for: video))
          }
          .swipeActions {
            Button("Delete", role: .destructive) { pendingDeletion = video }
          }
          .contextMenu {
            ShareLink(item: library.url(for: video)) {
              Label("Share Video", systemImage: "square.and.arrow.up")
            }
            Button("Delete Download", systemImage: "trash", role: .destructive) {
              pendingDeletion = video
            }
          }
        }
      } header: {
        Text(
          "\(library.videos.count) \(library.videos.count == 1 ? "video" : "videos") · Available offline"
        )
        .textCase(nil)
      }
    }
    .listStyle(.plain)
    .searchable(text: $search, prompt: "Search downloads")
    .overlay {
      if visibleVideos.isEmpty { ContentUnavailableView.search(text: search) }
    }
    .scrollDismissesKeyboard(.interactively)
  }

  private var composer: some View {
    VStack(spacing: 12) {
      if library.isDownloading {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
              Text(library.activityTitle).font(.subheadline.weight(.medium)).lineLimit(1)
              Text(
                library.progress.map { "Downloading · \(Int($0 * 100))%" }
                  ?? "Preparing your download…"
              )
              .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Cancel", systemImage: "xmark") { library.cancel() }
              .labelStyle(.iconOnly)
              .buttonStyle(.borderless)
              .foregroundStyle(.secondary)
              .frame(minWidth: 44, minHeight: 44)
          }
          if let progress = library.progress {
            ProgressView(value: progress)
          } else {
            ProgressView().frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .contain)
      }
      GlassEffectContainer(spacing: 8) {
        HStack(spacing: 10) {
          HStack(spacing: 10) {
            Image(systemName: "link").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("YouTube link", text: $link)
              .keyboardType(.URL)
              .textContentType(.URL)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .submitLabel(.go)
              .focused($editingLink)
              .onSubmit(startDownload)
              .accessibilityIdentifier("youtube-link")
            if link.isEmpty {
              PasteButton(payloadType: String.self) { strings in
                if let value = strings.first { link = value }
              }
              .labelStyle(.iconOnly)
              .buttonBorderShape(.circle)
              .accessibilityLabel("Paste YouTube link")
            } else {
              Button("Clear link", systemImage: "xmark.circle.fill") { link = "" }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, minHeight: 44)
            }
          }
          .padding(.leading, 18)
          .padding(.trailing, 8)
          .frame(minHeight: 56)
          .glassEffect(.regular, in: .capsule)
          Button(action: startDownload) {
            Image(systemName: "arrow.down")
              .font(.title3.weight(.semibold))
              .frame(width: 40, height: 44)
          }
          .buttonStyle(.glassProminent)
          .buttonBorderShape(.circle)
          .disabled(
            link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || library.isDownloading
          )
          .accessibilityLabel("Download video")
          .accessibilityIdentifier("download-video")
        }
      }
      if !link.isEmpty && YouTubeLink(link) == nil {
        Text("Enter a YouTube video or Shorts link.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 12)
    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: library.isDownloading)
  }

  private func startDownload() {
    guard !library.isDownloading else { return }
    guard let parsed = YouTubeLink(link) else {
      library.errorMessage =
        "Enter a valid YouTube video link, such as youtube.com/watch?v=… or youtu.be/…"
      return
    }
    editingLink = false
    library.download(parsed)
  }
}

private struct VideoRow: View {
  let video: SavedVideo
  let thumbnail: URL?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    HStack(spacing: 14) {
      Group {
        if let thumbnail, let image = UIImage(contentsOfFile: thumbnail.path) {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          Rectangle().fill(.quaternary)
            .overlay { Image(systemName: "play.fill").foregroundStyle(.secondary) }
        }
      }
      .frame(
        width: dynamicTypeSize.isAccessibilitySize ? 72 : 108,
        height: dynamicTypeSize.isAccessibilitySize ? 54 : 68
      )
      .clipShape(.rect(cornerRadius: 12))
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(video.title).font(.body.weight(.medium)).lineLimit(2)
        Text(video.subtitle).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityHint("Play downloaded video")
  }
}

struct PlaybackView: View {
  let video: SavedVideo
  let url: URL
  @State private var player: AVPlayer?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VideoPlayer(player: player)
          .aspectRatio(16 / 9, contentMode: .fit)
          .clipShape(.rect(cornerRadius: 18))
        VStack(alignment: .leading, spacing: 8) {
          Text(video.title).font(.title2.bold())
          Text(video.subtitle).foregroundStyle(.secondary)
          Label("Available offline", systemImage: "checkmark.circle.fill")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .padding(24)
    }
    .navigationTitle("Now Playing")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ShareLink(item: url) { Label("Share Video", systemImage: "square.and.arrow.up") }
    }
    .task(id: video.id) {
      player?.pause()
      player = AVPlayer(url: url)
      try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }
    .onDisappear { player?.pause() }
  }
}
