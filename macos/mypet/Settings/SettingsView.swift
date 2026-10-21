import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case pets, appearance, behavior, general, about
    var id: Self { self }

    var title: String {
        switch self {
        case .pets: return "Pets"
        case .appearance: return "Appearance"
        case .behavior: return "Behaviour"
        case .general: return "General"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .pets: return "pawprint"
        case .appearance: return "paintpalette"
        case .behavior: return "figure.run"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

/// Everything the settings panes read. Passed as environment objects.
struct SettingsView: View {
    @EnvironmentObject var store: SettingsStore
    // `State` is used as a plain DynamicProperty rather than via `@State`: on the macOS 27 SDK
    // `@State` is a macro whose plugin ships only with full Xcode, and this keeps the
    // Command Line Tools build working. Behaviour is identical.
    private let section = State<SettingsSection?>(initialValue: .pets)

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: section.projectedValue) { s in
                Label(s.title, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            Group {
                switch section.wrappedValue ?? .pets {
                case .pets: PetsPane()
                case .appearance: AppearancePane()
                case .behavior: BehaviorPane()
                case .general: GeneralPane()
                case .about: AboutPane()
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 700, minHeight: 520)
    }
}

/// Convenience bindings into the store.
extension SettingsStore {
    func binding<T>(_ path: WritableKeyPath<PetSettings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: path] },
                set: { v in self.update { $0[keyPath: path] = v } })
    }
}

// MARK: - Pets

struct PetsPane: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var metrics: MetricsStore

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 12)]

    var body: some View {
        let slot = store.settings.menuBar
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 18) {
                    AnimatedPetPreview(petID: slot.petID, state: .run,
                                       settings: store.settings, metrics: metrics.latest,
                                       facing: store.settings.facing)
                        .frame(width: 128, height: 128)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.5)))
                        .accessibilityLabel("Live preview of \(SpriteLibrary.shared.pet(slot.petID)?.name ?? "pet")")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(SpriteLibrary.shared.pet(slot.petID)?.name ?? "—").font(.title2.weight(.semibold))
                        Text("Runs in the menu bar. Its colour follows memory; its pace follows CPU.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let m = metrics.latest {
                            let score = store.settings.memoryScore(m)
                            Label("\(store.settings.memoryMode.title): \(Int(score.rounded()))",
                                  systemImage: "memorychip")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Text("Gallery").font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SpriteLibrary.shared.pets, id: \.id) { pet in
                        PetCard(pet: pet, selected: pet.id == slot.petID, settings: store.settings) {
                            store.update { $0.menuBar.petID = pet.id }
                        }
                    }
                }
                Text("Add your own pets by placing a folder with a manifest.json and sprite strips in ~/Library/Application Support/MyPet/Pets.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(20)
        }
    }
}

struct PetCard: View {
    let pet: PetSprites
    let selected: Bool
    let settings: PetSettings
    let action: () -> Void
    private let hoverState = State(initialValue: false) // see SettingsView
    private var hovering: Bool { hoverState.wrappedValue }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Only the focused card animates: seven timers would wake the CPU for nothing.
                AnimatedPetPreview(petID: pet.id, state: .run, animated: selected || hovering,
                                   settings: settings, metrics: nil)
                    .frame(width: 72, height: 72)
                Text(pet.name).font(.callout)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovering ? 0.06 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hoverState.wrappedValue = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(selected ? "\(pet.name), selected" : pet.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var metrics: MetricsStore

    var body: some View {
        Form {
            Section {
                Picker("Facing", selection: store.binding(\.facing)) {
                    ForEach(PetFacing.allCases) { f in
                        Label(f.title, systemImage: f.symbol).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Direction")
            } footer: {
                Text(store.settings.facing == .turnAround
                     ? "The pet turns around every 6–14 seconds."
                     : "Mirror the pet so it runs to the \(store.settings.facing == .left ? "left" : "right").")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Colour pets by memory", isOn: store.binding(\.gradientEnabled))
                if store.settings.gradientEnabled {
                    GradientBar(settings: store.settings,
                                marker: metrics.latest.map { store.settings.memoryScore($0) })
                        .padding(.vertical, 4)
                    HStack {
                        ForEach(0..<4, id: \.self) { i in
                            ColorPicker(["Low", "Medium", "High", "Critical"][i], selection: colorBinding(i),
                                        supportsOpacity: false)
                        }
                    }
                    ThresholdSliders()
                    Button("Restore Default Colours") {
                        store.update {
                            $0.gradientColors = PetSettings.defaultColors
                            $0.thresholds = PetSettings.defaultThresholds
                        }
                    }
                }
            } header: {
                Text("Memory gradient")
            } footer: {
                Text(store.settings.gradientEnabled
                     ? "Colours blend smoothly in a perceptual colour space — no flicker or sudden jumps."
                     : "Pets use their natural colours.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func colorBinding(_ i: Int) -> Binding<Color> {
        Binding(get: { store.settings.gradientColors[i].color },
                set: { c in store.update { $0.gradientColors[i] = RGB(c) } })
    }
}

struct ThresholdSliders: View {
    @EnvironmentObject var store: SettingsStore
    private let names = ["Green → Yellow", "Yellow → Orange", "Orange → Red"]

    var body: some View {
        ForEach(0..<3, id: \.self) { i in
            LabeledSlider(title: names[i], value: binding(i), range: 5...95, step: 1, format: { "\(Int($0))%" })
        }
    }

    private func binding(_ i: Int) -> Binding<Double> {
        Binding(get: { store.settings.thresholds[i] },
                set: { v in
                    store.update {
                        var t = $0.thresholds
                        t[i] = v
                        $0.thresholds = PetSettings.sanitizeThresholds(t)
                    }
                })
    }
}

/// Gradient strip sampled from the Rust engine, with threshold ticks and the live score.
struct GradientBar: View {
    let settings: PetSettings
    let marker: Double?

    var body: some View {
        let stops = (0...24).map { i -> Gradient.Stop in
            let v = Double(i) / 24 * 100
            return .init(color: settings.gradientColor(at: v), location: v / 100)
        }
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
                    ForEach(settings.thresholds, id: \.self) { t in
                        Rectangle().fill(.white.opacity(0.7)).frame(width: 1)
                            .offset(x: geo.size.width * t / 100)
                    }
                    if let marker {
                        Circle().fill(.white).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.black.opacity(0.35)))
                            .offset(x: geo.size.width * min(max(marker, 0), 100) / 100 - 6)
                            .animation(.easeOut(duration: 0.8), value: marker)
                    }
                }
            }
            .frame(height: 14)
            HStack {
                Text("0%"); Spacer(); Text("100%")
            }
            .font(.caption2).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Memory colour gradient")
        .accessibilityValue(marker.map { "Current score \(Int($0))" } ?? "")
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                    .accessibilityLabel(title)
                    .accessibilityValue(format(value))
                Text(format(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

// MARK: - Behaviour

struct BehaviorPane: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Memory monitoring") {
                Picker("Colour by", selection: store.binding(\.memoryMode)) {
                    ForEach(MemoryMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(store.settings.memoryMode.explanation)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Speed") {
                Toggle("Speed follows CPU usage", isOn: store.binding(\.menuBar.cpuDrivenSpeed))
                if store.settings.menuBar.cpuDrivenSpeed {
                    Text("Low CPU: slow · Medium: normal · High: fast")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    LabeledSlider(title: "Speed", value: store.binding(\.menuBar.manualSpeed),
                                  range: PetSettings.speedRange, step: 0.25, format: { String(format: "%.2g×", $0) })
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

struct GeneralPane: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var login: LoginItemManager
    @EnvironmentObject var metrics: MetricsStore
    @EnvironmentObject var updates: UpdateController

    var body: some View {
        Form {
            UpdatesSection()
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { login.isEnabled || login.needsApproval },
                                                        set: { login.setEnabled($0) }))
                if login.needsApproval {
                    HStack {
                        Text("Approve \(AppInfo.name) in System Settings → Login Items.").font(.caption)
                        Button("Open…") { login.openSystemSettings() }.controlSize(.small)
                    }
                }
                if let err = login.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Performance") {
                Toggle("Pause animation", isOn: store.binding(\.paused))
                Toggle("Battery saver", isOn: store.binding(\.batterySaver))
                Text("On battery or in Low Power Mode, pets animate at a lower frame rate and metrics are sampled less often.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Low-CPU menu bar animation", isOn: store.binding(\.lowCPUMenuBar))
                Text("Uses about 15× less CPU. If the menu-bar pet ever looks frozen on your Mac, turn this off.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledSlider(title: "Sample every", value: store.binding(\.samplingInterval),
                              range: PetSettings.intervalRange, step: 0.5, format: { String(format: "%.1f s", $0) })
            }
            Section("Live statistics") {
                LiveStatsView(metrics: metrics, settings: store.settings)
            }
            Section {
                Button("Reset All Settings", role: .destructive) { store.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .onAppear { login.refresh() }
    }
}

// MARK: - Updates

struct UpdatesSection: View {
    @EnvironmentObject var updates: UpdateController

    var body: some View {
        Section {
            LabeledContent("Current version", value: updates.currentVersion)
            if updates.isConfigured {
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                Toggle("Download and install updates automatically", isOn: $updates.automaticallyDownloads)
                    .disabled(!updates.automaticallyChecks)
                HStack {
                    Text(lastCheckText).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                }
            } else {
                Text("This build can’t update itself because it was built without an update signing key. Get new versions from GitHub Releases.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Releases Page") { NSWorkspace.shared.open(UpdateController.releasesPage) }
            }
        } header: {
            Text("Updates")
        } footer: {
            if updates.isConfigured {
                Text("Updates come from GitHub Releases and are verified with a digital signature before installing. Your settings and pets are kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var lastCheckText: String {
        guard let date = updates.lastUpdateCheck else { return "Never checked" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Last checked \(f.localizedString(for: date, relativeTo: Date()))"
    }
}

// MARK: - About

enum AppInfo {
    /// The name people see (Finder, Spotlight, menus). Identifiers stay lowercase: com.erag.mypet.
    static let name = "MyPet"
    static let tagline = "Your Mac’s Little Companion."
}

enum ProjectLinks {
    static let author = URL(string: "https://github.com/eramitgupta")!
    static let sponsor = URL(string: "https://github.com/sponsors/eramitgupta")!
}

struct AboutPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 14) {
                AnimatedPetPreview(petID: "cat", state: .run, settings: PetSettings(), metrics: nil)
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text(AppInfo.name).font(.largeTitle.weight(.semibold))
                    Text(AppInfo.tagline).font(.title3).foregroundStyle(.secondary)
                }
                Text("Version \(version)")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Text("Animated pets that react to your Mac's CPU and memory.")
                    .multilineTextAlignment(.center)
                    .font(.callout).foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("Developed by")
                        .foregroundStyle(.secondary)
                    // Link opens the URL in the default browser.
                    Link("@eramitgupta", destination: ProjectLinks.author)
                        .help(ProjectLinks.author.absoluteString)
                }
                .font(.callout)
                .padding(.top, 4)

                Button {
                    NSWorkspace.shared.open(ProjectLinks.sponsor)
                } label: {
                    Label {
                        Text("Sponsor on GitHub")
                    } icon: {
                        Image(systemName: "heart.fill").foregroundStyle(.pink)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help(ProjectLinks.sponsor.absoluteString)
                .accessibilityHint("Opens GitHub Sponsors in your browser")
            }

            Spacer(minLength: 20)

            VStack(spacing: 3) {
                Text("MIT License · Rust + SwiftUI + AppKit")
                Text("Engine ABI v\(RustBridge.libraryABI)")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 30)
    }
}
