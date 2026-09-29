import AppKit
import PeelAppCore
import SwiftUI
import UniformTypeIdentifiers

/// The action wheel: round action chips around a small "More" hub. While a file hovers over a chip,
/// that chip and a slice fanning out from the centre light up in the Mac's accent colour.
struct WheelView: View {
    let slots: [WheelSlot]
    let onDrop: (WheelSlot?, [URL]) -> Void   // nil slot = More…

    static let size: CGFloat = 290
    private static let ring: CGFloat = 98
    @State private var hovered: Int?          // slot index under the drag; -1 = the hub

    private var accent: Color { Color(nsColor: .controlAccentColor) }
    private var span: Double { 360 / Double(max(slots.count, 1)) }
    private func angle(_ index: Int) -> Double { -90 + Double(index) * span }

    var body: some View {
        ZStack {
            if let hovered, hovered >= 0 {
                let mid = angle(hovered)
                let slice = Sector(start: .degrees(mid - span / 2 + 1), end: .degrees(mid + span / 2 - 1), inner: 32, outer: 140)
                slice.fill(accent.opacity(0.35))
                    .overlay(slice.stroke(accent.opacity(0.8), lineWidth: 1.5))
                    .transition(.opacity)
            }
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                let radians = angle(index) * .pi / 180
                ChipView(title: slot.label, systemImage: slot.systemImage, size: 70, lit: hovered == index,
                         accent: accent, onTargeted: { setHovered(index, $0) }) { urls in onDrop(slot, urls) }
                    .offset(x: cos(radians) * Self.ring, y: sin(radians) * Self.ring)
            }
            ChipView(title: nil, systemImage: "ellipsis", size: 56, lit: hovered == -1, accent: accent,
                     onTargeted: { setHovered(-1, $0) }) { urls in onDrop(nil, urls) }
                .help("More… — open these files in the Peel panel")
        }
        .frame(width: Self.size, height: Self.size)
        .animation(.easeOut(duration: 0.12), value: hovered)
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
    let accent: Color
    let onTargeted: (Bool) -> Void
    let onDrop: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: title == nil ? 16 : 18, weight: .semibold))
            if let title {
                Text(title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(lit ? accent : Color(white: title == nil ? 0.22 : 0.16)))
        .overlay(Circle().stroke(Color.white.opacity(lit ? 0.5 : 0.12), lineWidth: 1))
        .foregroundStyle(Color.white.opacity(title == nil && !lit ? 0.8 : 1))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .scaleEffect(lit ? 1.1 : 1)
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

/// A ring slice (annular sector), drawn behind the hovered chip.
private struct Sector: Shape {
    var start: Angle
    var end: Angle
    var inner: CGFloat
    var outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: centre, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: centre, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
