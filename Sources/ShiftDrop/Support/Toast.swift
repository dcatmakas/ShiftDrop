import AppKit
import SwiftUI

/// A small bubble near the cursor that reports progress and results.
@MainActor
final class Toast {
    static let shared = Toast()

    enum Style { case progress, success, failure }

    private let model = ToastModel()
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 64),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: ToastView(model: model))
        return panel
    }()
    private var hideWork: DispatchWorkItem?

    func show(_ title: String, detail: String? = nil, style: Style) {
        hideWork?.cancel()
        model.title = title
        model.detail = detail
        model.style = style

        if !panel.isVisible {
            let mouse = NSEvent.mouseLocation
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 28))
            panel.orderFrontRegardless()
        }
        model.isVisible = true

        guard style != .progress else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (style == .failure ? 3.5 : 1.8), execute: work)
    }

    func hide() {
        model.isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.model.isVisible else { return }
            self.panel.orderOut(nil)
        }
    }
}

@MainActor
private final class ToastModel: ObservableObject {
    @Published var title = ""
    @Published var detail: String?
    @Published var style: Toast.Style = .progress
    @Published var isVisible = false
}

private struct ToastView: View {
    @ObservedObject var model: ToastModel

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = model.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(model.isVisible ? 1 : 0)
        .offset(y: model.isVisible ? 0 : -6)
        .animation(.easeOut(duration: 0.2), value: model.isVisible)
    }

    @ViewBuilder
    private var icon: some View {
        switch model.style {
        case .progress:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 16))
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 16))
        }
    }
}
