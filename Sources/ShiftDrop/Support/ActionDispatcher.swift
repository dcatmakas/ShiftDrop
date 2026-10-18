import AppKit
import ShiftDropCore

/// Runs the item the files were dropped on and reports the outcome in a toast.
@MainActor
final class ActionDispatcher {
    func perform(_ action: RingAction, on urls: [URL]) {
        if case .tool(let tool) = action.kind, tool.isInteractive {
            openEditor(tool, for: urls)
            return
        }

        // Only show a spinner if the work takes long enough to notice.
        var finished = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if !finished { Toast.shared.show(Self.progressTitle(for: action), style: .progress) }
        }

        Task {
            do {
                let result = try await ActionRunner.run(action.kind, on: urls)
                finished = true
                report(result)
            } catch {
                finished = true
                Toast.shared.show(error.localizedDescription, style: .failure)
            }
        }
    }

    private func openEditor(_ tool: Tool, for urls: [URL]) {
        guard let url = urls.first else { return }
        guard FileKind.of(url) == .image else {
            Toast.shared.show("\(tool.title) works on images only", style: .failure)
            return
        }
        let onSaved: (URL) -> Void = { output in
            Toast.shared.show(output.lastPathComponent, detail: "Saved", style: .success)
        }
        switch tool {
        case .crop: EditorWindows.openCrop(url, onSaved: onSaved)
        case .addBackground: EditorWindows.openAddBackground(url, onSaved: onSaved)
        default: break
        }
    }

    private func report(_ result: RunResult) {
        if let text = result.textToCopy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        let title: String
        if result.outputs.count == 1 {
            title = result.outputs[0].lastPathComponent
        } else if result.outputs.count > 1 {
            title = "\(result.outputs.count) files created"
        } else {
            title = result.detail ?? "Done"
        }

        var details: [String] = []
        if let detail = result.detail, detail != title { details.append(detail) }
        if !result.failures.isEmpty { details.append("\(result.failures.count) failed") }

        Toast.shared.show(
            title, detail: details.isEmpty ? nil : details.joined(separator: " · "),
            style: result.failures.isEmpty ? .success : .failure
        )
    }

    private static func progressTitle(for action: RingAction) -> String {
        switch action.kind {
        case .convert(let format): return "Converting to \(format.label)…"
        case .tool(let tool): return "\(tool.title)…"
        }
    }
}
