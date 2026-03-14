import AppKit
import SwiftUI

extension Notification.Name {
    static let openSettingsWindow = Notification.Name("openSettingsWindow")
}

final class MenuBarController {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?

    private let settingsManager: SettingsManager
    private let spaceManager: SpaceManager

    init(settingsManager: SettingsManager, spaceManager: SpaceManager) {
        self.settingsManager = settingsManager
        self.spaceManager = spaceManager
        setupStatusItem()
        setupPopover()
        setupEventMonitor()

        NotificationCenter.default.addObserver(
            forName: .openSettingsWindow, object: nil, queue: .main
        ) { [weak self] _ in
            self?.openPopover()
        }
    }

    deinit {
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let btn = statusItem.button else { return }

        // Try custom menu bar icon first, fall back to SF Symbol
        if let img = loadMenuBarIcon() {
            img.isTemplate = false
            img.size = NSSize(width: 18, height: 18)
            btn.image = img
        } else if let img = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Deskhopper") {
            img.isTemplate = true
            btn.image = img
        }
        btn.action = #selector(togglePopover(_:))
        btn.target = self
    }

    private func loadMenuBarIcon() -> NSImage? {
        // Look for MenuBarIcon in the bundle resources
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        // Fallback: look next to the executable (for debug builds)
        let execDir = Bundle.main.bundlePath
        let resourcePaths = [
            "\(execDir)/Contents/Resources/MenuBarIcon.png",
            "\(execDir)/../Sources/Deskhopper/Resources/MenuBarIcon.png",
        ]
        for path in resourcePaths {
            if let img = NSImage(contentsOfFile: path) { return img }
        }
        return nil
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: SettingsView(settingsManager: settingsManager, spaceManager: spaceManager)
        )
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let p = self?.popover, p.isShown {
                p.performClose(nil)
            }
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func openPopover() {
        guard let btn = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
