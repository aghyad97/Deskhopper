# Changelog

All notable changes to Deskhopper are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.1.1] — 2026-03-14

### Fixed

- **Space overlapping on switch** — `NSWorkspace.activeSpaceDidChangeNotification` fires ~50ms after `CGSManagedDisplaySetCurrentSpace` is called, before the switch commits. `handleSpaceChanged()` was reading the stale CGS state and reverting `activeSpaceID` back to the old space. This caused the UI to flip back, then `activateFrontmostApp()` would target an app on the old space and trigger a reverse animation — producing the visual overlap. Fixed by tracking `switchTargetSpaceID` and skipping notifications where CGS returns a non-target space during the switching cooldown.
- **`activateFrontmostApp()` targeting wrong space** — added a guard that verifies `CGSGetActiveSpace() == targetSpaceID` before calling activation. If the switch hasn't committed by the 300ms mark, activation is skipped entirely rather than triggering a reverse switch.
- **Active space wrong on first launch** — `CGSGetActiveSpace` can return a stale space ID immediately after process start, before macOS fully maps the new process to the display's current space (most visibly: always reporting Desktop 1). Fixed by setting `activeSpaceID` synchronously in `SpaceManager.init()` and scheduling a deferred `refreshSpaces()` at 150ms after `startMonitoring()` to re-sample once the OS has settled.

---

## [0.1.0] — 2026-03-13

### Added

- Floating panel visible on all spaces simultaneously via `NSPanel` with `canJoinAllSpaces`
- One-click switching to any desktop using `CGSManagedDisplaySetCurrentSpace`
- Global hotkeys (Ctrl+Option+1–9, configurable modifier key) via `CGEventTap`
- Horizontal and vertical layout modes
- Desktop preview thumbnails via `CGWindowListCreateImage` (optional, three sizes: small / medium / large)
- Configurable idle and hover opacity with smooth animated transitions
- Always-visible and auto-hide modes (panel slides in from screen edge on hover)
- Custom space names per desktop, persisted in `UserDefaults`
- Right-click context menu for quick access to common settings
- Menu bar icon with full settings panel (Position, Appearance, Opacity, Previews, Hotkeys, Behavior, About)
- Multi-monitor support — spaces grouped by display with a divider between monitors
- Drag-to-reposition with edge and center snapping; double-click resets to preset position
- Resize handle (bottom-right corner) with size persistence
- Launch at login via `SMAppService`
- Show in Dock toggle
- Fullscreen spaces detected via `CGSSpaceGetType` and visually badged
- Liquid glass material (`NSVisualEffectView` with `.menu` material) — renders with the macOS 26 Tahoe aesthetic
- GitHub Actions workflow for automated DMG releases

### Fixed

- **Menu bar stacking after rapid clicks** — replaced `NSWorkspace.activeSpaceDidChangeNotification`-based `isSwitching` clear with a 350ms `Timer`. The notification fires at ~50ms (before the animation ends), so the notification-based guard cleared too early. The timer enforces a hard cooldown covering the full ~250ms animation window.
- **Menu bar not committing after programmatic switch** — `CGSManagedDisplaySetCurrentSpace` alone leaves focus state ambiguous. Added `activateFrontmostApp()` at 300ms post-switch to find the topmost normal-layer window on the new space and activate its app, forcing macOS to commit the menu bar transition.
- **Mission Control showing incorrect window assignments** — `canJoinAllSpaces` panels can be registered to the wrong space internally after a programmatic switch. Fixed by briefly toggling `collectionBehavior` on every `NSWorkspace.activeSpaceDidChangeNotification`, forcing the window server to re-evaluate the panel's space membership.
- **CGSCopySpaces returning empty on some macOS versions** — switched from individual type masks to mask `7` (all), which is universally supported.
- **Main thread blocking during space switch** — moved thumbnail capture and space enumeration off the call path of `switchToSpace()`.
