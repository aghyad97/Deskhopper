import AppKit
import Combine
import SwiftUI

// MARK: - EdgeTrackingView

/// Invisible view placed at the screen edge to detect mouse entry for auto-hide mode.
private final class EdgeTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }
}

// MARK: - FloatingPanelController

final class FloatingPanelController: NSPanel {
    private let spaceManager: SpaceManager
    private let settingsManager: SettingsManager
    private let thumbnailCache: ThumbnailCache

    private var cancellables = Set<AnyCancellable>()
    private var trackingArea: NSTrackingArea?

    private let visualEffectView = NSVisualEffectView()
    private var hostingView: NSHostingView<PanelContentView>!

    // Auto-hide
    private var edgeTrackingWindow: NSWindow?
    private var isHiddenByAutoHide = false

    // Drag
    private var isDragging = false
    private var dragStartMouseLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero

    // Resize
    private var isResizing = false
    private var resizeStartMouseLocation: NSPoint = .zero
    private var resizeStartSize: NSSize = .zero
    private let resizeHandleSize: CGFloat = 16

    private let edgeSnapDistance: CGFloat = 10
    private let screenMargin: CGFloat = 8

    // MARK: - Init

    init(spaceManager: SpaceManager, settingsManager: SettingsManager, thumbnailCache: ThumbnailCache) {
        self.spaceManager = spaceManager
        self.settingsManager = settingsManager
        self.thumbnailCache = thumbnailCache

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        configureWindow()
        setupVisualEffectView()
        setupHostingView()
        setupTrackingArea()
        bindSettings()
        observeScreenChanges()
    }

    // MARK: - Window Configuration

    private func configureWindow() {
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isExcludedFromWindowsMenu = true
        alphaValue = CGFloat(settingsManager.idleOpacity)
        titlebarSeparatorStyle = .none
    }

    // MARK: - Visual Effect Background

    private func setupVisualEffectView() {
        // .menu gives a light translucent glass that adapts to background content.
        // On macOS 26 Tahoe this renders with the liquid glass aesthetic.
        visualEffectView.material = .menu
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 8
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        contentView = NSView(frame: .zero)
        contentView!.wantsLayer = true
        contentView!.addSubview(visualEffectView)

        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: contentView!.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
        ])
    }

    // MARK: - Hosting View

    private func setupHostingView() {
        let panelContentView = PanelContentView(
            spaceManager: spaceManager,
            settingsManager: settingsManager,
            thumbnailCache: thumbnailCache
        )
        hostingView = NSHostingView(rootView: panelContentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        contentView!.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentView!.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
        ])
    }

    // MARK: - Tracking Area (Hover)

    private func setupTrackingArea() {
        // Will be created/updated in updateTrackingAreas
    }

    private func installTrackingArea() {
        guard let cv = contentView else { return }
        if let existing = trackingArea { cv.removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: cv.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        cv.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        animateOpacity(to: CGFloat(settingsManager.hoverOpacity))
    }

    override func mouseExited(with event: NSEvent) {
        if settingsManager.panelMode == .autoHide {
            hidePanel()
        } else {
            animateOpacity(to: CGFloat(settingsManager.idleOpacity))
        }
    }

    private func animateOpacity(to target: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = settingsManager.opacityTransitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().alphaValue = target
        }
    }

    // MARK: - Auto-Hide

    private func setupAutoHide() {
        tearDownAutoHide()
        guard settingsManager.panelMode == .autoHide else { return }

        let edgeRect = calculateEdgeTrackingRect()
        let edgeWindow = NSWindow(
            contentRect: edgeRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        edgeWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        edgeWindow.level = .floating
        edgeWindow.isOpaque = false
        edgeWindow.backgroundColor = .clear
        edgeWindow.hasShadow = false
        edgeWindow.hidesOnDeactivate = false
        edgeWindow.ignoresMouseEvents = false

        let trackView = EdgeTrackingView(frame: edgeWindow.contentView!.bounds)
        trackView.autoresizingMask = [.width, .height]
        trackView.onMouseEntered = { [weak self] in
            self?.revealPanel()
        }
        edgeWindow.contentView!.addSubview(trackView)
        edgeWindow.orderFront(nil)
        edgeTrackingWindow = edgeWindow
    }

    private func tearDownAutoHide() {
        edgeTrackingWindow?.orderOut(nil)
        edgeTrackingWindow = nil
    }

    private func calculateEdgeTrackingRect() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let vf = screen.visibleFrame
        let position = settingsManager.panelPosition
        let thickness: CGFloat = 2

        switch position {
        case .topLeft, .topCenter, .topRight:
            return NSRect(x: vf.minX, y: vf.maxY - thickness, width: vf.width, height: thickness)
        case .bottomLeft, .bottomCenter, .bottomRight:
            return NSRect(x: vf.minX, y: vf.minY, width: vf.width, height: thickness)
        case .leftTop, .leftCenter, .leftBottom:
            return NSRect(x: vf.minX, y: vf.minY, width: thickness, height: vf.height)
        case .rightTop, .rightCenter, .rightBottom:
            return NSRect(x: vf.maxX - thickness, y: vf.minY, width: thickness, height: vf.height)
        }
    }

    private func hidePanel() {
        isHiddenByAutoHide = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.edgeTrackingWindow?.orderFront(nil)
        })
    }

    private func revealPanel() {
        isHiddenByAutoHide = false
        alphaValue = 0
        orderFront(nil)
        edgeTrackingWindow?.orderOut(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = CGFloat(self.settingsManager.hoverOpacity)
        }
        installTrackingArea()
    }

    // MARK: - Positioning

    func showPanel() {
        updatePanelSize()
        updatePosition()
        alphaValue = CGFloat(settingsManager.idleOpacity)
        installTrackingArea()

        if settingsManager.panelMode == .autoHide {
            setupAutoHide()
            hidePanel()
        } else {
            orderFront(nil)
        }
    }

    private func updatePosition() {
        if settingsManager.hasDraggedPosition {
            let customOrigin = NSPoint(
                x: settingsManager.draggedPositionX,
                y: settingsManager.draggedPositionY
            )
            if isPositionOnScreen(customOrigin) {
                setFrameOrigin(customOrigin)
                return
            }
            // Custom position is off-screen — fall back to enum position
            settingsManager.clearDraggedPosition()
        }
        let origin = calculateOrigin()
        setFrameOrigin(origin)
    }

    private func isPositionOnScreen(_ origin: NSPoint) -> Bool {
        let panelFrame = NSRect(origin: origin, size: frame.size)
        for screen in NSScreen.screens {
            let intersection = panelFrame.intersection(screen.visibleFrame)
            if !intersection.isNull {
                let visibleArea = intersection.width * intersection.height
                let totalArea = panelFrame.width * panelFrame.height
                if visibleArea >= totalArea * 0.5 {
                    return true
                }
            }
        }
        return false
    }

    private func calculateOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let vf = screen.visibleFrame
        let ps = frame.size
        let m = screenMargin

        switch settingsManager.panelPosition {
        case .topLeft:
            return NSPoint(x: vf.minX + m, y: vf.maxY - ps.height - m)
        case .topCenter:
            return NSPoint(x: vf.midX - ps.width / 2, y: vf.maxY - ps.height - m)
        case .topRight:
            return NSPoint(x: vf.maxX - ps.width - m, y: vf.maxY - ps.height - m)
        case .bottomLeft:
            return NSPoint(x: vf.minX + m, y: vf.minY + m)
        case .bottomCenter:
            return NSPoint(x: vf.midX - ps.width / 2, y: vf.minY + m)
        case .bottomRight:
            return NSPoint(x: vf.maxX - ps.width - m, y: vf.minY + m)
        case .leftTop:
            return NSPoint(x: vf.minX + m, y: vf.maxY - ps.height - m)
        case .leftCenter:
            return NSPoint(x: vf.minX + m, y: vf.midY - ps.height / 2)
        case .leftBottom:
            return NSPoint(x: vf.minX + m, y: vf.minY + m)
        case .rightTop:
            return NSPoint(x: vf.maxX - ps.width - m, y: vf.maxY - ps.height - m)
        case .rightCenter:
            return NSPoint(x: vf.maxX - ps.width - m, y: vf.midY - ps.height / 2)
        case .rightBottom:
            return NSPoint(x: vf.maxX - ps.width - m, y: vf.minY + m)
        }
    }

    private func updatePanelSize() {
        if settingsManager.hasCustomPanelSize {
            let customSize = NSSize(
                width: max(settingsManager.customPanelWidth, 80),
                height: max(settingsManager.customPanelHeight, 24)
            )
            setContentSize(customSize)
            return
        }
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let newSize = NSSize(
            width: max(fittingSize.width, 40),
            height: max(fittingSize.height, 20)
        )
        setContentSize(newSize)
    }

    // MARK: - Drag to Reposition

    override func mouseDown(with event: NSEvent) {
        guard let cv = contentView else { return }
        let localPoint = cv.convert(event.locationInWindow, from: nil)
        let resizeRect = NSRect(
            x: cv.bounds.maxX - resizeHandleSize,
            y: 0,
            width: resizeHandleSize,
            height: resizeHandleSize
        )

        if resizeRect.contains(localPoint) {
            isResizing = true
            resizeStartMouseLocation = NSEvent.mouseLocation
            resizeStartSize = frame.size
            return
        }

        if event.clickCount == 2 {
            // Double-click resets to enum position
            settingsManager.clearDraggedPosition()
            updatePosition()
            return
        }
        isDragging = true
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        if isResizing {
            let currentMouse = NSEvent.mouseLocation
            let dx = currentMouse.x - resizeStartMouseLocation.x
            let dy = resizeStartMouseLocation.y - currentMouse.y  // Y is flipped in screen coords
            let newWidth = max(resizeStartSize.width + dx, 80)
            let newHeight = max(resizeStartSize.height + dy, 24)
            setContentSize(NSSize(width: newWidth, height: newHeight))
            return
        }
        guard isDragging else { return }
        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - dragStartMouseLocation.x
        let dy = currentMouse.y - dragStartMouseLocation.y
        var newOrigin = NSPoint(
            x: dragStartWindowOrigin.x + dx,
            y: dragStartWindowOrigin.y + dy
        )
        newOrigin = snapToEdges(newOrigin)
        setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        if isResizing {
            isResizing = false
            settingsManager.setCustomPanelSize(
                width: Double(frame.width),
                height: Double(frame.height)
            )
            return
        }
        guard isDragging else { return }
        isDragging = false
        settingsManager.setDraggedPosition(x: Double(frame.origin.x), y: Double(frame.origin.y))
    }

    private func snapToEdges(_ origin: NSPoint) -> NSPoint {
        guard let screen = NSScreen.main else { return origin }
        let vf = screen.visibleFrame
        let ps = frame.size
        var x = origin.x
        var y = origin.y

        // Snap to left edge
        if abs(x - (vf.minX + screenMargin)) < edgeSnapDistance {
            x = vf.minX + screenMargin
        }
        // Snap to right edge
        if abs((x + ps.width) - (vf.maxX - screenMargin)) < edgeSnapDistance {
            x = vf.maxX - ps.width - screenMargin
        }
        // Snap to bottom edge
        if abs(y - (vf.minY + screenMargin)) < edgeSnapDistance {
            y = vf.minY + screenMargin
        }
        // Snap to top edge
        if abs((y + ps.height) - (vf.maxY - screenMargin)) < edgeSnapDistance {
            y = vf.maxY - ps.height - screenMargin
        }
        // Snap to horizontal center
        let centerX = vf.midX - ps.width / 2
        if abs(x - centerX) < edgeSnapDistance {
            x = centerX
        }
        // Snap to vertical center
        let centerY = vf.midY - ps.height / 2
        if abs(y - centerY) < edgeSnapDistance {
            y = centerY
        }

        return NSPoint(x: x, y: y)
    }

    // MARK: - Context Menu

    override func rightMouseDown(with event: NSEvent) {
        let menu = buildContextMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: contentView!)
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Panel Options")

        // Toggle Previews
        let previewItem = NSMenuItem(
            title: settingsManager.showPreviews ? "Hide Previews" : "Show Previews",
            action: #selector(togglePreviews),
            keyEquivalent: ""
        )
        previewItem.target = self
        menu.addItem(previewItem)

        // Toggle Orientation
        let orientItem = NSMenuItem(
            title: settingsManager.panelOrientation == .horizontal ? "Vertical Layout" : "Horizontal Layout",
            action: #selector(toggleOrientation),
            keyEquivalent: ""
        )
        orientItem.target = self
        menu.addItem(orientItem)

        // Opacity Submenu
        let opacitySubmenu = NSMenu(title: "Idle Opacity")
        let opacityValues: [(String, Double)] = [
            ("5%", 0.05), ("10%", 0.10), ("20%", 0.20), ("30%", 0.30),
            ("50%", 0.50), ("75%", 0.75), ("100%", 1.0),
        ]
        for (title, value) in opacityValues {
            let item = NSMenuItem(title: title, action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(value * 100)
            if abs(settingsManager.idleOpacity - value) < 0.01 {
                item.state = .on
            }
            opacitySubmenu.addItem(item)
        }
        let opacityItem = NSMenuItem(title: "Idle Opacity", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacitySubmenu
        menu.addItem(opacityItem)

        menu.addItem(.separator())

        // Toggle Mode
        let modeItem = NSMenuItem(
            title: settingsManager.panelMode == .alwaysVisible ? "Switch to Auto-Hide" : "Switch to Always Visible",
            action: #selector(toggleMode),
            keyEquivalent: ""
        )
        modeItem.target = self
        menu.addItem(modeItem)

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        return menu
    }

    @objc private func togglePreviews() {
        settingsManager.showPreviews.toggle()
    }

    @objc private func toggleOrientation() {
        settingsManager.panelOrientation = settingsManager.panelOrientation == .horizontal ? .vertical : .horizontal
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        settingsManager.idleOpacity = Double(sender.tag) / 100.0
    }

    @objc private func toggleMode() {
        settingsManager.panelMode = settingsManager.panelMode == .alwaysVisible ? .autoHide : .alwaysVisible
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
    }

    // MARK: - Settings Bindings

    private func bindSettings() {
        // Panel position changes
        settingsManager.$panelPosition
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.settingsManager.clearDraggedPosition()
                self?.updatePanelSize()
                self?.updatePosition()
                self?.setupAutoHide()
            }
            .store(in: &cancellables)

        // Orientation changes — clear custom size so panel auto-fits new layout
        settingsManager.$panelOrientation
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.settingsManager.clearCustomPanelSize()
                self?.updatePanelSize()
                self?.updatePosition()
            }
            .store(in: &cancellables)

        // Mode changes
        settingsManager.$panelMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                guard let self else { return }
                if mode == .autoHide {
                    self.setupAutoHide()
                    self.hidePanel()
                } else {
                    self.tearDownAutoHide()
                    self.isHiddenByAutoHide = false
                    self.alphaValue = CGFloat(self.settingsManager.idleOpacity)
                    self.orderFront(nil)
                    self.installTrackingArea()
                }
            }
            .store(in: &cancellables)

        // Show previews changes — clear custom size since mode changes affect panel shape
        settingsManager.$showPreviews
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.settingsManager.clearCustomPanelSize()
                self?.updatePanelSize()
                self?.updatePosition()
            }
            .store(in: &cancellables)

        // Preview size changes — clear custom size
        settingsManager.$previewSize
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.settingsManager.clearCustomPanelSize()
                self?.updatePanelSize()
                self?.updatePosition()
            }
            .store(in: &cancellables)

        // Compact mode changes — clear custom size
        settingsManager.$compactMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.settingsManager.clearCustomPanelSize()
                self?.updatePanelSize()
                self?.updatePosition()
            }
            .store(in: &cancellables)

        // Space name changes — resize panel to fit updated labels
        settingsManager.$spaceNames
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.settingsManager.hasCustomPanelSize else { return }
                self.updatePanelSize()
                self.updatePosition()
            }
            .store(in: &cancellables)

        // Idle opacity changes
        settingsManager.$idleOpacity
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] opacity in
                guard let self, !self.isHiddenByAutoHide else { return }
                // Only update if mouse is not hovering (approximation: if alphaValue is close to idle)
                let currentAlpha = Double(self.alphaValue)
                if abs(currentAlpha - self.settingsManager.hoverOpacity) > 0.05 {
                    self.alphaValue = CGFloat(opacity)
                }
            }
            .store(in: &cancellables)

        // Space list changes (resize panel)
        spaceManager.$spaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePanelSize()
                self?.updatePosition()
            }
            .store(in: &cancellables)
    }

    // MARK: - Screen Changes

    private func observeScreenChanges() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updatePanelSize()
                self.updatePosition()
                if self.settingsManager.panelMode == .autoHide {
                    self.setupAutoHide()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Key handling (prevent beeps)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
