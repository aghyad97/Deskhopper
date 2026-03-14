import Cocoa
import Combine

final class ThumbnailCache: ObservableObject {
    @Published private(set) var thumbnails: [CGSSpaceID: NSImage] = [:]

    private let settingsManager: SettingsManager
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var lastKnownSpaceCount = 0

    var panelWindowNumber: CGWindowID = 0

    private let placeholderImage: NSImage

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        let ratio = NSScreen.main.map { $0.frame.width / $0.frame.height } ?? 1.6
        self.placeholderImage = Self.generatePlaceholder(aspectRatio: ratio)
        setupObservers()
    }

    deinit { stopPeriodicRefresh() }

    // MARK: - Access

    func thumbnail(for spaceID: CGSSpaceID) -> NSImage { thumbnails[spaceID] ?? placeholderImage }

    // MARK: - Capture

    func captureCurrentScreen() -> NSImage? {
        let rect = CGDisplayBounds(CGMainDisplayID())
        let windowID = panelWindowNumber > 0 ? panelWindowNumber : kCGNullWindowID
        let listOption: CGWindowListOption = panelWindowNumber > 0 ? [.optionOnScreenOnly, .optionOnScreenBelowWindow] : .optionOnScreenOnly
        guard let cg = CGWindowListCreateImage(rect, listOption, windowID, [.nominalResolution]) else { return nil }
        let targetW: CGFloat = 256
        let scale = targetW / CGFloat(cg.width)
        let size = NSSize(width: targetW, height: CGFloat(cg.height) * scale)
        let img = NSImage(size: size)
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            .draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        img.unlockFocus()
        return img
    }

    func captureCurrentSpace(spaceID: CGSSpaceID) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self, let img = self.captureCurrentScreen() else { return }
            DispatchQueue.main.async { self.thumbnails[spaceID] = img }
        }
    }

    /// Call BEFORE an app-initiated switch
    func captureBeforeSwitch(currentSpaceID: CGSSpaceID) { captureCurrentSpace(spaceID: currentSpaceID) }

    /// Call after an external switch (swipe, Mission Control)
    func captureAfterExternalSwitch(newSpaceID: CGSSpaceID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.captureCurrentSpace(spaceID: newSpaceID)
        }
    }

    // MARK: - Cache Management

    func invalidateAll() { thumbnails.removeAll() }

    @discardableResult
    func updateSpaceCount(_ count: Int) -> Bool {
        if count != lastKnownSpaceCount { lastKnownSpaceCount = count; invalidateAll(); return true }
        return false
    }

    // MARK: - Periodic Refresh

    func startPeriodicRefresh(activeSpaceIDProvider: @escaping () -> CGSSpaceID?) {
        stopPeriodicRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.settingsManager.showPreviews, let id = activeSpaceIDProvider() else { return }
            self.captureCurrentSpace(spaceID: id)
        }
        if let t = refreshTimer { RunLoop.current.add(t, forMode: .common) }
    }

    func stopPeriodicRefresh() { refreshTimer?.invalidate(); refreshTimer = nil }

    // MARK: - Observers

    private func setupObservers() {
        settingsManager.$showPreviews.removeDuplicates()
            .sink { [weak self] enabled in if !enabled { self?.stopPeriodicRefresh() } }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.invalidateAll() }
            .store(in: &cancellables)
    }

    // MARK: - Placeholder

    private static func generatePlaceholder(aspectRatio: CGFloat) -> NSImage {
        let w: CGFloat = 128, h = w / aspectRatio
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSColor(white: 0.15, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h), xRadius: 4, yRadius: 4).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .ultraLight),
            .foregroundColor: NSColor(white: 0.5, alpha: 1)
        ]
        let text = "?" as NSString
        let sz = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (w - sz.width) / 2, y: (h - sz.height) / 2), withAttributes: attrs)
        img.unlockFocus()
        return img
    }
}
