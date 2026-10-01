import AppKit
import PeelAppCore
import SwiftUI
import UniformTypeIdentifiers

/// The action wheel: a Liquid Glass disc (following the system's glass setting on macOS 26+) with the
/// actions around a small "More" hub. At rest the actions are just icon + label; the one under a dragged
/// file gets an accent-tinted glass highlight.
struct WheelView: View {
    let slots: [WheelSlot]
    let onDrop: (WheelSlot?, [URL]) -> Void   // nil slot = More…
    /// Developer aid for previews: show this slot as hovered (-1 = the hub).
    var previewHovered: Int? = nil

    static let size: CGFloat = 212
    /// Distance from the centre to each chip: as tight as six 58-pt chips around a 58-pt hub allow.
    private static let ring: CGFloat = 66
    @State private var hovered: Int?          // slot index under the drag; -1 = the hub

    private var lit: Int? { hovered ?? previewHovered }
    private func radians(_ index: Int) -> Double {
        (-90 + Double(index) * 360 / Double(max(slots.count, 1))) * .pi / 180
    }

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: Self.size - 8, height: Self.size - 8)
                .peelGlass(Circle())
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                ChipView(title: slot.label, systemImage: slot.systemImage, size: 58, lit: lit == index,
                         onTargeted: { setHovered(index, $0) }) { urls in onDrop(slot, urls) }
                    .offset(x: cos(radians(index)) * Self.ring, y: sin(radians(index)) * Self.ring)
            }
            ChipView(title: "More", systemImage: "ellipsis", size: 58, lit: lit == -1,
                     onTargeted: { setHovered(-1, $0) }) { urls in onDrop(nil, urls) }
                .help("More… — open these files in the peel panel")
        }
        .frame(width: Self.size, height: Self.size)
        .animation(.easeOut(duration: 0.12), value: lit)
    }

    private func setHovered(_ index: Int, _ targeted: Bool) {
        if targeted { hovered = index } else if hovered == index { hovered = nil }
    }
}

/// One action; a drop target. Plain icon + label at rest, accent glass when a file hovers over it.
private struct ChipView: View {
    let title: String?
    let systemImage: String
    let size: CGFloat
    let lit: Bool
    let onTargeted: (Bool) -> Void
    let onDrop: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage).font(.system(size: title == nil ? 13 : 17, weight: .medium))
            if let title {
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(lit ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        .background {
            // Each action sits in its own frosted circle, a step more opaque than the glass disc, so the
            // targets (and the space between them) read clearly; the hovered one fills with the accent.
            Circle().fill(lit ? AnyShapeStyle(Color.accentColor.opacity(0.9)) : AnyShapeStyle(.primary.opacity(0.12)))
                .overlay(Circle().strokeBorder(.primary.opacity(lit ? 0 : 0.2), lineWidth: 0.5))
        }
        .contentShape(Circle())
        .onChange(of: targeted) { onTargeted($0) }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            let group = DispatchGroup()
            let collected = OrderedURLs(count: providers.count)   // keep drag order (matters for Merge)
            for (index, provider) in providers.enumerated() {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    collected.set(index, url)
                    group.leave()
                }
            }
            group.notify(queue: .main) { onDrop(collected.urls) }
            return true
        }
    }
}

extension View {
    /// Liquid Glass on macOS 26+ (follows the user's glass and transparency settings), otherwise the
    /// closest older material.
    @ViewBuilder func peelGlass<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
    }
}
