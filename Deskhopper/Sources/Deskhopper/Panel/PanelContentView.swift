import SwiftUI

// MARK: - PanelContentView

struct PanelContentView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var thumbnailCache: ThumbnailCache

    var body: some View {
        let groups = groupedSpaces()

        Group {
            if settingsManager.panelOrientation == .horizontal {
                HStack(spacing: 2) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        if index > 0 {
                            MonitorSeparator(orientation: .horizontal)
                        }
                        ForEach(group) { space in
                            spaceItem(for: space)
                        }
                    }
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        if index > 0 {
                            MonitorSeparator(orientation: .vertical)
                        }
                        ForEach(group) { space in
                            spaceItem(for: space)
                        }
                    }
                }
            }
        }
        .padding(4)
        .overlay(alignment: .bottomTrailing) {
            ResizeGrip()
        }
    }

    // MARK: - Grouping

    /// Groups spaces by displayID, preserving display order from displayGroups.
    private func groupedSpaces() -> [[Space]] {
        return spaceManager.displayGroups.map { $0.spaces }
    }

    // MARK: - Item Selection

    @ViewBuilder
    private func spaceItem(for space: Space) -> some View {
        if settingsManager.showPreviews {
            PreviewSpaceItem(
                space: space,
                isActive: space.id == spaceManager.activeSpaceID,
                label: settingsManager.displayName(forSpaceIndex: space.index),
                thumbnail: thumbnailCache.thumbnail(for: space.id),
                previewSize: settingsManager.previewSize.size,
                onTap: { spaceManager.switchToSpace(id: space.id) }
            )
        } else {
            CompactSpaceItem(
                space: space,
                isActive: space.id == spaceManager.activeSpaceID,
                label: settingsManager.displayName(forSpaceIndex: space.index),
                compactMode: settingsManager.compactMode,
                onTap: { spaceManager.switchToSpace(id: space.id) }
            )
        }
    }
}

// MARK: - CompactSpaceItem

private struct CompactSpaceItem: View {
    let space: Space
    let isActive: Bool
    let label: String
    let compactMode: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isFlashing = false

    var body: some View {
        let minWidth: CGFloat = compactMode ? 24 : 32

        Text(label)
            .font(compactMode ? .system(size: 10, weight: .medium) : .system(size: 11, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(isActive ? .white : .secondary)
            .padding(.horizontal, compactMode ? 4 : 6)
            .padding(.vertical, compactMode ? 2 : 4)
            .frame(minWidth: minWidth)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
            )
            .scaleEffect(isFlashing ? 1.1 : 1.0)
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                onTap()
            }
            .onChange(of: isActive) { newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isFlashing = true
                    }
                    withAnimation(.easeInOut(duration: 0.15).delay(0.15)) {
                        isFlashing = false
                    }
                }
            }
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.6)
        } else if isHovered {
            return Color.white.opacity(0.1)
        } else {
            return Color.clear
        }
    }
}

// MARK: - PreviewSpaceItem

private struct PreviewSpaceItem: View {
    let space: Space
    let isActive: Bool
    let label: String
    let thumbnail: NSImage
    let previewSize: CGSize
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isFlashing = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: previewSize.width, height: previewSize.height)
                    .clipped()
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                isActive ? Color.accentColor : Color.clear,
                                lineWidth: isActive ? 2 : 0
                            )
                    )

                // Fullscreen badge
                if space.isFullscreen {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                        .padding(2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(2)
                        .padding(2)
                }
            }

            Text(label)
                .font(.system(size: 9))
                .foregroundColor(isActive ? .white : .secondary)
                .lineLimit(1)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(previewBackground)
        )
        .scaleEffect(isFlashing ? 1.05 : 1.0)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap()
        }
        .onChange(of: isActive) { newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFlashing = true
                }
                withAnimation(.easeInOut(duration: 0.15).delay(0.15)) {
                    isFlashing = false
                }
            }
        }
    }

    private var previewBackground: Color {
        if isHovered {
            return Color.white.opacity(0.08)
        } else {
            return Color.clear
        }
    }
}

// MARK: - ResizeGrip

private struct ResizeGrip: View {
    var body: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 7, weight: .light))
            .foregroundColor(.secondary.opacity(0.35))
            .frame(width: 14, height: 14)
            .allowsHitTesting(false)
    }
}

// MARK: - MonitorSeparator

private struct MonitorSeparator: View {
    let orientation: PanelOrientation

    var body: some View {
        if orientation == .horizontal {
            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)
        } else {
            Divider()
                .frame(width: 16)
                .padding(.vertical, 2)
        }
    }
}
