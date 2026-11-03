import SwiftUI

struct SettingsView: View {
  @Bindable var library: Library
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Button(
            library.isUpgrading
              ? "Upgrading Videos…"
              : (library.hasPendingUpgrades
                ? "Resume Quality Upgrades" : "Upgrade All to Max Quality"),
            systemImage: "arrow.up.circle"
          ) {
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
              if let notice = library.backgroundNotice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, 8)
            Button("Stop Upgrades", role: .cancel) { library.cancel() }
          }
        } else if let summary = library.upgradeSummary {
          Section { Text(summary).foregroundStyle(.secondary) }
        }
        if let reason = library.upgradePauseReason {
          Section { Text(reason).foregroundStyle(.secondary) }
        }
        if !library.upgradeErrors.isEmpty {
          Section("Couldn’t Upgrade") {
            ForEach(library.upgradeErrors) { failure in
              VStack(alignment: .leading, spacing: 6) {
                Text(failure.title)
                Text(failure.message).font(.footnote).foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
            }
          }
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
