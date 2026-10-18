import Foundation
import ShiftDropCore

/// State of the ring while it is on screen.
@MainActor
final class RingModel: ObservableObject {
    @Published private(set) var actions: [RingAction] = []
    @Published private(set) var mode: RingMode = .convert
    @Published var hoveredIndex: Int?
    @Published var isVisible = false

    private(set) var files: [URL] = []
    private var sizeText = ""

    /// What the center pill says: the hovered item, else the size of the dragged files.
    var centerText: String {
        if let hoveredIndex, actions.indices.contains(hoveredIndex) {
            return actions[hoveredIndex].title
        }
        return sizeText
    }

    var hoveredAction: RingAction? {
        hoveredIndex.flatMap { actions.indices.contains($0) ? actions[$0] : nil }
    }

    /// Fills the ring for `files`. Falls back to the other page if this one would be empty.
    /// Returns false if neither page has anything to offer.
    func load(files: [URL], mode: RingMode) -> Bool {
        self.files = files
        let bytes = files.reduce(Int64(0)) { $0 + $1.fileSize }
        sizeText = files.count == 1 ? ByteFormat.string(bytes) : "\(files.count) files"
        hoveredIndex = nil

        for candidate in [mode, mode.toggled] {
            let list = ActionCatalog.actions(for: files, mode: candidate)
            if !list.isEmpty {
                self.mode = candidate
                actions = list
                return true
            }
        }
        actions = []
        return false
    }

    /// Flips between Convert and Tools. Does nothing if the other page is empty.
    func toggleMode() {
        let next = mode.toggled
        let list = ActionCatalog.actions(for: files, mode: next)
        guard !list.isEmpty else { return }
        mode = next
        actions = list
        hoveredIndex = nil
    }
}

/// Sizes of the ring, shared by drawing and hit testing.
enum RingGeometry {
    static let panelSize: CGFloat = 380
    static let outerRadius: CGFloat = 152
    static let segmentOuter: CGFloat = 142
    static let segmentInner: CGFloat = 64
    static let gap: CGFloat = 7
    static let corner: CGFloat = 14

    static var labelRadius: CGFloat { (segmentInner + segmentOuter) / 2 }

    /// Angle (radians, clockwise from 12 o'clock) of the middle of segment `index`.
    static func centerAngle(of index: Int, count: Int) -> Double {
        2 * .pi * Double(index) / Double(max(count, 1))
    }

    /// Segment under `point`, given relative to the ring center with y pointing up.
    /// Nil inside the center hole (dropping there cancels) or well outside the ring.
    static func segment(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let distance = hypot(point.x, point.y)
        guard distance >= segmentInner - 6, distance <= outerRadius + 36 else { return nil }
        var angle = atan2(point.x, point.y) // 0 at top, growing clockwise
        if angle < 0 { angle += 2 * .pi }
        let slice = 2 * .pi / Double(count)
        return Int((angle + slice / 2) / slice) % count
    }
}
