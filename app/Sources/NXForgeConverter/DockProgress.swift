// The build's progress on the Dock icon: a bar under the app icon while a build runs, the step as a badge.
import AppKit

@MainActor
enum DockProgress {
    private final class Tile: NSView {
        var fraction = 0.0
        override func draw(_ dirty: NSRect) {
            NSApp.applicationIconImage?.draw(in: bounds)
            let bar = NSRect(x: bounds.width * 0.1, y: bounds.height * 0.06, width: bounds.width * 0.8, height: bounds.height * 0.09)
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
            var fill = bar.insetBy(dx: 3, dy: 3)
            fill.size.width = max(fill.height, fill.width * fraction)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: fill, xRadius: fill.height / 2, yRadius: fill.height / 2).fill()
        }
    }

    private static var tile: Tile?

    /// Called on every change of the run: the bar while it runs, the plain icon once it ends.
    static func show(_ run: BuildRun) {
        let dock = NSApp.dockTile
        guard run.running else {
            if tile != nil { tile = nil; dock.contentView = nil; dock.badgeLabel = nil; dock.display() }
            return
        }
        if tile == nil { tile = Tile(frame: NSRect(origin: .zero, size: dock.size)); dock.contentView = tile }
        let n = max(run.stage.n, 1)
        tile?.fraction = min(1, (Double(max(run.stage.k - 1, 0)) + (run.stage.fraction ?? 0)) / Double(n))
        dock.badgeLabel = run.stage.k > 0 ? "\(run.stage.k)/\(n)" : nil
        dock.display()
    }
}
