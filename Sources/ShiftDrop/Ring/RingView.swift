import ShiftDropCore
import SwiftUI

/// A glass dial: items around the rim, a highlight that slides to the hovered one,
/// and a lens in the middle showing the file and what the drop will produce.
struct RingView: View {
    @ObservedObject var model: RingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var count: Int { model.actions.count }
    static let isSnapshot = ProcessInfo.processInfo.environment["SHIFTDROP_SNAPSHOT"] != nil
    /// SHIFTDROP_SNAPSHOT_GLASS=clear leaves glass surfaces empty so a script can paint real blur behind them.
    static let snapshotGlassOpacity: Double = ProcessInfo.processInfo.environment["SHIFTDROP_SNAPSHOT_GLASS"] == "clear" ? 0 : 0.78
    private var slice: Double { 2 * .pi / Double(max(count, 1)) }

    var body: some View {
        ZStack {
            dial
            dividers
            highlight
            labels
            Lens(model: model)
            ModeSwitch(mode: model.mode)
                .offset(y: RingGeometry.dialRadius + 26)
        }
        .frame(width: RingGeometry.panelSize, height: RingGeometry.panelSize)
        .scaleEffect(model.isVisible || reduceMotion ? 1 : 0.86)
        .opacity(model.isVisible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.isVisible)
    }

    // MARK: - Layers

    @ViewBuilder
    private var dial: some View {
        let size = RingGeometry.dialRadius * 2
        if Self.isSnapshot {
            // Offscreen snapshots can't render glass; approximate it so layout can be reviewed.
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(Self.snapshotGlassOpacity))
                .overlay(Circle().strokeBorder(.white.opacity(Self.snapshotGlassOpacity > 0 ? 0.3 : 0), lineWidth: 0.5))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(Self.snapshotGlassOpacity > 0 ? 0.22 : 0), radius: 26, y: 12)
        } else if #available(macOS 26.0, *) {
            Circle()
                .fill(.clear)
                .frame(width: size, height: size)
                .glassEffect(.regular, in: Circle())
                .shadow(color: .black.opacity(0.22), radius: 26, y: 12)
        } else {
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.22), radius: 26, y: 12)
        }
    }

    /// Hairlines between items, like the marks on a dial.
    private var dividers: some View {
        Path { path in
            guard count > 1 else { return }
            let c = RingGeometry.panelSize / 2
            for index in 0..<count {
                let angle = RingGeometry.centerAngle(of: index, count: count) + slice / 2
                let from = RingGeometry.bandInner + 8, to = RingGeometry.bandOuter - 8
                path.move(to: CGPoint(x: c + from * sin(angle), y: c - from * cos(angle)))
                path.addLine(to: CGPoint(x: c + to * sin(angle), y: c - to * cos(angle)))
            }
        }
        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        .id(model.mode)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: model.mode)
    }

    private var highlight: some View {
        // With few items a full slice is a huge slab of color; cap it so it reads as a pointer.
        let width = min(slice, 64 * .pi / 180)
        let wedge = WedgeShape(
            start: model.highlightAngle - width / 2, end: model.highlightAngle + width / 2,
            inner: RingGeometry.bandInner, outer: RingGeometry.bandOuter,
            halfGap: count > 1 ? RingGeometry.gap / 2 : 0, corner: RingGeometry.corner
        )
        // Fill + a thick round-joined stroke of the same color = a wedge with rounded corners.
        let solid = ZStack {
            wedge.fill(Color.accentColor)
            wedge.stroke(Color.accentColor, style: StrokeStyle(lineWidth: RingGeometry.corner * 2, lineJoin: .round))
        }
        return solid
            .overlay(
                LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    .mask(solid)
            )
            .compositingGroup()
            .shadow(color: Color.accentColor.opacity(0.4), radius: 12)
            .opacity(model.hoveredIndex == nil ? 0 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.84), value: model.highlightAngle)
            .animation(.easeOut(duration: 0.12), value: model.hoveredIndex == nil)
    }

    private var labels: some View {
        ZStack {
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                ItemLabel(action: action, isHovered: model.hoveredIndex == index)
                    .position(labelPosition(index))
            }
        }
        .frame(width: RingGeometry.panelSize, height: RingGeometry.panelSize)
        .id(model.mode)
        // Switching pages turns the dial a notch.
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .modifier(active: DialTurn(degrees: -24, opacity: 0), identity: DialTurn(degrees: 0, opacity: 1)),
            removal: .modifier(active: DialTurn(degrees: 24, opacity: 0), identity: DialTurn(degrees: 0, opacity: 1))
        ))
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.mode)
    }

    private func labelPosition(_ index: Int) -> CGPoint {
        let angle = RingGeometry.centerAngle(of: index, count: count)
        let c = RingGeometry.panelSize / 2
        let r = RingGeometry.labelRadius
        return CGPoint(x: c + r * sin(angle), y: c - r * cos(angle))
    }
}

private struct DialTurn: ViewModifier {
    let degrees: Double
    let opacity: Double

    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(degrees)).opacity(opacity)
    }
}

private struct ItemLabel: View {
    let action: RingAction
    let isHovered: Bool

    var body: some View {
        Group {
            if let symbol = action.symbol {
                VStack(spacing: 5) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .regular))
                        .frame(height: 20)
                    Text(action.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: 70)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(action.title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.3)
                    .fixedSize()
            }
        }
        .foregroundStyle(isHovered ? Color.white : Color.primary.opacity(0.85))
        .scaleEffect(isHovered ? 1.06 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// The middle of the dial: a preview of the dragged file and what the drop will make.
private struct Lens: View {
    @ObservedObject var model: RingModel

    var body: some View {
        let size = RingGeometry.lensRadius * 2
        VStack(spacing: 7) {
            Thumbnails(images: model.thumbnails)
                .frame(height: 50)
            VStack(spacing: 2) {
                Text(model.lensTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.lensSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: size - 30)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.12), value: model.lensTitle)
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Color.primary.opacity(0.045)))
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

/// One preview, or up to three fanned out for several files.
private struct Thumbnails: View {
    let images: [NSImage]

    var body: some View {
        ZStack {
            ForEach(Array(images.enumerated().reversed()), id: \.offset) { index, image in
                let spread = Double(index) - Double(images.count - 1) / 2
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 50, maxHeight: 50)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .rotationEffect(.degrees(spread * 9))
                    .offset(x: spread * 9)
            }
        }
    }
}

/// Shows which page is open and that Shift flips it.
private struct ModeSwitch: View {
    let mode: RingMode
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            Text("⇧")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
            segment("Convert", active: mode == .convert)
            segment("Tools", active: mode == .tools)
        }
        .padding(3)
        .modifier(GlassCapsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: mode)
    }

    private func segment(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                if active {
                    Capsule().fill(Color.primary.opacity(0.1))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
    }
}

private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if RingView.isSnapshot {
            // A near-invisible fill in "clear" mode still marks the capsule's bounds for the compositing script.
            content.background(Color(nsColor: .windowBackgroundColor).opacity(max(RingView.snapshotGlassOpacity, 0.02)), in: Capsule())
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
        }
    }
}

/// An annular wedge with parallel-sided gaps. Corners get rounded by the caller's stroke,
/// so the path is shrunk by `corner` on every side to compensate. Angles animate.
struct WedgeShape: Shape {
    var start: Double
    var end: Double
    var inner: CGFloat
    var outer: CGFloat
    var halfGap: CGFloat
    var corner: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, end) }
        set { start = newValue.first; end = newValue.second }
    }

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
