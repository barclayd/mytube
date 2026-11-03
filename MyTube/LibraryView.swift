import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
  @Bindable var library: Library
  @State private var playback = PlaybackSession()
  @State private var selection: SavedVideo.ID?
  @State private var showingAddVideo = false
  @State private var draftLink = ""
  @State private var search = ""
  @State private var pendingDeletion: SavedVideo?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  private var visibleVideos: [SavedVideo] {
    library.videos.filter { search.isEmpty || $0.title.localizedStandardContains(search) }
  }
  private var selectedVideo: SavedVideo? { library.videos.first { $0.id == selection } }

  var body: some View {
    libraryNavigation
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
        if new > old { draftLink = "" }
      }
      .sheet(isPresented: $showingAddVideo) {
        AddVideoView(library: library, link: $draftLink)
          .presentationDetents([.height(500), .large])
          .presentationDragIndicator(.visible)
      }
  }

  private var libraryNavigation: some View {
    NavigationSplitView {
      Group {
        if library.videos.isEmpty {
          emptyLibrary
        } else {
          videoList
        }
      }
      .navigationTitle("Downloads")
      .searchable(text: $search, prompt: "Search downloads")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Add Video", systemImage: "plus") { showingAddVideo = true }
            .accessibilityIdentifier("add-video")
        }
        if horizontalSizeClass == .compact {
          ToolbarItem(placement: .bottomBar) {
            pasteButton
          }
          .visibilityPriority(.high)
        }
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if library.isDownloading { downloadStatus }
      }
      .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)

    } detail: {
      Group {
        if let video = selectedVideo {
          PlaybackView(video: video, url: library.url(for: video), session: playback) {
            selection = video.id
          }
        } else {
          ContentUnavailableView {
            Label("Select a Video", systemImage: "play.rectangle")
          } description: {
            Text("Choose a download to start watching.")
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .bottomBar) {
          pasteButton
        }
        .visibilityPriority(.high)
      }
    }
    .navigationSplitViewStyle(.balanced)
    .animation(
      reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1), value: library.isDownloading
    )
  }

  private var pasteButton: some View {
    Button("Paste & Download", systemImage: "document.on.clipboard", action: pasteAndDownload)
      .labelStyle(.iconOnly)
      .disabled(library.isDownloading)
      .accessibilityIdentifier("paste-and-download")
  }

  private func pasteAndDownload() {
    // Read the clipboard only in response to this explicit user action.
    guard let value = UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString,
      let parsed = YouTubeLink(value)
    else {
      library.errorMessage = "Copy a YouTube video or Shorts link, then tap Paste & Download."
      return
    }
    draftLink = value
    library.download(parsed)
  }

  private var emptyLibrary: some View {
    ContentUnavailableView {
      Label("No Downloads", systemImage: "arrow.down.circle")
    } description: {
      Text("Add a YouTube video to watch it offline.")
    } actions: {
      Button("Add Video", systemImage: "plus") { showingAddVideo = true }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
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
        Text("Saved Videos")
      } footer: {
        Text(librarySummary)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.top, 8)
      }
    }
    .listStyle(.insetGrouped)
    .overlay {
      if visibleVideos.isEmpty { ContentUnavailableView.search(text: search) }
    }
    .scrollDismissesKeyboard(.interactively)
  }

  private var librarySummary: String {
    let count = library.videos.count
    let bytes = library.videos.reduce(Int64(0)) { $0 + $1.bytes }
    return
      "\(count) \(count == 1 ? "video" : "videos") · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) on this device"
  }

  private var downloadStatus: some View {
    HStack(spacing: 14) {
      ZStack {
        Circle().stroke(.quaternary, lineWidth: 3)
        if let progress = library.progress {
          Circle().trim(from: 0, to: min(max(progress, 0), 1))
            .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
        } else {
          ProgressView()
        }
      }
      .frame(width: 30, height: 30)
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(library.activityTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
        Text(
          library.progress.map { "\(library.activityStatus) · \(Int($0 * 100))%" }
            ?? library.activityStatus
        )
        .font(.caption).foregroundStyle(.secondary)
        if let notice = library.backgroundNotice {
          Text(notice).font(.caption2).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
      Button("Cancel Download", systemImage: "xmark") { library.cancel() }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .frame(minWidth: 44, minHeight: 44)
    }
    .padding(16)
    .background(.regularMaterial, in: .rect(cornerRadius: 24))
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
  }
}

private struct AddVideoView: View {
  @Bindable var library: Library
  @Binding var link: String
  @State private var attemptedDownload = false
  @FocusState private var editingLink: Bool
  @Environment(\.dismiss) private var dismiss

  private var validLink: YouTubeLink? { YouTubeLink(link) }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack(spacing: 12) {
            Image(systemName: "link").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("YouTube URL", text: $link)
              .keyboardType(.URL)
              .textContentType(.URL)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .submitLabel(.go)
              .focused($editingLink)
              .onSubmit(startDownload)
              .accessibilityLabel("YouTube URL")
              .accessibilityIdentifier("youtube-link")
            if link.isEmpty {
              PasteButton(payloadType: String.self) { values in
                if let value = values.first { link = value }
              }
              .tint(.secondary)
              .labelStyle(.iconOnly)
              .accessibilityLabel("Paste YouTube link")
            } else {
              Button("Clear URL", systemImage: "xmark.circle.fill") { link = "" }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
            }
          }
          .frame(minHeight: 44)
        } header: {
          Text("Video Link")
        } footer: {
          if attemptedDownload && validLink == nil {
            Text("Enter a valid YouTube video or Shorts URL.")
              .foregroundStyle(.red)
              .accessibilityIdentifier("invalid-link")
          } else {
            Text("Paste a YouTube video or Shorts link. The video will be saved on this device.")
          }
        }
        Section {
          Picker("Quality", selection: $library.preferredQuality) {
            ForEach(DownloadQuality.allCases) { quality in
              Text(quality.label).tag(quality)
            }
          }
          .accessibilityIdentifier("download-quality")
        } footer: {
          Text(
            "Uses the highest available resolution up to your choice. Higher quality needs more storage. Paste & Download uses this setting too."
          )
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle("Add Video")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button(action: startDownload) {
          Label(
            library.isDownloading ? "Download in Progress" : "Download Video",
            systemImage: "arrow.down"
          )
          .font(.body.weight(.semibold))
          .frame(maxWidth: .infinity)
          .frame(minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(validLink == nil || library.isDownloading)
        .accessibilityIdentifier("download-video")
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
      }
    }
    .onChange(of: link) { attemptedDownload = false }
    .presentationSizing(.form)
  }

  private func startDownload() {
    attemptedDownload = true
    guard let validLink, !library.isDownloading else { return }
    library.download(validLink)
    dismiss()
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
        Text("\(video.subtitle) · \(video.qualityLabel)").font(.caption).foregroundStyle(.secondary)
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
  let session: PlaybackSession
  var onRestore: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        NativePlayer(session: session, onRestore: onRestore)
          .aspectRatio(16 / 9, contentMode: .fit)
          .clipShape(.rect(cornerRadius: 18))
        VStack(alignment: .leading, spacing: 8) {
          Text(video.title).font(.title3.weight(.semibold))
          Text("\(video.subtitle) · \(video.qualityLabel)").foregroundStyle(.secondary)
          if let dimensions = video.dimensionsLabel {
            Text(dimensions).font(.caption).foregroundStyle(.secondary)
          }
          Label("Available offline", systemImage: "checkmark.circle.fill")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .padding(20)
      .frame(maxWidth: 1000)
      .frame(maxWidth: .infinity)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Now Playing")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ShareLink(item: url) { Label("Share Video", systemImage: "square.and.arrow.up") }
    }
    .task(id: video.filename) { session.open(video, url: url) }
    .onDisappear {
      if !session.isPictureInPictureActive && !session.isFullScreenActive { session.player.pause() }
    }
  }
}
