import SwiftUI

/// Colors and small controls shared by the editor windows (warm, light look from the ring menu).
enum EditorStyle {
    static let accent = Color(red: 0xF0 / 255, green: 0x53 / 255, blue: 0x1C / 255)
    static let panel = Color(red: 1.0, green: 0xF1 / 255, blue: 0xE6 / 255)
    static let panelDeep = Color(red: 0xFC / 255, green: 0xE3 / 255, blue: 0xCF / 255)
    static let control = Color.white.opacity(0.75)
    static let ink = Color(red: 0.24, green: 0.15, blue: 0.10)
    static let inkSoft = Color(red: 0.24, green: 0.15, blue: 0.10).opacity(0.6)
}

/// Window chrome: centered title at the top, cream background.
struct EditorChrome<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EditorStyle.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            content
        }
        .background(
            LinearGradient(colors: [EditorStyle.panel, EditorStyle.panelDeep], startPoint: .top, endPoint: .bottom)
        )
        .ignoresSafeArea()
    }
}

/// A row of pill buttons where exactly one is selected (aspect ratio pickers).
struct PillPicker<Item: Identifiable & Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item == selection
                Button { selection = item } label: {
                    Text(title(item))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : EditorStyle.ink)
                        .frame(minWidth: 34)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selected ? EditorStyle.accent : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(EditorStyle.control))
    }
}

/// Orange slider drawn in SwiftUI so it matches the rest of the editor.
struct AccentSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            let thumb: CGFloat = 16
            let x = (geo.size.width - thumb) * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08)).frame(height: 4)
                Capsule().fill(EditorStyle.accent).frame(width: x + thumb / 2, height: 4)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .frame(width: thumb, height: thumb)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let f = (drag.location.x - thumb / 2) / max(1, geo.size.width - thumb)
                    value = (range.lowerBound + min(max(f, 0), 1) * span).rounded()
                }
            )
        }
        .frame(height: 18)
    }
}

/// Label, slider and the current value in px.
struct SliderRow: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EditorStyle.inkSoft)
                .frame(width: 70, alignment: .leading)
            AccentSlider(value: $value, range: range)
            Text("\(Int(value)) px")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(EditorStyle.inkSoft)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(EditorStyle.accent.opacity(configuration.isPressed ? 0.8 : 1))
            )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(EditorStyle.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(EditorStyle.control.opacity(configuration.isPressed ? 0.5 : 1))
            )
    }
}

/// Gray-white checkerboard shown behind transparent areas.
struct Checkerboard: View {
    var cell: CGFloat = 8

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let cols = Int(ceil(size.width / cell)), rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for col in 0..<cols where (row + col) % 2 == 0 {
                    let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    ctx.fill(Path(rect), with: .color(Color(white: 0.88)))
                }
            }
        }
    }
}

extension View {
    /// Inline error text under the controls.
    func errorBanner(_ message: String?) -> some View {
        overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
                    .padding(.bottom, 56)
                    .transition(.opacity)
            }
        }
    }
}
