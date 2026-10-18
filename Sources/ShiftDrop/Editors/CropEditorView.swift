import ShiftDropCore
import SwiftUI

@MainActor
final class CropModel: ObservableObject {
    let url: URL
    /// Full-resolution, upright pixels. The crop is cut from this.
    let image: CGImage
    /// Smaller copy for drawing on screen.
    let preview: CGImage
    let bounds: CGSize

    @Published var rect: CGRect
    @Published var aspect: CropAspect = .free {
        didSet {
            guard aspect != oldValue, let ratio = aspect.ratio else { return }
            rect = CropGeometry.fit(ratio: ratio, in: bounds)
        }
    }
    @Published var isSaving = false
    @Published var error: String?

    init(url: URL) throws {
        self.url = url
        image = try ImageFile.load(url)
        preview = (try? ImageFile.load(url, maxPixelSize: 2048)) ?? image
        bounds = CGSize(width: image.width, height: image.height)
        rect = CGRect(origin: .zero, size: bounds)
    }

    func reset() {
        aspect = .free
        rect = CGRect(origin: .zero, size: bounds)
    }

    func setWidth(_ width: Int) {
        var w = CGFloat(width)
        var h = rect.height
        if let ratio = aspect.ratio {
            w = min(w, bounds.width, bounds.height * ratio)
            h = w / ratio
        }
        rect = CropGeometry.resized(rect, width: w, height: h, bounds: bounds)
    }

    func setHeight(_ height: Int) {
        var h = CGFloat(height)
        var w = rect.width
        if let ratio = aspect.ratio {
            h = min(h, bounds.height, bounds.width / ratio)
            w = h * ratio
        }
        rect = CropGeometry.resized(rect, width: w, height: h, bounds: bounds)
    }

    func save() async throws -> URL {
        isSaving = true
        defer { isSaving = false }
        return try await CropRenderer.save(image, cropping: rect, source: url)
    }
}

struct CropEditorView: View {
    @ObservedObject var model: CropModel
    var onClose: () -> Void
    var onSaved: (URL) -> Void

    @State private var dragStart: CGRect?

    var body: some View {
        EditorChrome(title: "Crop Image") {
            VStack(spacing: 14) {
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 10) {
                    HStack {
                        Text("Aspect ratio")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(EditorStyle.inkSoft)
                        Spacer()
                        PillPicker(items: CropAspect.allCases, selection: $model.aspect, title: \.title)
                    }
                    HStack(spacing: 8) {
                        sizeField("W", value: Binding(
                            get: { Int(model.rect.width.rounded()) },
                            set: { model.setWidth($0) }
                        ))
                        sizeField("H", value: Binding(
                            get: { Int(model.rect.height.rounded()) },
                            set: { model.setHeight($0) }
                        ))
                        Text("px")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(EditorStyle.inkSoft)
                        Spacer()
                    }
                }

                Divider().opacity(0.5)

                HStack {
                    Button("Reset") { model.reset() }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button(model.isSaving ? "Saving…" : "Apply") { apply() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.isSaving)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
            .padding(.top, 4)
        }
        .errorBanner(model.error)
    }

    private func apply() {
        Task {
            do {
                let out = try await model.save()
                onClose()
                onSaved(out)
            } catch {
                model.error = error.localizedDescription
            }
        }
    }

    private func sizeField(_ label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EditorStyle.inkSoft)
            TextField("", value: value, format: .number.grouping(.never))
                .textFieldStyle(.plain)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(EditorStyle.ink)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(width: 74)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(EditorStyle.control))
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let inset: CGFloat = 14
            let fit = fittedRect(for: model.bounds, in: geo.size, inset: inset)
            let scale = fit.width / model.bounds.width
            let crop = CGRect(
                x: fit.minX + model.rect.minX * scale, y: fit.minY + model.rect.minY * scale,
                width: model.rect.width * scale, height: model.rect.height * scale
            )

            ZStack(alignment: .topLeading) {
                Image(decorative: model.preview, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)

                // Dim everything outside the crop.
                Path { path in
                    path.addRect(fit)
                    path.addRect(crop)
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                // Rule-of-thirds guides.
                Path { path in
                    for i in 1...2 {
                        let x = crop.minX + crop.width * CGFloat(i) / 3
                        let y = crop.minY + crop.height * CGFloat(i) / 3
                        path.move(to: CGPoint(x: x, y: crop.minY)); path.addLine(to: CGPoint(x: x, y: crop.maxY))
                        path.move(to: CGPoint(x: crop.minX, y: y)); path.addLine(to: CGPoint(x: crop.maxX, y: y))
                    }
                }
                .stroke(Color.white.opacity(dragStart == nil ? 0.0 : 0.6), lineWidth: 0.5)
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: crop.width, height: crop.height)
                    .position(x: crop.midX, y: crop.midY)
                    .gesture(dragGesture(scale: scale) { start, t in
                        CropGeometry.move(start, by: t, bounds: model.bounds)
                    })

                Rectangle()
                    .stroke(EditorStyle.accent, lineWidth: 1.5)
                    .frame(width: crop.width, height: crop.height)
                    .position(x: crop.midX, y: crop.midY)
                    .allowsHitTesting(false)

                ForEach(CropHandle.allCases, id: \.self) { handle in
                    handleView
                        .position(handle.point(in: crop))
                        .gesture(dragGesture(scale: scale) { start, t in
                            CropGeometry.resize(start, handle: handle, by: t, ratio: model.aspect.ratio, bounds: model.bounds)
                        })
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var handleView: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(EditorStyle.accent)
            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).stroke(Color.white, lineWidth: 1))
            .frame(width: 9, height: 9)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }

    /// Drag in view points, converted to image pixels relative to the rect at drag start.
    private func dragGesture(scale: CGFloat, update: @escaping (CGRect, CGSize) -> CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? model.rect
                if dragStart == nil { dragStart = start }
                let t = CGSize(width: value.translation.width / scale, height: value.translation.height / scale)
                model.rect = update(start, t)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func fittedRect(for size: CGSize, in container: CGSize, inset: CGFloat) -> CGRect {
        let avail = CGSize(width: max(1, container.width - inset * 2), height: max(1, container.height - inset * 2))
        let scale = min(avail.width / size.width, avail.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}
