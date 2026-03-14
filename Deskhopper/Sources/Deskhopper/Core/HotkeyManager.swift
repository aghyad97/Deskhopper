import Cocoa
import Combine

final class HotkeyManager {
    private let spaceManager: SpaceManager
    private let settingsManager: SettingsManager
    private var cancellables = Set<AnyCancellable>()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var accessibilityGranted = false

    private static let numberKeyCodes: [CGKeyCode: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
    ]

    init(spaceManager: SpaceManager, settingsManager: SettingsManager) {
        self.spaceManager = spaceManager
        self.settingsManager = settingsManager
        setupObservers()
    }

    deinit { tearDownEventTap() }

    // MARK: - Accessibility

    @discardableResult
    func checkAccessibility(prompt: Bool = false) -> Bool {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt]
        accessibilityGranted = AXIsProcessTrustedWithOptions(opts)
        return accessibilityGranted
    }

    func recheckAccessibility() {
        let was = accessibilityGranted
        let now = checkAccessibility(prompt: false)
        if now && !was && settingsManager.globalHotkeysEnabled { startEventTap() }
        else if !now && was { tearDownEventTap() }
    }

    // MARK: - Event Tap

    func startEventTap() {
        guard accessibilityGranted, eventTap == nil else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                return Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                    .handleEvent(type: type, event: event)
            }, userInfo: selfPtr
        ) else { accessibilityGranted = false; return }

        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func tearDownEventTap() {
        if let s = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), s, .commonModes); runLoopSource = nil }
        if let t = eventTap { CGEvent.tapEnable(tap: t, enable: false); eventTap = nil }
    }

    func startListening() {
        if checkAccessibility(prompt: true) && settingsManager.globalHotkeysEnabled { startEventTap() }
    }

    func stopListening() { tearDownEventTap() }

    // MARK: - Event Handling

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            if let t = eventTap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, settingsManager.globalHotkeysEnabled else {
            return Unmanaged.passUnretained(event)
        }
        // Skip synthetic events posted by SpaceManager — let them reach the Dock
        if event.getIntegerValueField(.eventSourceUserData) == SpaceManager.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let mod = settingsManager.hotkeyModifier
        guard flags.contains(mod.cgEventFlags) else { return Unmanaged.passUnretained(event) }
        for ex in mod.exclusionFlags {
            if flags.contains(ex) { return Unmanaged.passUnretained(event) }
        }
        guard let idx = Self.numberKeyCodes[keyCode] else { return Unmanaged.passUnretained(event) }
        DispatchQueue.main.async { [weak self] in self?.spaceManager.switchToSpace(byIndex: idx) }
        return nil // consume event
    }

    // MARK: - Observers

    private func setupObservers() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.recheckAccessibility() }
            .store(in: &cancellables)

        settingsManager.$globalHotkeysEnabled.removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled && self.accessibilityGranted { self.startEventTap() }
                else if !enabled { self.tearDownEventTap() }
            }.store(in: &cancellables)
    }
}
