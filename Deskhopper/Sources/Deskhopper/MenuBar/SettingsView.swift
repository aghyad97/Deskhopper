import SwiftUI

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, spaces, about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .spaces: return "Spaces"
        case .about: return "About"
        }
    }
}

// MARK: - Setting Row

struct SettingRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Setting Toggle Row

struct SettingToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingRow {
            Toggle(isOn: $isOn) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

// MARK: - Setting Group

struct SettingGroup<Content: View>: View {
    let header: String?
    let content: Content

    init(header: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
            }
            VStack(spacing: 1) {
                content
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var spaceManager: SpaceManager
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Segmented tab bar
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    switch selectedTab {
                    case .general:
                        generalTab
                    case .appearance:
                        appearanceTab
                    case .spaces:
                        spacesTab
                    case .about:
                        aboutTab
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 380, height: 480)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(spacing: 16) {
            SettingGroup(header: "Layout") {
                // Position
                SettingRow {
                    HStack {
                        Text("Position")
                        Spacer()
                        Picker("", selection: $settingsManager.panelPosition) {
                            ForEach(PanelPosition.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }

                // Orientation
                SettingRow {
                    HStack {
                        Text("Orientation")
                        Spacer()
                        Picker("", selection: $settingsManager.panelOrientation) {
                            ForEach(PanelOrientation.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
            }

            SettingGroup(header: "Behavior") {
                // Panel Mode
                SettingRow {
                    HStack {
                        Text("Panel Mode")
                        Spacer()
                        Picker("", selection: $settingsManager.panelMode) {
                            ForEach(PanelMode.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }

                // Transition Style
                SettingRow {
                    HStack {
                        Text("Transition Style")
                        Spacer()
                        Picker("", selection: $settingsManager.panelTransitionStyle) {
                            ForEach(PanelTransitionStyle.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
            }

            SettingGroup(header: "System") {
                SettingToggleRow(title: "Launch at Login", isOn: $settingsManager.launchAtLogin)

                SettingToggleRow(title: "Show in Dock", isOn: Binding(
                    get: { settingsManager.showInDock },
                    set: { newValue in
                        settingsManager.showInDock = newValue
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
                ))
            }
        }
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        VStack(spacing: 16) {
            SettingGroup(header: "Opacity") {
                // Idle Opacity
                SettingRow {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Idle Opacity")
                            Spacer()
                            Text("\(Int(settingsManager.idleOpacity * 100))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settingsManager.idleOpacity, in: 0...1)
                    }
                }

                // Hover Opacity
                SettingRow {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Hover Opacity")
                            Spacer()
                            Text("\(Int(settingsManager.hoverOpacity * 100))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settingsManager.hoverOpacity, in: 0...1)
                    }
                }

                // Transition Duration
                SettingRow {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Transition Duration")
                            Spacer()
                            Text(String(format: "%.2fs", settingsManager.opacityTransitionDuration))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settingsManager.opacityTransitionDuration, in: 0.05...1.0)
                    }
                }
            }

            SettingGroup(header: "Display") {
                SettingToggleRow(title: "Compact Mode", isOn: $settingsManager.compactMode)

                SettingToggleRow(title: "Show Previews", isOn: $settingsManager.showPreviews)

                if settingsManager.showPreviews {
                    SettingRow {
                        HStack {
                            Text("Preview Size")
                            Spacer()
                            Picker("", selection: $settingsManager.previewSize) {
                                ForEach(PreviewSize.allCases) { item in
                                    Text(item.displayName).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 180)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Spaces Tab

    private var spacesTab: some View {
        VStack(spacing: 16) {
            SettingGroup(header: "Space Names") {
                if spaceManager.spaces.isEmpty {
                    SettingRow {
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                                Text("No spaces detected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 12)
                            Spacer()
                        }
                    }
                } else {
                    ForEach(spaceManager.spaces) { space in
                        SettingRow {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(space.id == spaceManager.activeSpaceID ? Color.green : Color.clear)
                                    .frame(width: 6, height: 6)

                                if space.isFullscreen {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }

                                Text("Desktop \(space.index)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .frame(width: 70, alignment: .leading)

                                TextField(
                                    "Name",
                                    text: Binding(
                                        get: { settingsManager.spaceNames[space.index] ?? "" },
                                        set: { settingsManager.spaceNames[space.index] = $0.isEmpty ? nil : $0 }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                            }
                        }
                    }
                }
            }

            Divider()
                .padding(.horizontal, 4)

            SettingGroup(header: "Hotkeys") {
                SettingToggleRow(title: "Enable Global Hotkeys", isOn: $settingsManager.globalHotkeysEnabled)

                if settingsManager.globalHotkeysEnabled {
                    SettingRow {
                        HStack {
                            Text("Modifier Key")
                            Spacer()
                            Picker("", selection: $settingsManager.hotkeyModifier) {
                                ForEach(HotkeyModifier.allCases) { item in
                                    Text(item.displayName).tag(item)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }
                    }

                    SettingRow {
                        Text("Press \(settingsManager.hotkeyModifier.displayName) + 1\u{2013}9 to switch spaces")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if settingsManager.globalHotkeysEnabled {
                SettingGroup(header: "Permissions") {
                    SettingRow {
                        HStack(spacing: 8) {
                            if AXIsProcessTrusted() {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Accessibility permission granted")
                                    .font(.system(size: 12))
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Accessibility permission required")
                                        .font(.system(size: 12))
                                    Button("Open System Settings") {
                                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .font(.caption)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)

                Text("Deskhopper")
                    .font(.title3)
                    .fontWeight(.semibold)

                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                   let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                    Text("Version \(version) (\(build))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("A floating desktop switcher for macOS.\nQuickly view and switch between virtual desktops.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Link("GitHub Repository", destination: URL(string: "https://github.com/aghyad97/Deskhopper")!)
                    .font(.caption)

                Text("MIT License")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { NSApp.terminate(nil) }) {
                Text("Quit Deskhopper")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }
}
