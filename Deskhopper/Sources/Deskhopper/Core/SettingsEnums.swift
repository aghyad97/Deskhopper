import Foundation
import CoreGraphics

enum PanelPosition: String, CaseIterable, Codable, Identifiable, Sendable {
    case topLeft, topCenter, topRight
    case bottomLeft, bottomCenter, bottomRight
    case leftTop, leftCenter, leftBottom
    case rightTop, rightCenter, rightBottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        case .leftTop: return "Left Top"
        case .leftCenter: return "Left Center"
        case .leftBottom: return "Left Bottom"
        case .rightTop: return "Right Top"
        case .rightCenter: return "Right Center"
        case .rightBottom: return "Right Bottom"
        }
    }

    var isVerticalEdge: Bool {
        switch self {
        case .leftTop, .leftCenter, .leftBottom,
             .rightTop, .rightCenter, .rightBottom:
            return true
        default:
            return false
        }
    }
}

enum PanelOrientation: String, CaseIterable, Codable, Identifiable, Sendable {
    case horizontal, vertical
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }
}

enum PanelMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case alwaysVisible, autoHide
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .alwaysVisible: return "Always Visible"
        case .autoHide: return "Auto-Hide"
        }
    }
}

enum PreviewSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case small, medium, large
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    var width: CGFloat {
        switch self {
        case .small: return 64
        case .medium: return 96
        case .large: return 128
        }
    }
    var height: CGFloat {
        switch self {
        case .small: return 40
        case .medium: return 60
        case .large: return 80
        }
    }
    var size: CGSize { CGSize(width: width, height: height) }
}

enum PanelTransitionStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case instant, animated
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .instant: return "Instant"
        case .animated: return "Animated"
        }
    }
}

enum HotkeyModifier: String, CaseIterable, Codable, Identifiable, Sendable {
    case command, control, option, controlOption
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .command: return "⌘ Command"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .controlOption: return "⌃⌥ Control + Option"
        }
    }
    var cgEventFlags: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .controlOption: return [.maskControl, .maskAlternate]
        }
    }
    var exclusionFlags: [CGEventFlags] {
        let all: [CGEventFlags] = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        switch self {
        case .command: return all.filter { $0 != .maskCommand }
        case .control: return all.filter { $0 != .maskControl }
        case .option: return all.filter { $0 != .maskAlternate }
        case .controlOption: return all.filter { $0 != .maskControl && $0 != .maskAlternate }
        }
    }
}
