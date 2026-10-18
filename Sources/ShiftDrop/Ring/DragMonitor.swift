import AppKit

/// Notices when the user is dragging files anywhere on screen and taps Shift.
///
/// Needs no Accessibility permission: mouse-down is a global *mouse* event monitor,
/// and while the button is held we poll the drag pasteboard and the modifier keys.
@MainActor
final class DragMonitor {
    /// Shift was pressed while files are being dragged. Called on every press.
    var onShiftPressed: ((_ files: [URL]) -> Void)?
    /// The mouse button was released, ending the drag.
    var onDragEnded: (() -> Void)?

    private var mouseDownMonitor: Any?
    private var pollTimer: Timer?
    private var dragChangeCount = 0
    private var draggedFiles: [URL] = []
    private var shiftWasDown = false

    func start() {
        guard mouseDownMonitor == nil else { return }
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseWentDown() }
        }
    }

    func stop() {
        if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
        mouseDownMonitor = nil
        stopPolling()
    }

    private func mouseWentDown() {
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        draggedFiles = []
        shiftWasDown = NSEvent.modifierFlags.contains(.shift)
        guard pollTimer == nil else { return }
        // Polling only runs while the button is held, so it costs nothing at rest.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            let wasDragging = !draggedFiles.isEmpty
            stopPolling()
            if wasDragging { onDragEnded?() }
            return
        }

        if draggedFiles.isEmpty {
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != dragChangeCount else { return }
            dragChangeCount = pasteboard.changeCount
            draggedFiles = Self.fileURLs(on: pasteboard)
            if draggedFiles.isEmpty { return }
        }

        let shiftDown = NSEvent.modifierFlags.contains(.shift)
        if shiftDown && !shiftWasDown { onShiftPressed?(draggedFiles) }
        shiftWasDown = shiftDown
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        draggedFiles = []
    }

    static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }
}
