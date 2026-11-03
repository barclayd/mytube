import SwiftUI

struct SettingsView: View {
  @Bindable var library: Library
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Button("Upgrade All to Max Quality", systemImage: "arrow.up.circle") {
            library.upgradeAllToMaximumQuality()
          }
          .disabled(library.videos.isEmpty || library.isDownloading || library.isUpgrading)
          .accessibilityIdentifier("upgrade-all-videos")
        } header: {
          Text("Downloads")
        } footer: {
          Text(
            "Downloads the highest compatible quality for every saved video. Larger files need more storage. Existing copies are kept until each upgrade finishes."
          )
        }
        if library.isUpgrading {
          Section("Upgrading") {
            VStack(alignment: .leading, spacing: 12) {
              Text("Video \(library.upgradeIndex) of \(library.upgradeTotal)")
                .font(.subheadline).foregroundStyle(.secondary)
              Text(library.activityTitle)
              HStack {
                Text(library.activityStatus).font(.footnote).foregroundStyle(.secondary)
                if library.progress == nil { ProgressView().controlSize(.small) }
              }
              if let progress = library.progress { ProgressView(value: progress) }
            }
            .padding(.vertical, 8)
            Button("Stop Upgrades", role: .cancel) { library.cancel() }
          }
        } else if let summary = library.upgradeSummary {
          Section { Text(summary).foregroundStyle(.secondary) }
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
  }
}
