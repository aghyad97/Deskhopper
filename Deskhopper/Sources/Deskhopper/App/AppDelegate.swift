import AppKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    private var spaceManager: SpaceManager?
    private var settingsManager: SettingsManager!
    private var thumbnailCache: ThumbnailCache?
    private var hotkeyManager: HotkeyManager?
    private var floatingPanel: FloatingPanelController?
    private var menuBarController: MenuBarController?

    private var didSwitchObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Set activation policy based on showInDock
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)

        // 2. Settings manager (singleton)
        let settings = SettingsManager.shared
        self.settingsManager = settings

        // 3. Space manager — if private API unavailable, SpaceManager shows alert & throws
        let sm: SpaceManager
        do {
            sm = try SpaceManager()
        } catch {
            return
        }
        self.spaceManager = sm

        // 3b. One-time setup: configure Mission Control shortcuts and restart Dock.
        // After the Dock reads the new shortcut configs, synthetic Ctrl+N events go through
        // the Dock's normal space-switching code path — no compositor corruption.
        if sm.isShortcutSetupComplete {
            // Already set up in a previous run — just activate for this session
            sm.enableSyntheticSwitching()
        } else {
            let wroteNewConfigs = sm.writeShortcutConfigs()
            if wroteNewConfigs {
                sm.promptAndRestartDock()
            } else {
                // Configs already existed (user enabled them manually) — just activate
                sm.enableSyntheticSwitching()
                sm.markShortcutSetupComplete()
            }
        }

        // 4. Thumbnail cache
        let cache = ThumbnailCache(settingsManager: settings)
        self.thumbnailCache = cache

        // 5. Hotkey manager
        let hotkeys = HotkeyManager(spaceManager: sm, settingsManager: settings)
        hotkeys.startListening()
        self.hotkeyManager = hotkeys

        // 6. Wire thumbnail capture and post-switch fixups to space-switch notifications
        didSwitchObserver = NotificationCenter.default.addObserver(
            forName: .spaceDidSwitch, object: nil, queue: .main
        ) { [weak cache, weak self] note in
            guard let cache,
                  let toID = note.userInfo?["toSpaceID"] as? CGSSpaceID else { return }
            let isProgrammatic = note.userInfo?["isProgrammatic"] as? Bool ?? false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                cache.captureCurrentSpace(spaceID: toID)
                // Only activate frontmost app for CGS fallback switches (synthetic handles this)
                if isProgrammatic, self?.spaceManager?.useSyntheticSwitching == false {
                    guard self?.spaceManager?.getActiveSpaceID() == toID else { return }
                    self?.activateFrontmostApp()
                }
            }
        }

        // 7. Floating panel
        let panel = FloatingPanelController(
            spaceManager: sm, settingsManager: settings, thumbnailCache: cache
        )
        panel.showPanel()
        self.floatingPanel = panel
        cache.panelWindowNumber = CGWindowID(panel.windowNumber)

        // 8. Menu bar controller
        self.menuBarController = MenuBarController(settingsManager: settings, spaceManager: sm)

        // 9. Start space monitoring
        sm.startMonitoring()

        // 9b. Deferred re-verification for stale CGSGetActiveSpace on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            sm.refreshSpaces()
        }

        // 10. Observe NSWorkspace space changes to reset panel's space binding.
        // Only needed for CGS fallback — synthetic switching handles this via the Dock.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared, queue: .main
        ) { [weak self] _ in
            guard let self,
                  let sm = self.spaceManager,
                  !sm.useSyntheticSwitching,
                  !sm.isProgrammaticSwitchInProgress,
                  let panel = self.floatingPanel else { return }
            let current = panel.collectionBehavior
            panel.collectionBehavior = [.fullScreenAuxiliary]
            panel.collectionBehavior = current
        }

        // 11. Start periodic thumbnail refresh
        cache.startPeriodicRefresh { [weak sm] in
            sm?.getActiveSpaceID()
        }
    }

    /// Activates the frontmost app on the current space via Accessibility API.
    /// Only used in CGS fallback mode — synthetic switching handles this via the Dock.
    private func activateFrontmostApp() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  pid != myPID,
                  NSRunningApplication(processIdentifier: pid) != nil else { continue }

            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            return
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stopListening()
        spaceManager?.stopMonitoring()
        thumbnailCache?.stopPeriodicRefresh()

        if let obs = didSwitchObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
