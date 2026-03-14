import AppKit
import Combine

// MARK: - CGS Types

typealias CGSConnectionID = Int32
typealias CGSSpaceID = UInt64

// MARK: - CGS/SLS Function Signatures

private typealias CGSMainConnectionID_t = @convention(c) () -> CGSConnectionID
private typealias CGSGetActiveSpace_t = @convention(c) (CGSConnectionID) -> CGSSpaceID
private typealias CGSManagedDisplaySetCurrentSpace_t = @convention(c) (CGSConnectionID, CFString, CGSSpaceID) -> Void
private typealias CGSCopyManagedDisplayForSpace_t = @convention(c) (CGSConnectionID, CGSSpaceID) -> CFString
private typealias CGSCopyManagedDisplaySpaces_t = @convention(c) (CGSConnectionID) -> CFArray
private typealias SLSSetSymbolicHotKeyEnabled_t = @convention(c) (Int32, Bool) -> Int32

// MARK: - Space Model

struct Space: Identifiable, Equatable {
    let id: CGSSpaceID
    let displayID: CFString
    let isFullscreen: Bool
    let index: Int // 1-based Mission Control position within its display group
    var number: Int { index }

    var defaultLabel: String {
        isFullscreen ? "Fullscreen \(index)" : "Desktop \(index)"
    }

    static func == (lhs: Space, rhs: Space) -> Bool {
        lhs.id == rhs.id && (lhs.displayID as String) == (rhs.displayID as String)
            && lhs.isFullscreen == rhs.isFullscreen && lhs.index == rhs.index
    }
}

struct DisplaySpaceGroup: Identifiable, Equatable {
    let displayID: CFString
    let isPrimary: Bool
    let spaces: [Space]
    var id: String { displayID as String }

    static func == (lhs: DisplaySpaceGroup, rhs: DisplaySpaceGroup) -> Bool {
        (lhs.displayID as String) == (rhs.displayID as String)
            && lhs.isPrimary == rhs.isPrimary && lhs.spaces == rhs.spaces
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let spaceDidSwitch = Notification.Name("com.deskhopper.spaceDidSwitch")
}

// MARK: - Error

enum SpaceManagerError: Error, LocalizedError {
    case privateAPIUnavailable
    var errorDescription: String? { "SkyLight private API functions could not be resolved." }
}

// MARK: - Private API Resolver

private struct PrivateAPIResolver {
    let mainConnectionID: CGSMainConnectionID_t
    let getActiveSpace: CGSGetActiveSpace_t
    let managedDisplaySetCurrentSpace: CGSManagedDisplaySetCurrentSpace_t
    let copyManagedDisplayForSpace: CGSCopyManagedDisplayForSpace_t
    let copyManagedDisplaySpaces: CGSCopyManagedDisplaySpaces_t
    let setSymbolicHotKeyEnabled: SLSSetSymbolicHotKeyEnabled_t?

    static func resolve() -> PrivateAPIResolver? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return nil }
        guard let p1 = dlsym(handle, "CGSMainConnectionID"),
              let p2 = dlsym(handle, "CGSGetActiveSpace"),
              let p3 = dlsym(handle, "CGSManagedDisplaySetCurrentSpace"),
              let p4 = dlsym(handle, "CGSCopyManagedDisplayForSpace"),
              let p5 = dlsym(handle, "CGSCopyManagedDisplaySpaces") else {
            dlclose(handle); return nil
        }
        let pHotkey: SLSSetSymbolicHotKeyEnabled_t? = dlsym(handle, "SLSSetSymbolicHotKeyEnabled")
            .map { unsafeBitCast($0, to: SLSSetSymbolicHotKeyEnabled_t.self) }

        return PrivateAPIResolver(
            mainConnectionID: unsafeBitCast(p1, to: CGSMainConnectionID_t.self),
            getActiveSpace: unsafeBitCast(p2, to: CGSGetActiveSpace_t.self),
            managedDisplaySetCurrentSpace: unsafeBitCast(p3, to: CGSManagedDisplaySetCurrentSpace_t.self),
            copyManagedDisplayForSpace: unsafeBitCast(p4, to: CGSCopyManagedDisplayForSpace_t.self),
            copyManagedDisplaySpaces: unsafeBitCast(p5, to: CGSCopyManagedDisplaySpaces_t.self),
            setSymbolicHotKeyEnabled: pHotkey
        )
    }
}

// MARK: - SpaceManager

final class SpaceManager: ObservableObject {
    @Published private(set) var displayGroups: [DisplaySpaceGroup] = []
    @Published private(set) var spaces: [Space] = []
    @Published private(set) var activeSpaceID: CGSSpaceID = 0

    private let api: PrivateAPIResolver
    private let connectionID: CGSConnectionID
    private var notificationObserver: NSObjectProtocol?
    private var pollingTimer: Timer?
    private var isSwitching = false
    private var switchTargetSpaceID: CGSSpaceID = 0
    private var switchCooldownTimer: Timer?

    /// True while a programmatic switch is in the 350ms cooldown window.
    var isProgrammaticSwitchInProgress: Bool { isSwitching }

    /// Whether switching uses synthetic keyboard events (Dock-native) vs CGS (instant but broken).
    private(set) var useSyntheticSwitching = false

    /// Marker value set on synthetic CGEvents so HotkeyManager can skip them.
    static let syntheticEventMarker: Int64 = 0x44455348

    /// macOS virtual key codes for number keys 1-9.
    private static let numberKeyCodes: [Int: CGKeyCode] = [
        1: 0x12, 2: 0x13, 3: 0x14, 4: 0x15, 5: 0x17,
        6: 0x16, 7: 0x1A, 8: 0x1C, 9: 0x19
    ]

    private static let shortcutsSetupKey = "deskhopper.shortcutsSetupComplete"

    var activeSpace: Space? { spaces.first { $0.id == activeSpaceID } }

    init() throws {
        guard let resolved = PrivateAPIResolver.resolve() else {
            Self.showIncompatibleAlert()
            throw SpaceManagerError.privateAPIUnavailable
        }
        self.api = resolved
        let cid = resolved.mainConnectionID()
        self.connectionID = cid
        self.activeSpaceID = resolved.getActiveSpace(cid)
        refreshSpaces()
    }

    deinit {
        if let obs = notificationObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        pollingTimer?.invalidate()
        switchCooldownTimer?.invalidate()
    }

    // MARK: - Mission Control Shortcut Setup

    /// Writes "Switch to Desktop N" shortcut configs (Ctrl+1 through Ctrl+9) to CFPreferences.
    /// Returns true if new configs were written (meaning a Dock restart is needed).
    @discardableResult
    func writeShortcutConfigs() -> Bool {
        let domain = "com.apple.symbolichotkeys" as CFString
        var hotkeys = (CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]) ?? [:]

        let keyCodes: [Int: Int] = [0: 18, 1: 19, 2: 20, 3: 21, 4: 23, 5: 22, 6: 26, 7: 28, 8: 25]
        var wrote = false

        for i in 0..<9 {
            let key = "\(118 + i)"

            if let entry = hotkeys[key] as? [String: Any],
               let enabled = entry["enabled"] as? NSNumber, enabled.boolValue,
               entry["value"] != nil {
                continue
            }

            let asciiCode = 49 + i
            let keyCode = keyCodes[i] ?? 18
            hotkeys[key] = [
                "enabled": true as NSNumber,
                "value": [
                    "parameters": [asciiCode, keyCode, 262144] as [Int],
                    "type": "standard"
                ] as [String: Any]
            ] as [String: Any]
            wrote = true
        }

        if wrote {
            CFPreferencesSetAppValue("AppleSymbolicHotKeys" as CFString, hotkeys as CFDictionary, domain)
            CFPreferencesAppSynchronize(domain)
            NSLog("[Deskhopper] Wrote Mission Control shortcut configs to CFPreferences")
        }

        return wrote
    }

    /// Activates shortcuts in the current session via SLS API and enables synthetic switching.
    func enableSyntheticSwitching() {
        if let setEnabled = api.setSymbolicHotKeyEnabled {
            for i in 0..<9 {
                let result = setEnabled(Int32(118 + i), true)
                NSLog("[Deskhopper] SLSSetSymbolicHotKeyEnabled(\(118 + i)) = \(result)")
            }
        }
        useSyntheticSwitching = true
        NSLog("[Deskhopper] Synthetic switching enabled — using Dock-native space transitions")
    }

    /// Whether the one-time Dock restart setup has been completed.
    var isShortcutSetupComplete: Bool {
        UserDefaults.standard.bool(forKey: Self.shortcutsSetupKey)
    }

    /// Marks the one-time setup as complete.
    func markShortcutSetupComplete() {
        UserDefaults.standard.set(true, forKey: Self.shortcutsSetupKey)
    }

    /// Shows a one-time alert asking to restart the Dock for proper space switching.
    /// Returns true if the user agreed and the Dock was restarted.
    @discardableResult
    func promptAndRestartDock() -> Bool {
        let alert = NSAlert()
        alert.messageText = "One-Time Setup"
        alert.informativeText = """
            Deskhopper needs to restart the Dock to enable smooth space switching. \
            This is a one-time setup that takes about 2 seconds.

            Without this, trackpad swiping and Mission Control may glitch after switching desktops.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart Dock")
        alert.addButton(withTitle: "Skip (use instant mode)")

        guard alert.runModal() == .alertFirstButtonReturn else {
            NSLog("[Deskhopper] User skipped Dock restart — using CGS switching")
            return false
        }

        NSLog("[Deskhopper] Restarting Dock...")

        // Kill the Dock — macOS automatically relaunches it within ~2 seconds
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["Dock"]
        task.launch()
        task.waitUntilExit()

        // Wait for the Dock to fully restart and read the new shortcut configs
        Thread.sleep(forTimeInterval: 2.5)

        markShortcutSetupComplete()
        enableSyntheticSwitching()
        NSLog("[Deskhopper] Dock restarted — synthetic switching active")
        return true
    }

    // MARK: - Monitoring

    func startMonitoring() {
        notificationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared, queue: .main
        ) { [weak self] _ in self?.handleSpaceChanged() }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollActiveSpace()
        }
        if let t = pollingTimer { RunLoop.main.add(t, forMode: .common) }
    }

    func stopMonitoring() {
        if let obs = notificationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            notificationObserver = nil
        }
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Enumeration

    func refreshSpaces() {
        let (grouped, active) = enumerateSpaces()
        let flat = grouped.flatMap(\.spaces)
        DispatchQueue.main.async { [weak self] in
            self?.displayGroups = grouped
            self?.spaces = flat
            self?.activeSpaceID = active
        }
    }

    func getActiveSpaceID() -> CGSSpaceID { api.getActiveSpace(connectionID) }

    private func enumerateSpaces() -> ([DisplaySpaceGroup], CGSSpaceID) {
        let activeID = api.getActiveSpace(connectionID)

        guard let rawDisplays = api.copyManagedDisplaySpaces(connectionID) as? [[String: Any]],
              !rawDisplays.isEmpty else {
            return ([], activeID)
        }

        var groups: [DisplaySpaceGroup] = []

        for displayDict in rawDisplays {
            guard let displayID = displayDict["Display Identifier"] as? String else { continue }

            let primarySpaces  = displayDict["Spaces"]       as? [[String: Any]] ?? []
            let otherSpaces    = displayDict["Other Spaces"] as? [[String: Any]] ?? []
            let allRawSpaces   = primarySpaces + otherSpaces

            let cfDisplayID = displayID as CFString
            var spaceList: [Space] = []
            var displayContainsActive = false

            for (i, spaceDict) in allRawSpaces.enumerated() {
                guard let id64 = spaceDict["id64"] as? NSNumber else { continue }
                let spaceID = CGSSpaceID(id64.uint64Value)
                let type = (spaceDict["type"] as? Int) ?? 0
                let isFullscreen = (type == 4)

                spaceList.append(Space(id: spaceID, displayID: cfDisplayID, isFullscreen: isFullscreen, index: i + 1))
                if spaceID == activeID { displayContainsActive = true }
            }

            guard !spaceList.isEmpty else { continue }
            groups.append(DisplaySpaceGroup(displayID: cfDisplayID, isPrimary: displayContainsActive, spaces: spaceList))
        }

        groups.sort { a, b in
            if a.isPrimary != b.isPrimary { return a.isPrimary }
            return (a.displayID as String) < (b.displayID as String)
        }

        return (groups, activeID)
    }

    // MARK: - Switching

    func switchToSpace(id target: CGSSpaceID) {
        guard target != activeSpaceID else { return }
        guard !isSwitching else { return }

        isSwitching = true
        switchTargetSpaceID = target
        switchCooldownTimer?.invalidate()
        switchCooldownTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.isSwitching = false
            self?.switchTargetSpaceID = 0
        }

        let previousSpace = activeSpaceID

        if useSyntheticSwitching,
           let idx = spaces.firstIndex(where: { $0.id == target }),
           (idx + 1) <= 9 {
            // Synthetic: Ctrl+N via Dock's normal code path — correct compositor state
            postSpaceKeyEvent(index: idx + 1)
            NSLog("[Deskhopper] switchToSpace: synthetic Ctrl+\(idx + 1)")
        } else {
            // CGS fallback: instant but doesn't update Dock internal state
            let display = api.copyManagedDisplayForSpace(connectionID, target)
            api.managedDisplaySetCurrentSpace(connectionID, display, target)
            activeSpaceID = target
            NSLog("[Deskhopper] switchToSpace: CGS → \(target)")

            NotificationCenter.default.post(name: .spaceDidSwitch, object: self,
                userInfo: ["fromSpaceID": previousSpace, "toSpaceID": target, "isProgrammatic": true])
        }
    }

    func switchToSpace(byIndex index: Int) {
        let i = index - 1
        guard i >= 0, i < spaces.count else { return }
        switchToSpace(id: spaces[i].id)
    }

    private func postSpaceKeyEvent(index: Int) {
        guard let keyCode = Self.numberKeyCodes[index] else { return }

        let source = CGEventSource(stateID: .privateState)
        source?.userData = Self.syntheticEventMarker

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskControl
        keyUp.flags = .maskControl

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Change Detection

    private func handleSpaceChanged() {
        let newActive = api.getActiveSpace(connectionID)
        guard newActive != activeSpaceID else { return }
        if isSwitching && newActive != switchTargetSpaceID { return }
        let prev = activeSpaceID
        activeSpaceID = newActive
        let (grouped, _) = enumerateSpaces()
        displayGroups = grouped
        spaces = grouped.flatMap(\.spaces)
        NotificationCenter.default.post(name: .spaceDidSwitch, object: self,
            userInfo: ["fromSpaceID": prev, "toSpaceID": newActive])
    }

    private func pollActiveSpace() {
        let current = api.getActiveSpace(connectionID)
        if current != activeSpaceID { handleSpaceChanged() }
    }

    // MARK: - Alert

    private static func showIncompatibleAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Deskhopper is not compatible with this macOS version"
            alert.informativeText = "Required private APIs could not be found.\nSupported: macOS 13-16."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
}
