import ServiceManagement
import ShiftDropCore
import SwiftUI

@main
struct ShiftDropApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("ShiftDrop", systemImage: "circle.circle") {
            Toggle("Enabled", isOn: $state.isEnabled)
            Toggle("Launch at Login", isOn: $state.launchesAtLogin)
            Divider()
            Text("Drag files, then tap ⇧ Shift to open the ring.")
            Text("Tap ⇧ again to switch Convert ↔ Tools.")
            Divider()
            Button("Quit ShiftDrop") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Wires drag detection to the ring and the ring to the action runner.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "enabled")
            isEnabled ? monitor.start() : monitor.stop()
        }
    }

    @Published var launchesAtLogin: Bool {
        didSet {
            guard launchesAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchesAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Toast.shared.show("Launch at login: \(error.localizedDescription)", style: .failure)
            }
        }
    }

    #if DEBUG
    /// SHIFTDROP_SELFTEST_DRAG="x,y,dx,dy" (points from the window's top-left) drags with synthetic
    /// mouse events inside the open editor and prints whether the window or the editor moved.
    static func selfTestDrag(_ spec: String) {
        let n = spec.split(separator: ",").compactMap { Double($0) }
        guard n.count == 4, let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }),
              let content = window.contentView else {
            print("SELFTEST error: no editor window"); NSApp.terminate(nil); return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let start = NSPoint(x: n[0], y: content.bounds.height - n[1])
        let frameBefore = window.frame.origin
        let hit = content.hitTest(content.convert(start, from: nil))
        print("SELFTEST hitView=\(hit.map { String(describing: type(of: $0)) } ?? "nil") canMoveWindow=\(hit?.mouseDownCanMoveWindow ?? false) movableByBackground=\(window.isMovableByWindowBackground)")
        let stateBefore = EditorWindows.debugState?() ?? "-"

        func post(_ type: NSEvent.EventType, _ point: NSPoint) {
            let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            )!
            NSApp.postEvent(event, atStart: false)
        }
        post(.leftMouseDown, start)
        for step in 1...12 {
            let f = Double(step) / 12
            post(.leftMouseDragged, NSPoint(x: start.x + n[2] * f, y: start.y - n[3] * f))
        }
        post(.leftMouseUp, NSPoint(x: start.x + n[2], y: start.y - n[3]))

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let moved = window.frame.origin != frameBefore
            print("SELFTEST key=\(window.isKeyWindow) windowMoved=\(moved) before[\(stateBefore)] after[\(EditorWindows.debugState?() ?? "-")]")
            NSApp.terminate(nil)
        }
    }
    #endif

    private let monitor = DragMonitor()
    private let ring = RingController()
    private let dispatcher = ActionDispatcher()

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        launchesAtLogin = SMAppService.mainApp.status == .enabled

        monitor.onShiftPressed = { [ring] files in ring.shiftPressed(files: files) }
        monitor.onDragEnded = { [ring] in ring.dragEnded() }
        ring.onAction = { [dispatcher] action, urls in dispatcher.perform(action, on: urls) }

        if isEnabled { monitor.start() }

        #if DEBUG
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--demo-ring"), args.count > flag + 1 {
            let file = URL(fileURLWithPath: args[flag + 1])
            let mode: RingMode = args.contains("tools") ? .tools : .convert
            let hover = args.last.flatMap(Int.init)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [ring] in
                ring.showDemo(files: [file], mode: mode, hoveredIndex: hover)
            }
        }
        // `--demo-editor crop|bg <image>`; with SHIFTDROP_SNAPSHOT it saves the window to a PNG and quits.
        if let flag = args.firstIndex(of: "--demo-editor"), args.count > flag + 2 {
            let file = URL(fileURLWithPath: args[flag + 2])
            let crop = args[flag + 1] == "crop"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                crop ? EditorWindows.openCrop(file) { _ in } : EditorWindows.openAddBackground(file) { _ in }
                if let spec = ProcessInfo.processInfo.environment["SHIFTDROP_SELFTEST_DRAG"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { AppState.selfTestDrag(spec) }
                    return
                }
                guard let path = ProcessInfo.processInfo.environment["SHIFTDROP_SNAPSHOT"] else { return }
                if let name = ProcessInfo.processInfo.environment["SHIFTDROP_APPEARANCE"] {
                    NSApp.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard let view = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) })?.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    NSApp.terminate(nil)
                }
            }
        }
        #endif
    }
}
