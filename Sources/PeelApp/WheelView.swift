import AppKit
import PeelAppCore
import SwiftUI
import UniformTypeIdentifiers

/// The action wheel: translucent round chips on a frosted disc (so it's clear where Peel's wheel starts
/// and ends), with a small "More" hub in the middle. The chip under a dragged file fills with the Mac's
/// accent colour.
struct WheelView: View {
    let slots: [WheelSlot]
    let onDrop: (WheelSlot?, [URL]) -> Void   // nil slot = More…
    /// Developer aid for previews: show this slot as hovered (-1 = the hub).
    var previewHovered: Int? = nil

    static let size: CGFloat = 290
    private static let ring: CGFloat = 96
    @State private var hovered: Int?          // slot index under the drag; -1 = the hub

    private var lit: Int? { hovered ?? previewHovered }
    private func radians(_ index: Int) -> Double {
        (-90 + Double(index) * 360 / Double(max(slots.count, 1))) * .pi / 180
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                .padding(4)
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                ChipView(title: slot.label, systemImage: slot.systemImage, size: 66, lit: lit == index,
                         onTargeted: { setHovered(index, $0) }) { urls in onDrop(slot, urls) }
                    .offset(x: cos(radians(index)) * Self.ring, y: sin(radians(index)) * Self.ring)
            }
            ChipView(title: nil, systemImage: "ellipsis", size: 50, lit: lit == -1,
                     onTargeted: { setHovered(-1, $0) }) { urls in onDrop(nil, urls) }
                .help("More… — open these files in the Peel panel")
        }
        .frame(width: Self.size, height: Self.size)
        .animation(.easeOut(duration: 0.12), value: lit)
    }

    private func setHovered(_ index: Int, _ targeted: Bool) {
        if targeted { hovered = index } else if hovered == index { hovered = nil }
    }
}

/// One round chip; a drop target.
private struct ChipView: View {
    let title: String?
    let systemImage: String
    let size: CGFloat
    let lit: Bool
    let onTargeted: (Bool) -> Void
    let onDrop: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: title == nil ? 15 : 17, weight: .medium))
            if let title {
                Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(lit ? Color.white : Color.primary.opacity(title == nil ? 0.7 : 0.9))
        .background(Circle().fill(lit ? Color.accentColor : Color.primary.opacity(0.07)))
        .overlay(Circle().strokeBorder(Color.primary.opacity(lit ? 0 : 0.12), lineWidth: 0.5))
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
