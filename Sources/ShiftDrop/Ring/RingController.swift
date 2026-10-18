import AppKit
import ShiftDropCore

/// Shows the ring at the cursor when Shift is pressed mid-drag and hides it when the drag ends.
@MainActor
final class RingController {
    let model = RingModel()
    var onAction: ((RingAction, [URL]) -> Void)?

    private lazy var panel = RingPanel(model: model) { [weak self] action, urls in
        MainActor.assumeIsolated { self?.didDrop(action, urls) }
    }
    /// Bumped on every show/hide so a late hide can't close a newer ring.
    private var generation = 0

    func shiftPressed(files: [URL]) {
        if panel.isVisible, model.isVisible {
            model.toggleMode()
            return
        }
        guard model.load(files: files, mode: .convert) else { return }
        show(at: NSEvent.mouseLocation)
    }

    func dragEnded() {
        guard panel.isVisible else { return }
        // The drop message comes from the source app slightly after mouse-up; don't pull the target away early.
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.generation == current else { return }
            self.hide()
        }
    }

    #if DEBUG
    /// Shows the ring without a drag, for screenshots: `ShiftDrop --demo-ring <file> [tools] [hover-index]`.
    func showDemo(files: [URL], mode: RingMode, hoveredIndex: Int?) {
        guard model.load(files: files, mode: mode) else { return }
        let screen = NSScreen.main?.frame ?? .zero
        show(at: NSPoint(x: screen.midX, y: screen.midY))
        model.hoveredIndex = hoveredIndex

        // SHIFTDROP_SNAPSHOT=/path.png writes the panel to an image and quits (no screen recording permission needed).
        if let path = ProcessInfo.processInfo.environment["SHIFTDROP_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [panel] in
                guard let view = panel.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
    }
    #endif

    private func didDrop(_ action: RingAction, _ urls: [URL]) {
        hide()
        onAction?(action, urls)
    }

    private func show(at point: NSPoint) {
        generation += 1
        let size = RingGeometry.panelSize
        var frame = NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        // Keep the whole ring on screen; near an edge the cursor just won't be dead center.
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            let visible = screen.frame.insetBy(dx: -(size - RingGeometry.outerRadius * 2) / 2,
                                               dy: -(size - RingGeometry.outerRadius * 2) / 2)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - size)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - size)
        }
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        model.isVisible = false
        DispatchQueue.main.async { self.model.isVisible = true }
    }

    private func hide() {
        generation += 1
        let current = generation
        model.isVisible = false
        model.hoveredIndex = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.generation == current else { return }
            self.panel.orderOut(nil)
        }
    }
}
