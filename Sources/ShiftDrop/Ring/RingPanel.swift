import AppKit
import ShiftDropCore
import SwiftUI

/// Transparent, non-activating window that hosts the ring and receives the drop.
final class RingPanel: NSPanel {
    init(model: RingModel, onDrop: @escaping (RingAction, [URL]) -> Void) {
        let size = RingGeometry.panelSize
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        let hosting = NSHostingView(rootView: RingView(model: model))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        // Sits on top of the SwiftUI view so AppKit routes the drag session to it.
        let dropTarget = DropTargetView(model: model, onDrop: onDrop)
        dropTarget.frame = container.bounds
        dropTarget.autoresizingMask = [.width, .height]
        container.addSubview(dropTarget)

        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Tracks which wedge the dragged files are over and hands the drop to the controller.
private final class DropTargetView: NSView {
    private let model: RingModel
    private let onDrop: (RingAction, [URL]) -> Void

    init(model: RingModel, onDrop: @escaping (RingAction, [URL]) -> Void) {
        self.model = model
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        MainActor.assumeIsolated { model.hoveredIndex = nil }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        MainActor.assumeIsolated { model.hoveredAction != nil }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        MainActor.assumeIsolated {
            let index = segment(for: sender)
            model.hoveredIndex = index
            guard let action = model.hoveredAction else { return false }
            let urls = DragMonitor.fileURLs(on: sender.draggingPasteboard)
            guard !urls.isEmpty else { return false }
            onDrop(action, urls)
            return true
        }
    }

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated {
            let index = segment(for: sender)
            if model.hoveredIndex != index { model.hoveredIndex = index }
            // "Copy" shows the green plus badge and tells Finder to leave the original alone.
            return index == nil ? [] : .copy
        }
    }

    @MainActor
    private func segment(for sender: NSDraggingInfo) -> Int? {
        let local = convert(sender.draggingLocation, from: nil)
        let relative = CGPoint(x: local.x - bounds.midX, y: local.y - bounds.midY)
        return RingGeometry.segment(at: relative, count: model.actions.count)
    }
}
