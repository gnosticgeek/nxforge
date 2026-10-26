// Draws the converter's app icon: a white game controller with a small hammer on a blue-to-violet rounded square,
// on the macOS icon grid (an 824-point shape in a 1024-point canvas). bundle.sh turns it into AppIcon.icns.
// Usage: swift app/make_icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let shape = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = NSBezierPath(roundedRect: shape, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.47, blue: 1.0, alpha: 1), NSColor(srgbRed: 0.45, green: 0.25, blue: 0.93, alpha: 1)])!
        .draw(in: path, angle: -60)
    // a soft highlight on the top half, as on the system's icons
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(roundedRect: shape, xRadius: 185, yRadius: 185), angle: -90)

    func symbol(_ name: String, points: CGFloat, in rect: NSRect) {
        let cfg = NSImage.SymbolConfiguration(pointSize: points, weight: .semibold).applying(.init(paletteColors: [.white]))
        guard let s = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
        let fit = min(rect.width / s.size.width, rect.height / s.size.height)
        let w = s.size.width * fit, h = s.size.height * fit
        s.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }
    symbol("gamecontroller.fill", points: 400, in: NSRect(x: 210, y: 300, width: 604, height: 440))
    // the hammer: the game is built, not emulated
    let badge = NSRect(x: 620, y: 150, width: 240, height: 240)
    NSColor(srgbRed: 0.10, green: 0.12, blue: 0.30, alpha: 0.9).setFill()
    NSBezierPath(ovalIn: badge).fill()
    symbol("hammer.fill", points: 140, in: badge.insetBy(dx: 52, dy: 52))
    return true
}

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
