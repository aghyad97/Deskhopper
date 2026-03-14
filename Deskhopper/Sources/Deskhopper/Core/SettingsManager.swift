import Combine
import Foundation
import ServiceManagement

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private enum Key: String {
        case panelPosition, panelOrientation, panelMode
        case idleOpacity, hoverOpacity, opacityTransitionDuration
        case showPreviews, previewSize, compactMode, panelTransitionStyle
        case spaceNames, globalHotkeysEnabled, hotkeyModifier
        case launchAtLogin, showInDock
        case draggedPositionX, draggedPositionY, hasDraggedPosition
        case customPanelWidth, customPanelHeight, hasCustomPanelSize
    }

    private let defaults: UserDefaults

    @Published var panelPosition: PanelPosition {
        didSet { defaults.set(panelPosition.rawValue, forKey: Key.panelPosition.rawValue) }
    }
    @Published var panelOrientation: PanelOrientation {
        didSet { defaults.set(panelOrientation.rawValue, forKey: Key.panelOrientation.rawValue) }
    }
    @Published var panelMode: PanelMode {
        didSet { defaults.set(panelMode.rawValue, forKey: Key.panelMode.rawValue) }
    }
    @Published var idleOpacity: Double {
        didSet {
            let v = min(max(idleOpacity, 0), 1)
            if v != idleOpacity { idleOpacity = v }
            defaults.set(v, forKey: Key.idleOpacity.rawValue)
        }
    }
    @Published var hoverOpacity: Double {
        didSet {
            let v = min(max(hoverOpacity, 0), 1)
            if v != hoverOpacity { hoverOpacity = v }
            defaults.set(v, forKey: Key.hoverOpacity.rawValue)
        }
    }
    @Published var opacityTransitionDuration: Double {
        didSet {
            let v = min(max(opacityTransitionDuration, 0.05), 1)
            if v != opacityTransitionDuration { opacityTransitionDuration = v }
            defaults.set(v, forKey: Key.opacityTransitionDuration.rawValue)
        }
    }
    @Published var showPreviews: Bool {
        didSet { defaults.set(showPreviews, forKey: Key.showPreviews.rawValue) }
    }
    @Published var previewSize: PreviewSize {
        didSet { defaults.set(previewSize.rawValue, forKey: Key.previewSize.rawValue) }
    }
    @Published var compactMode: Bool {
        didSet { defaults.set(compactMode, forKey: Key.compactMode.rawValue) }
    }
    @Published var panelTransitionStyle: PanelTransitionStyle {
        didSet { defaults.set(panelTransitionStyle.rawValue, forKey: Key.panelTransitionStyle.rawValue) }
    }
    @Published var spaceNames: [Int: String] {
        didSet { saveSpaceNames() }
    }
    @Published var globalHotkeysEnabled: Bool {
        didSet { defaults.set(globalHotkeysEnabled, forKey: Key.globalHotkeysEnabled.rawValue) }
    }
    @Published var hotkeyModifier: HotkeyModifier {
        didSet { defaults.set(hotkeyModifier.rawValue, forKey: Key.hotkeyModifier.rawValue) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin.rawValue)
            updateLoginItem()
        }
    }
    @Published var showInDock: Bool {
        didSet { defaults.set(showInDock, forKey: Key.showInDock.rawValue) }
    }
    @Published var hasDraggedPosition: Bool {
        didSet { defaults.set(hasDraggedPosition, forKey: Key.hasDraggedPosition.rawValue) }
    }
    @Published var draggedPositionX: Double {
        didSet { defaults.set(draggedPositionX, forKey: Key.draggedPositionX.rawValue) }
    }
    @Published var draggedPositionY: Double {
        didSet { defaults.set(draggedPositionY, forKey: Key.draggedPositionY.rawValue) }
    }
    @Published var hasCustomPanelSize: Bool {
        didSet { defaults.set(hasCustomPanelSize, forKey: Key.hasCustomPanelSize.rawValue) }
    }
    @Published var customPanelWidth: Double {
        didSet { defaults.set(customPanelWidth, forKey: Key.customPanelWidth.rawValue) }
    }
    @Published var customPanelHeight: Double {
        didSet { defaults.set(customPanelHeight, forKey: Key.customPanelHeight.rawValue) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.panelPosition = Self.loadEnum(defaults, key: .panelPosition, fallback: .topRight)
        self.panelOrientation = Self.loadEnum(defaults, key: .panelOrientation, fallback: .horizontal)
        self.panelMode = Self.loadEnum(defaults, key: .panelMode, fallback: .alwaysVisible)
        self.previewSize = Self.loadEnum(defaults, key: .previewSize, fallback: .small)
        self.panelTransitionStyle = Self.loadEnum(defaults, key: .panelTransitionStyle, fallback: .instant)
        self.hotkeyModifier = Self.loadEnum(defaults, key: .hotkeyModifier, fallback: .controlOption)
        self.idleOpacity = Self.loadDouble(defaults, key: .idleOpacity, fallback: 1.0, min: 0, max: 1)
        self.hoverOpacity = Self.loadDouble(defaults, key: .hoverOpacity, fallback: 1.0, min: 0, max: 1)
        self.opacityTransitionDuration = Self.loadDouble(defaults, key: .opacityTransitionDuration, fallback: 0.2, min: 0.05, max: 1)
        self.showPreviews = defaults.object(forKey: Key.showPreviews.rawValue) as? Bool ?? true
        self.compactMode = defaults.object(forKey: Key.compactMode.rawValue) as? Bool ?? true
        self.globalHotkeysEnabled = defaults.object(forKey: Key.globalHotkeysEnabled.rawValue) as? Bool ?? true
        self.launchAtLogin = defaults.object(forKey: Key.launchAtLogin.rawValue) as? Bool ?? false
        self.showInDock = defaults.object(forKey: Key.showInDock.rawValue) as? Bool ?? false
        self.hasDraggedPosition = defaults.object(forKey: Key.hasDraggedPosition.rawValue) as? Bool ?? false
        self.draggedPositionX = defaults.double(forKey: Key.draggedPositionX.rawValue)
        self.draggedPositionY = defaults.double(forKey: Key.draggedPositionY.rawValue)
        self.hasCustomPanelSize = defaults.object(forKey: Key.hasCustomPanelSize.rawValue) as? Bool ?? false
        self.customPanelWidth = defaults.double(forKey: Key.customPanelWidth.rawValue)
        self.customPanelHeight = defaults.double(forKey: Key.customPanelHeight.rawValue)
        self.spaceNames = Self.loadSpaceNames(defaults)
    }

    func displayName(forSpaceIndex index: Int) -> String {
        if let name = spaceNames[index], !name.isEmpty { return name }
        return "\(index)"
    }

    func setDraggedPosition(x: Double, y: Double) {
        hasDraggedPosition = true
        draggedPositionX = x
        draggedPositionY = y
    }

    func clearDraggedPosition() {
        hasDraggedPosition = false
        draggedPositionX = 0
        draggedPositionY = 0
    }

    func setCustomPanelSize(width: Double, height: Double) {
        hasCustomPanelSize = true
        customPanelWidth = width
        customPanelHeight = height
    }

    func clearCustomPanelSize() {
        hasCustomPanelSize = false
        customPanelWidth = 0
        customPanelHeight = 0
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }

    private func saveSpaceNames() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: spaceNames.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            defaults.set(data, forKey: Key.spaceNames.rawValue)
        }
    }

    private static func loadSpaceNames(_ defaults: UserDefaults) -> [Int: String] {
        guard let data = defaults.data(forKey: Key.spaceNames.rawValue),
              let stringKeyed = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        var result: [Int: String] = [:]
        for (k, v) in stringKeyed { if let i = Int(k) { result[i] = v } }
        return result
    }

    private static func loadEnum<T: RawRepresentable>(_ d: UserDefaults, key: Key, fallback: T) -> T where T.RawValue == String {
        guard let raw = d.string(forKey: key.rawValue), let v = T(rawValue: raw) else { return fallback }
        return v
    }

    private static func loadDouble(_ d: UserDefaults, key: Key, fallback: Double, min minV: Double, max maxV: Double) -> Double {
        if d.object(forKey: key.rawValue) == nil { return fallback }
        return Swift.min(Swift.max(d.double(forKey: key.rawValue), minV), maxV)
    }
}
