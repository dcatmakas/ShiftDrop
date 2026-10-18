import AppKit
import ShiftDropCore
import SwiftUI

/// Which background swatch is selected.
enum BackgroundSwatch: Hashable {
    case gradient(Int)
    case solid(Int)
    case image
    case clear
}

@MainActor
final class BackgroundModel: ObservableObject {
    let url: URL
    /// Full-resolution, upright pixels; used when saving.
    let image: CGImage
    /// Smaller copy for the live preview.
    let preview: CGImage
    let size: CGSize

    @Published var swatch: BackgroundSwatch = .gradient(0) { didSet { refresh() } }
    @Published var customImage: CGImage? { didSet { refresh() } }
    @Published var padding: CGFloat { didSet { refresh() } }
    @Published var corners: CGFloat { didSet { refresh() } }
    @Published var shadow: CGFloat { didSet { refresh() } }
    @Published var ratio: CanvasRatio = .auto { didSet { refresh() } }

    @Published private(set) var rendered: CGImage?
    @Published var isSaving = false
    @Published var error: String?

    let paddingRange: ClosedRange<CGFloat>
    let cornerRange: ClosedRange<CGFloat>
    let shadowRange: ClosedRange<CGFloat> = 0...100

    /// Swatch thumbnails, rendered once with the same code as the output.
    let gradientThumbs: [CGImage]

    private let defaults: BackgroundSettings

    init(url: URL) throws {
        self.url = url
        image = try ImageFile.load(url)
        preview = (try? ImageFile.load(url, maxPixelSize: 1400)) ?? image
        size = CGSize(width: image.width, height: image.height)

        let longSide = max(size.width, size.height)
        paddingRange = 0...max(600, (longSide * 0.4).rounded())
        cornerRange = 0...max(200, (longSide * 0.15).rounded())

        defaults = BackgroundSettings.defaults(for: size)
        padding = min(defaults.padding, paddingRange.upperBound)
        corners = defaults.cornerRadius
        shadow = defaults.shadow
        gradientThumbs = BackgroundRenderer.gradients.compactMap {
            BackgroundRenderer.swatch(.gradient($0), pixelSize: 56)
        }
        refresh()
    }

    var settings: BackgroundSettings {
        BackgroundSettings(fill: fill, padding: padding, cornerRadius: corners, shadow: shadow, ratio: ratio)
    }

    private var fill: BackgroundFill {
        switch swatch {
        case .gradient(let i): return .gradient(BackgroundRenderer.gradients[i])
        case .solid(let i): return .solid(BackgroundRenderer.solids[i])
        case .image: return customImage.map { .image($0) } ?? .clear
        case .clear: return .clear
        }
    }

    func reset() {
        swatch = .gradient(0)
        padding = min(defaults.padding, paddingRange.upperBound)
        corners = defaults.cornerRadius
        shadow = defaults.shadow
        ratio = .auto
    }

    func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a background image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            customImage = try ImageFile.load(url, maxPixelSize: 4096)
            swatch = .image
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Re-renders the preview at about 1000 px on the long side.
    private func refresh() {
        let settings = self.settings
        let canvas = BackgroundRenderer.canvasSize(imageSize: size, padding: settings.padding, ratio: settings.ratio)
        let scale = min(1, 1000 / max(canvas.width, canvas.height))
        rendered = BackgroundRenderer.render(preview, logicalSize: size, settings: settings, scale: scale)
    }

    func save() async throws -> URL {
        isSaving = true
        defer { isSaving = false }
        return try await BackgroundRenderer.save(image, settings: settings, source: url)
    }
}

struct BackgroundEditorView: View {
    @ObservedObject var model: BackgroundModel
    var onClose: () -> Void
    var onSaved: (URL) -> Void

    var body: some View {
        EditorChrome(title: "Add background") {
            VStack(spacing: 14) {
                previewArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    swatches
                    SliderRow(title: "Padding", value: $model.padding, range: model.paddingRange)
                    SliderRow(title: "Corners", value: $model.corners, range: model.cornerRange)
                    SliderRow(title: "Shadow", value: $model.shadow, range: model.shadowRange)
                    HStack(spacing: 12) {
                        Text("Ratio")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(EditorStyle.inkSoft)
                            .frame(width: 70, alignment: .leading)
                        PillPicker(items: CanvasRatio.allCases, selection: $model.ratio, title: \.title)
                        Spacer()
                    }
                }

                Divider().opacity(0.5)

                HStack {
                    Button("Reset") { model.reset() }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button(model.isSaving ? "Saving…" : "Save copy") { save() }
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

    private func save() {
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

    // MARK: - Preview

    private var previewArea: some View {
        GeometryReader { geo in
            if let rendered = model.rendered {
                let size = fitted(CGSize(width: rendered.width, height: rendered.height), in: geo.size, inset: 14)
                ZStack {
                    Checkerboard()
                        .frame(width: size.width, height: size.height)
                    Image(decorative: rendered, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width, height: size.height)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(EditorStyle.well))
    }

    private func fitted(_ size: CGSize, in container: CGSize, inset: CGFloat) -> CGSize {
        let avail = CGSize(width: max(1, container.width - inset * 2), height: max(1, container.height - inset * 2))
        let scale = min(avail.width / size.width, avail.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    // MARK: - Swatches

    private var swatches: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Background")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EditorStyle.inkSoft)
                .frame(width: 70, alignment: .leading)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(model.gradientThumbs.indices, id: \.self) { i in
                        swatchButton(.gradient(i)) {
                            Image(decorative: model.gradientThumbs[i], scale: 2).resizable()
                        }
                    }
                    swatchButton(.image, action: { model.pickImage() }) {
                        ZStack {
                            if let custom = model.customImage {
                                Image(decorative: custom, scale: 1).resizable().scaledToFill()
                            } else {
                                EditorStyle.control
                                Image(systemName: "photo")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(EditorStyle.inkSoft)
                            }
                        }
                    }
                    .help("Use an image as the background")
                }
                HStack(spacing: 6) {
                    swatchButton(.clear) {
                        ZStack {
                            Checkerboard(cell: 5)
                            Path { p in
                                p.move(to: CGPoint(x: 22, y: 2)); p.addLine(to: CGPoint(x: 2, y: 22))
                            }
                            .stroke(Color.red.opacity(0.8), lineWidth: 1.5)
                        }
                    }
                    .help("Transparent")
                    ForEach(BackgroundRenderer.solids.indices, id: \.self) { i in
                        let c = BackgroundRenderer.solids[i]
                        swatchButton(.solid(i)) {
                            Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
                        }
                    }
                }
            }
        }
    }

    private func swatchButton<Content: View>(
        _ swatch: BackgroundSwatch, action: (() -> Void)? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        let selected = model.swatch == swatch
        return Button {
            if let action { action() } else { model.swatch = swatch }
        } label: {
            content()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
                .padding(2)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? EditorStyle.accent : Color.clear, lineWidth: 2)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
