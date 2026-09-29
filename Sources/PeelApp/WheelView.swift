import PeelAppCore
import SwiftUI
import UniformTypeIdentifiers

/// The action wheel: slots in a circle around a central "More…"; each slot is a drop target.
struct WheelView: View {
    let slots: [WheelSlot]
    let onDrop: (WheelSlot?, [URL]) -> Void   // nil slot = More…

    static let size: CGFloat = 280

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).frame(width: Self.size - 8, height: Self.size - 8)
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(max(slots.count, 1))
                SlotView(title: slot.label, systemImage: slot.systemImage) { urls in onDrop(slot, urls) }
                    .offset(x: cos(angle) * 96, y: sin(angle) * 96)
            }
            SlotView(title: "More…", systemImage: "ellipsis.circle", size: 76) { urls in onDrop(nil, urls) }
        }
        .frame(width: Self.size, height: Self.size)
    }
}

private struct SlotView: View {
    let title: String
    let systemImage: String
    var size: CGFloat = 70
    let onDrop: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 18, weight: .semibold))
            Text(title).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: size, height: size)
        .background(Circle().fill(targeted ? Color.accentColor : Color(nsColor: .windowBackgroundColor).opacity(0.9)))
        .foregroundStyle(targeted ? Color.white : Color.primary)
        .scaleEffect(targeted ? 1.12 : 1)
        .animation(.easeOut(duration: 0.12), value: targeted)
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
