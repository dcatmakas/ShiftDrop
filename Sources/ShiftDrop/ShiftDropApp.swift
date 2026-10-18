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
        #endif
    }
}
