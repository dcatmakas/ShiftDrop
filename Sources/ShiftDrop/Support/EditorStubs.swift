// TEMPORARY: replaced by Sources/ShiftDrop/Editors/EditorWindows.swift when the editors branch is merged.
import Foundation

@MainActor
enum EditorWindows {
    static func openCrop(_ url: URL, onSaved: @escaping (URL) -> Void) {
        Toast.shared.show("Crop editor coming soon", style: .failure)
    }

    static func openAddBackground(_ url: URL, onSaved: @escaping (URL) -> Void) {
        Toast.shared.show("Add BG editor coming soon", style: .failure)
    }
}
