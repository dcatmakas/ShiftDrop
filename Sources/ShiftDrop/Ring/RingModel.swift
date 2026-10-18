import AppKit
import QuickLookThumbnailing
import ShiftDropCore
import SwiftUI

/// State of the ring while it is on screen.
@MainActor
final class RingModel: ObservableObject {
    @Published private(set) var actions: [RingAction] = []
    @Published private(set) var mode: RingMode = .convert
    @Published var isVisible = false
    @Published private(set) var thumbnails: [NSImage] = []
    @Published var hoveredIndex: Int? {
        didSet { if hoveredIndex != oldValue { hoverChanged(from: oldValue) } }
    }
    /// Angle of the highlight, unwrapped so it always slides the short way round the dial.
    @Published private(set) var highlightAngle: Double = 0

    private(set) var files: [URL] = []
    private var sourceKind: FileKind = .other
    private var sizeText = ""

    var hoveredAction: RingAction? {
        hoveredIndex.flatMap { actions.indices.contains($0) ? actions[$0] : nil }
    }

    /// First line in the lens: the file, or what the hovered item will produce.
    var lensTitle: String {
        guard let action = hoveredAction else {
            return files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
        }
        switch action.kind {
        case .convert(let format):
            guard files.count == 1 else { return "\(files.count) \(format.label) files" }
            return files[0].deletingPathExtension().lastPathComponent + "." + format.fileExtension
        case .tool(let tool):
            return tool.title
        }
    }

    /// Second line in the lens: size of the files, or what the hovered item does.
    var lensSubtitle: String {
        hoveredAction?.hint(for: sourceKind) ?? sizeText
    }

    /// Fills the ring for `files`. Falls back to the other page if this one would be empty.
    /// Returns false if neither page has anything to offer.
    func load(files: [URL], mode: RingMode) -> Bool {
        let isNewDrag = files != self.files
        self.files = files
        let kinds = Set(files.map(FileKind.of))
        sourceKind = kinds.count == 1 ? kinds.first! : .other
        let bytes = files.reduce(Int64(0)) { $0 + $1.fileSize }
        sizeText = ByteFormat.string(bytes)
        hoveredIndex = nil
        if isNewDrag { loadThumbnails() }

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
        hoveredIndex = nil
        mode = next
        actions = list
    }

    private func hoverChanged(from old: Int?) {
        guard let index = hoveredIndex else { return }
        let target = RingGeometry.centerAngle(of: index, count: actions.count)
        if old == nil {
            // Appear in place rather than sliding in from wherever it was last time.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { highlightAngle = target }
        } else {
            let turns = ((highlightAngle - target) / (2 * .pi)).rounded()
            highlightAngle = target + turns * 2 * .pi
        }
        // A light detent on Force Touch trackpads, like a dial clicking into place.
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func loadThumbnails() {
        let shown = Array(files.prefix(3))
        thumbnails = shown.map { NSWorkspace.shared.icon(forFile: $0.path) }
        let current = files
        for (index, url) in shown.enumerated() {
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: 120, height: 120),
                scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
                guard let image = rep?.nsImage else { return }
                DispatchQueue.main.async {
                    guard let self, self.files == current, self.thumbnails.indices.contains(index) else { return }
                    self.thumbnails[index] = image
                }
            }
        }
    }
}

/// Sizes of the ring, shared by drawing and hit testing.
enum RingGeometry {
    static let panelSize: CGFloat = 440
    /// The glass dial.
    static let dialRadius: CGFloat = 156
    /// The band the items and highlight live in.
    static let bandInner: CGFloat = 88
    static let bandOuter: CGFloat = 150
    /// The center lens with the file preview.
    static let lensRadius: CGFloat = 80
    static let gap: CGFloat = 4
    static let corner: CGFloat = 12

    static var labelRadius: CGFloat { (bandInner + bandOuter) / 2 }

    /// Angle (radians, clockwise from 12 o'clock) of the middle of segment `index`.
    static func centerAngle(of index: Int, count: Int) -> Double {
        2 * .pi * Double(index) / Double(max(count, 1))
    }

    /// Segment under `point`, given relative to the ring center with y pointing up.
    /// Nil inside the lens (dropping there cancels) or well outside the dial.
    static func segment(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let distance = hypot(point.x, point.y)
        guard distance >= lensRadius, distance <= dialRadius + 40 else { return nil }
        var angle = atan2(point.x, point.y) // 0 at top, growing clockwise
        if angle < 0 { angle += 2 * .pi }
        let slice = 2 * .pi / Double(count)
        return Int((angle + slice / 2) / slice) % count
    }
}
