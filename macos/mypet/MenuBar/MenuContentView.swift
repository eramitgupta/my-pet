import SwiftUI

/// The compact dropdown shown from the menu-bar pet.
struct MenuContentView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var metrics: MetricsStore
    @ObservedObject var updates: UpdateController
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppInfo.name).font(.headline)
                    Text(AppInfo.tagline).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.update { $0.facing = $0.facing.flipped }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.borderless)
                .help("Flip the pet's direction")
                .accessibilityLabel("Flip pet direction")
                Toggle(isOn: binding(\.paused)) {
                    Text("Pause")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Pause all pet animation")
            }

            LiveStatsView(metrics: metrics, settings: store.settings)

            Divider()

            Picker("Colour by", selection: binding(\.memoryMode)) {
                ForEach(MemoryMode.allCases) { Text($0.title).tag($0) }
            }
            .controlSize(.small)

            Divider()

            HStack {
                Button("Settings…", action: openSettings)
                    .keyboardShortcut(",", modifiers: .command)
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .disabled(updates.isConfigured && !updates.canCheckForUpdates)
                    .help("Check GitHub for a newer version of \(AppInfo.name)")
                Spacer()
                Button("Quit \(AppInfo.name)", action: quit)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 290)
    }

    private func binding<T>(_ path: WritableKeyPath<PetSettings, T>) -> Binding<T> {
        Binding(get: { store.settings[keyPath: path] },
                set: { v in store.update { $0[keyPath: path] = v } })
    }
}
