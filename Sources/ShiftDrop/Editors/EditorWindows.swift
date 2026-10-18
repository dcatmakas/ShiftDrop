import AppKit
import Foundation
import ShiftDropCore
import SwiftUI

/// Opens the Crop and Add BG editors. The app has no Dock icon, so each editor is a
/// standalone window that brings the app forward and is released when it closes.
@MainActor
enum EditorWindows {
    /// Opens the crop editor for an image. Calls onSaved with the written file.
    static func openCrop(_ url: URL, onSaved: @escaping (URL) -> Void) {
        let model: CropModel
        do {
            model = try CropModel(url: url)
        } catch {
            showError(error, for: url)
            return
        }
        #if DEBUG
        // Lets README screenshots show a crop in progress: SHIFTDROP_DEMO_CROP=square|wide|...
        if let raw = ProcessInfo.processInfo.environment["SHIFTDROP_DEMO_CROP"], let aspect = CropAspect(rawValue: raw) {
            model.aspect = aspect
        }
        #endif
        present(title: "Crop", size: NSSize(width: 520, height: 640)) { close in
            CropEditorView(model: model, onClose: close, onSaved: onSaved)
        }
    }

    /// Opens the "Add BG" (screenshot beautifier) editor for an image.
    static func openAddBackground(_ url: URL, onSaved: @escaping (URL) -> Void) {
        let model: BackgroundModel
        do {
            model = try BackgroundModel(url: url)
        } catch {
            showError(error, for: url)
            return
        }
        present(title: "Add background", size: NSSize(width: 560, height: 700)) { close in
            BackgroundEditorView(model: model, onClose: close, onSaved: onSaved)
        }
    }

    // MARK: - Window management

    /// Open editor windows, kept alive until they close.
    private static var windows: [ObjectIdentifier: (window: NSWindow, observer: NSObjectProtocol)] = [:]

    private static func present<Content: View>(
        title: String, size: NSSize, content: (_ close: @escaping () -> Void) -> Content
    ) {
        let window = EditorWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Narrower than the design width would clip the swatch rows and pickers.
        window.minSize = NSSize(width: size.width, height: 520)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let view = content { [weak window] in window?.close() }
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(size)
        window.center()

        let id = ObjectIdentifier(window)
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if let entry = windows.removeValue(forKey: id) {
                    NotificationCenter.default.removeObserver(entry.observer)
                }
            }
        }
        windows[id] = (window, observer)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func showError(_ error: Error, for url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Can't open \(url.lastPathComponent)"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

/// Closes on Esc.
private final class EditorWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
