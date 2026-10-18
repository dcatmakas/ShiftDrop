import ShiftDropCore
import SwiftUI

/// The pie menu: a glass disc with one rounded wedge per action and a pill in the middle.
struct RingView: View {
    @ObservedObject var model: RingModel

    var body: some View {
        ZStack {
            disc

            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                SegmentView(
                    action: action,
                    index: index,
                    count: model.actions.count,
                    isHovered: model.hoveredIndex == index
                )
            }
            .id(model.mode) // fresh views per page so the swap animates
            .transition(.asymmetric(
                insertion: .scale(scale: 0.92).combined(with: .opacity),
                removal: .opacity
            ))

            CenterPill(text: model.centerText, isHovering: model.hoveredIndex != nil)
        }
        .frame(width: RingGeometry.panelSize, height: RingGeometry.panelSize)
        .scaleEffect(model.isVisible ? 1 : 0.7)
        .opacity(model.isVisible ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: model.isVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.mode)
        .animation(.easeOut(duration: 0.12), value: model.hoveredIndex)
    }

    @ViewBuilder
    private var disc: some View {
        let size = RingGeometry.outerRadius * 2
        let shape = Circle()
        if #available(macOS 26.0, *) {
            shape
                .fill(Palette.disc.opacity(0.35))
                .frame(width: size, height: size)
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Palette.disc.opacity(0.35)))
                .overlay(shape.strokeBorder(.white.opacity(0.55), lineWidth: 1))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }
}

enum Palette {
    static let disc = Color(red: 1.0, green: 0.93, blue: 0.86)
    static let segment = Color(red: 1.0, green: 0.88, blue: 0.76)
    static let segmentHover = Color(red: 0.94, green: 0.33, blue: 0.11)
    static let ink = Color(red: 0.33, green: 0.2, blue: 0.13)
    static let pill = Color(red: 1.0, green: 0.92, blue: 0.84)
}

private struct SegmentView: View {
    let action: RingAction
    let index: Int
    let count: Int
    let isHovered: Bool

    var body: some View {
        let slice = 2 * Double.pi / Double(count)
        let mid = RingGeometry.centerAngle(of: index, count: count)
        let wedge = WedgeShape(
            start: mid - slice / 2, end: mid + slice / 2,
            inner: RingGeometry.segmentInner, outer: RingGeometry.segmentOuter,
            halfGap: count > 1 ? RingGeometry.gap / 2 : 0, corner: RingGeometry.corner
        )
        let fill = isHovered ? Palette.segmentHover : Palette.segment

        ZStack {
            // Fill + a thick round-joined stroke of the same color = a wedge with rounded corners.
            wedge.fill(fill)
                .overlay(wedge.stroke(fill, style: StrokeStyle(lineWidth: RingGeometry.corner * 2, lineJoin: .round)))
                .compositingGroup()
                .opacity(isHovered ? 1 : 0.92)
                .shadow(color: .black.opacity(isHovered ? 0.18 : 0.06), radius: isHovered ? 6 : 2, y: 1)

            label
                .foregroundStyle(isHovered ? Color.white : Palette.ink)
                .position(labelPosition(angle: mid))
        }
        .frame(width: RingGeometry.panelSize, height: RingGeometry.panelSize)
        .scaleEffect(isHovered ? 1.04 : 1)
    }

    @ViewBuilder
    private var label: some View {
        if let symbol = action.symbol {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(action.title).font(.system(size: 9.5, weight: .bold)).tracking(0.3)
            }
            .fixedSize()
        } else {
            Text(action.title)
                .font(.system(size: 13, weight: .bold))
                .tracking(0.4)
                .fixedSize()
        }
    }

    private func labelPosition(angle: Double) -> CGPoint {
        let c = RingGeometry.panelSize / 2
        let r = RingGeometry.labelRadius + 4
        return CGPoint(x: c + r * sin(angle), y: c - r * cos(angle))
    }
}

private struct CenterPill: View {
    let text: String
    let isHovering: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 14)
            .frame(minWidth: 84, minHeight: 34)
            .background(
                Capsule().fill(Palette.pill)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            )
            .frame(maxWidth: RingGeometry.segmentInner * 2 - 8)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.1), value: text)
    }
}

/// An annular wedge with parallel-sided gaps. Corners get rounded by the caller's stroke,
/// so the path is shrunk by `corner` on every side to compensate.
struct WedgeShape: Shape {
    var start: Double
    var end: Double
    var inner: CGFloat
    var outer: CGFloat
    var halfGap: CGFloat
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rIn = inner + corner
        let rOut = outer - corner
        let offset = halfGap + corner

        // Angular inset that keeps the side edges parallel to the radius line.
        func inset(at radius: CGFloat) -> Double { Double(asin(min(1, offset / radius))) }
        let outStart = start + inset(at: rOut), outEnd = end - inset(at: rOut)
        let inStart = start + inset(at: rIn), inEnd = end - inset(at: rIn)

        func point(_ angle: Double, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y - radius * CGFloat(cos(angle)))
        }

        var path = Path()
        let steps = 32
        path.move(to: point(outStart, rOut))
        for step in 1...steps {
            path.addLine(to: point(outStart + (outEnd - outStart) * Double(step) / Double(steps), rOut))
        }
        path.addLine(to: point(inEnd, rIn))
        for step in 1...steps {
            path.addLine(to: point(inEnd + (inStart - inEnd) * Double(step) / Double(steps), rIn))
        }
        path.closeSubpath()
        return path
    }
}
