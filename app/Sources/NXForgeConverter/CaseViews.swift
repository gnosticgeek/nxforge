// A game's box, for the front end: flat covers for the shelf and the grid (CoverTile), and a real box that turns
// (CaseModelView, SceneKit: front, back and spine printed on an insert inside a clear case of a real one's measurements, CaseSize;
// drag it, or use a controller's right stick, and it eases back to its resting angle; the box viewer, CaseViewer, turns it any way
// and zooms). The art is CoverStore's; a game without any gets a cover drawn from its
// icon, and every game's back falls back to a panel of its details.
import AppKit
import CoreImage
import SceneKit
import SwiftUI

/// A front cover drawn from the game's icon, its name and its console (420 × 680, rendered once into a picture): the icon
/// spread out of focus over the whole cover as its artwork, and sharp on top of it
struct DrawnFront: View {
    let name: String
    let console: String
    let icon: NSImage?
    let wash: NSImage?
    let tint: Color

    var body: some View {
        ZStack {
            Color.black
            LinearGradient(colors: [tint, tint.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            if let wash {
                Image(nsImage: wash).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: 420, height: 680).scaleEffect(1.25).blur(radius: 18).saturation(1.9).contrast(1.15).clipped()
                tint.opacity(0.22)
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.30), location: 0), .init(color: .black.opacity(0.02), location: 0.32),
                                   .init(color: .black.opacity(0.10), location: 0.55), .init(color: .black.opacity(0.78), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 7, height: 22)
                    Text(console.uppercased()).font(.system(size: 17, weight: .heavy)).fontWidth(.expanded).kerning(3)
                    Spacer()
                }
                .padding(.horizontal, 26).frame(height: 58).background(Color.black.opacity(0.38))
                Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
                Spacer(minLength: 0)
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(1, contentMode: .fit)
                        .frame(width: 236, height: 236)
                        .clipShape(.rect(cornerRadius: 54))
                        .overlay(RoundedRectangle(cornerRadius: 54).strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 3))
                        .shadow(color: .black.opacity(0.55), radius: 26, y: 16)
                } else {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 130)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Text(name).font(.system(size: 40, weight: .heavy)).tracking(-0.8).lineLimit(3).minimumScaleFactor(0.55)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                    .padding(.horizontal, 28).padding(.bottom, 30)
            }
            .foregroundStyle(.white)
        }
        .frame(width: 420, height: 680)
        .clipped()
    }
}

/// A download-only game's box (420 × 680, rendered once into a picture and kept as its front): the console's red band across the
/// top as on a printed Switch box, the game's square shop art full width under it, and below that the same art carried on out
/// of focus behind the game's name
struct EShopFront: View {
    let name: String
    let console: String
    let art: NSImage
    /// "JoyMasher · 2019": the developer and the year it came out
    var detail = ""

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            // the art's lower edge stretched and blurred down the rest of the box, so the picture seems to carry on
            Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                .frame(width: 420, height: 680).scaleEffect(x: 1.6, y: 1.6, anchor: .bottom).blur(radius: 26).saturation(1.3).clipped()
            LinearGradient(stops: [.init(color: .clear, location: 0.6), .init(color: .black.opacity(0.35), location: 0.75), .init(color: .black.opacity(0.75), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 7, height: 22)
                    Text(console.uppercased()).font(.system(size: 17, weight: .heavy)).fontWidth(.expanded).kerning(3)
                    Spacer()
                }
                .padding(.horizontal, 24).frame(height: 54)
                .background(Color(red: 0.90, green: 0.0, blue: 0.07))
                Image(nsImage: art).resizable().interpolation(.high).aspectRatio(1, contentMode: .fill)
                    .frame(width: 420, height: 420).clipped()
                    .overlay(alignment: .bottom) { LinearGradient(colors: [.clear, .black.opacity(0.22)], startPoint: .top, endPoint: .bottom).frame(height: 60) }
                Spacer(minLength: 0)
                Text(name).font(.system(size: 30, weight: .heavy)).tracking(-0.5).lineLimit(2).minimumScaleFactor(0.6)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                    .padding(.horizontal, 26)
                Text(detail.uppercased()).font(.system(size: 12, weight: .bold)).fontWidth(.expanded).kerning(2.5).lineLimit(1).minimumScaleFactor(0.6).opacity(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 26).padding(.top, 8).padding(.bottom, 26)
            }
            .foregroundStyle(.white)
        }
        .frame(width: 420, height: 680)
        .clipped()
    }
}

/// A back cover with the game's details, for a game with no back art
struct DrawnBack: View {
    let name: String
    let lines: [(String, String)]
    let wash: NSImage?
    let tint: Color

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.065, blue: 0.08)
            if let wash {
                Image(nsImage: wash).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: 420, height: 680).scaleEffect(1.25).blur(radius: 18).saturation(1.2).opacity(0.45).clipped()
            }
            LinearGradient(colors: [tint.opacity(0.45), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 22) {
                Text(name).font(.system(size: 36, weight: .heavy)).tracking(-0.6).lineLimit(3).minimumScaleFactor(0.6)
                Rectangle().fill(.white.opacity(0.25)).frame(height: 2)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l.0.uppercased()).font(.system(size: 13, weight: .bold)).fontWidth(.expanded).kerning(2).foregroundStyle(.white.opacity(0.6))
                        Text(l.1).font(.system(size: 24, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
                Text("NXFORGE").font(.system(size: 15, weight: .heavy)).fontWidth(.expanded).kerning(4).foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white)
            .padding(34)
        }
        .frame(width: 420, height: 680)
        .clipped()
    }
}

/// A spine with the game's name running down it
struct DrawnSpine: View {
    let name: String
    let tint: Color

    var body: some View {
        ZStack {
            Color.black
            tint.opacity(0.8)
            Text(name).font(.system(size: 20, weight: .bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: 620, height: 40).rotationEffect(.degrees(90))
        }
        .frame(width: 40, height: 680)
        .clipped()
    }
}

/// The pictures of a game's box, from CoverStore or drawn here.
@MainActor
enum CoverArt {
    private static func render<V: View>(_ v: V) -> NSImage? {
        let r = ImageRenderer(content: v)
        r.scale = 2
        return r.nsImage
    }

    /// A download-only game's box made from its square shop art (EShopFront), as a JPEG the size of a downloaded front
    static func eshopBox(name: String, console: String, square: Data, detail: String = "") -> Data? {
        guard let art = NSImage(data: square), art.isValid,
              let img = render(EShopFront(name: name, console: console, art: art, detail: detail)),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }

    static func icon(_ g: StageGame) -> NSImage? {
        if let i = g.icon, let img = IconImage.load(i) { return img }
        // an app built without an icon has the system's blank one: no picture is better than that
        if let a = g.app, let b = Bundle(path: a), let name = b.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           let file = b.path(forResource: name, ofType: name.hasSuffix(".icns") ? nil : "icns"),
           ((try? FileManager.default.attributesOfItem(atPath: file))?[.size] as? Int ?? 0) > 2048 { return NSWorkspace.shared.icon(forFile: a) }
        return nil
    }

    static func tint(_ g: StageGame) -> Color { CoverStore.shared.tint(g.coverKey, icon: g.icon ?? g.app) }

    static func front(_ g: StageGame) -> NSImage? {
        let store = CoverStore.shared
        if let i = store.image(g.coverKey, .front) { return i }
        return store.drawn(g.coverKey + "-front-" + (g.icon ?? g.app ?? "")) {
            let i = icon(g)
            return render(DrawnFront(name: g.name, console: g.console.rawValue, icon: i, wash: i.flatMap { small($0, 14) }, tint: tint(g)))
        }
    }

    /// The front for a tile on the shelf or in the grid: the cover's smaller copy (CoverStore.thumb), nil while it is being read
    /// (the tile shows its plain case for that moment), the drawn stand-in for a game without a cover
    static func tile(_ g: StageGame) -> NSImage? {
        if let t = CoverStore.shared.thumb(g.coverKey, .front) { return t }
        return front(g)
    }

    /// The square art for a tile (Settings › Square covers): Nintendo Life's or the store's, else the game's own icon (the same
    /// square art, smaller), else the front cut to a square about its top
    static func squareTile(_ g: StageGame) -> NSImage? {
        switch CoverStore.shared.squareThumb(g.coverKey) {
        case .some(let i): return i
        case .none: return icon(g) ?? tile(g)
        }
    }

    static func back(_ g: StageGame) -> NSImage? {
        let store = CoverStore.shared
        if let i = store.image(g.coverKey, .back) { return i }
        var lines: [(String, String)] = [("Console", g.console.rawValue)]
        if let v = g.version, !v.isEmpty { lines.append(("Version", v)) }
        if let p = g.game?.publisher, !p.isEmpty { lines.append(("Publisher", p)) }
        if let t = g.titleID { lines.append(("Title ID", t)) }
        if g.total > 0 { lines.append(("Played", Playtime.text(g.total))) }
        return store.drawn(g.coverKey + "-back-\(Int(g.total))") { render(DrawnBack(name: g.name, lines: lines, wash: icon(g).flatMap { small($0, 14) }, tint: tint(g))) }
    }

    /// The game's art at a few dozen pixels: spread over the stage out of focus, it is the room's light.
    static func ambient(_ g: StageGame) -> NSImage? {
        let store = CoverStore.shared
        let art = store.image(g.coverKey, .front)
        return store.drawn(g.coverKey + "-ambient2-" + (art == nil ? "icon" : "art")) { (art ?? icon(g)).flatMap { small($0, 56) }.flatMap { soften($0) } }
    }

    /// The small art blurred once, here, so the stage only scales it up: a live blur of the whole window cost a full-screen pass a frame
    /// on a 4K or 5K display (StageBackdrop)
    static func soften(_ img: NSImage) -> NSImage? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return img }
        let ci = CIImage(cgImage: cg)
        guard let f = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: ci.clampedToExtent(), kCIInputRadiusKey: 3.2]),
              let out = f.outputImage?.cropped(to: ci.extent),
              let done = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(out, from: ci.extent) else { return img }
        return NSImage(cgImage: done, size: img.size)
    }

    /// A picture scaled down so its longer side is `side` pixels
    static func small(_ img: NSImage, _ side: Int) -> NSImage? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width > 0, cg.height > 0 else { return nil }
        let k = Double(side) / Double(max(cg.width, cg.height))
        let w = max(Int(Double(cg.width) * k), 1), h = max(Int(Double(cg.height) * k), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: w, height: h)) }
    }

    static func spine(_ g: StageGame) -> NSImage? {
        let store = CoverStore.shared
        if let i = store.image(g.coverKey, .spine) { return i }
        return store.drawn(g.coverKey + "-spine") { render(DrawnSpine(name: g.name, tint: tint(g))) }
    }
}

/// A flat cover, as on the shelf and in the grid: the art in its case (a crease at the spine, light along its top edge),
/// tilting towards the pointer with a highlight under it, and lifted inside a ring lit in its own colour when it has the focus.
struct CoverTile: View {
    let game: StageGame
    var focused = false
    var dim = false
    /// its mirror image fading out under it, as on Home's shelf (drawn outside the tile's own frame)
    var reflect = false
    /// the most pressing thing the game needs a look at (GameAttention), as a mark in the cover's corner
    var attention: GameAttention? = nil
    /// why it cannot play, when it cannot (GameStatus), as a label along the cover's foot instead of only dimming it
    var status: GameStatus? = nil
    /// the game's square shop art in a rounded square, not its box (Settings › Square covers)
    var square = false
    @State private var hover: CGPoint?
    @State private var size: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let _ = CoverStore.shared.revision
        let shape = square ? UnevenRoundedRectangle(cornerRadii: .init(topLeading: 10, bottomLeading: 10, bottomTrailing: 10, topTrailing: 10))
                           : UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 3, bottomTrailing: 7, topTrailing: 7))
        let img = square ? CoverArt.squareTile(game) : CoverArt.tile(game)
        let tint = CoverArt.tint(game)
        Color(white: 0.14)
            .aspectRatio(square ? 1 : CoverSource.aspect, contentMode: .fit)
            .overlay {
                if let img {
                    Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill).saturation(dim ? 0.5 : 1)
                }
            }
            .overlay { LinearGradient(stops: [.init(color: .white.opacity(0.20), location: 0), .init(color: .clear, location: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing) }
            .overlay {
                if let h = hover {
                    RadialGradient(colors: [.white.opacity(0.30), .clear], center: UnitPoint(x: h.x, y: h.y), startRadius: 0, endRadius: max(size.width, 40) * 0.95)
                        .blendMode(.plusLighter)
                }
            }
            .overlay(alignment: .leading) {
                // a box's crease at the spine
                if !square {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0.40), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 5)
                        Rectangle().fill(.white.opacity(0.16)).frame(width: 1)
                    }
                }
            }
            .overlay { if dim { Color.black.opacity(0.44) } }
            .overlay(alignment: .top) { if game.favorite || attention != nil { CoverMarks(favorite: game.favorite, attention: attention) } }
            // Not built yet stays in the line under the cover (most of a library is): the label is for what blocks a build
            .overlay(alignment: .bottomLeading) { if let status, !status.playable, status != .notBuilt { CoverStatus(status: status) } }
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay {
                RoundedRectangle(cornerRadius: square ? 14 : 11).strokeBorder(.white, lineWidth: 2.5).padding(-6)
                    .shadow(color: tint.opacity(0.9), radius: 9)
                    .opacity(focused ? 1 : 0)
            }
            .shadow(color: focused ? tint.opacity(0.55) : .black.opacity(0.5), radius: focused ? 26 : 9, y: focused ? 14 : 7)
            .rotation3DEffect(.degrees(still ? 0 : hover.map { Double(0.5 - $0.y) * 13 } ?? 0), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(still ? 0 : hover.map { Double($0.x - 0.5) * 15 } ?? 0), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .scaleEffect(focused ? 1.07 : hover != nil ? 1.03 : 1)
            .offset(y: focused ? -8 : 0)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hover = size.width > 0 && size.height > 0 ? CGPoint(x: p.x / size.width, y: p.y / size.height) : nil
                case .ended: hover = nil
                }
            }
            .background(alignment: .top) {
                if reflect, let img, size.height > 0 {
                    Image(nsImage: img).resizable().interpolation(.medium).aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height).clipShape(shape)
                        .scaleEffect(x: 1, y: -1)
                        .mask(LinearGradient(stops: [.init(color: .white.opacity(0.34), location: 0), .init(color: .clear, location: 0.30)], startPoint: .top, endPoint: .bottom))
                        .offset(y: size.height + 5)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .animation(.spring(duration: 0.28), value: focused)
            .animation(.spring(duration: 0.35), value: hover == nil)
    }
}

/// The right stick turns the box on screen (ControllerNav writes it, the box's render loop reads it); in the box viewer its
/// up and down tilts it too
enum CaseStick {
    nonisolated(unsafe) static var x: Double = 0
    nonisolated(unsafe) static var y: Double = 0
}

/// A real case's measurements, in metres over 100 (1.0 = 100 mm): a Switch case is 105 × 170 mm and 10.5 mm deep (Switch 2's the
/// same, in red plastic), its corners rounded. The printed insert sits inside the clear sleeve, a little short of the edges on
/// the three sides that open, where the plastic shows.
enum CaseSize {
    static let width = 1.05, height = 1.70, depth = 0.105, corner = 0.032
    static let insertWidth = 1.025, insertHeight = 1.676, insertDepth = 0.094
    /// the insert lies against the spine: the clear lip is on the side that opens
    static let insertShift = -0.010
}

/// The box in 3D.
struct CaseModelView: NSViewRepresentable {
    var front: NSImage?
    var back: NSImage?
    var spine: NSImage?
    var edge: NSColor = NSColor(white: 0.12, alpha: 1)
    /// the plastic's colour: clear for Switch, see-through red for Switch 2
    var console: Console = .switch1
    /// the angle it rests at, in radians: a little turned, its spine in view; add π to show its back
    var rest: Double = 0.48
    /// the full-window box viewer: turns any way, zooms, no floor, and stays where it is left
    var viewer = false
    /// the viewer's controls (Front, Back, Spine, Reset, zoom): a request the render loop picks up
    var command: CaseCommand? = nil

    func makeCoordinator() -> Coordinator { Coordinator(rest: rest, viewer: viewer) }

    func makeNSView(context: Context) -> SCNView {
        let v = CaseSCNView(frame: .zero)
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X   // 2X on a screen over 4K wide (CaseSCNView.fitToScreen)
        v.allowsCameraControl = false
        v.scene = context.coordinator.scene
        v.delegate = context.coordinator
        v.rendersContinuously = true
        v.preferredFramesPerSecond = viewer ? 120 : 60
        v.coordinator = context.coordinator
        v.addGestureRecognizer(NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:))))
        if viewer {
            v.addGestureRecognizer(NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.magnify(_:))))
            let two = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.reset(_:)))
            two.numberOfClicksRequired = 2
            v.addGestureRecognizer(two)
        }
        context.coordinator.set(front: front, back: back, spine: spine, edge: edge, console: console)
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        context.coordinator.set(front: front, back: back, spine: spine, edge: edge, console: console)
        context.coordinator.rest = rest
        context.coordinator.still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let c = command, c.id != context.coordinator.lastCommand { context.coordinator.lastCommand = c.id; context.coordinator.apply(c) }
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
        let scene = SCNScene()
        /// the case: the printed insert inside the clear plastic
        let node = SCNNode()
        /// the box again upside down under the floor: its reflection (GameCase fades it out)
        private var mirror: SCNNode?
        private let materials: [SCNMaterial]
        private let shellFaces = SCNMaterial()
        private let shellEdges = SCNMaterial()
        private let camera = SCNNode()
        let viewer: Bool
        // read by the render loop, written by the main thread: plain numbers, a late read only costs a frame
        var rest: Double
        /// Reduce Motion: no sway, and a turn to the other side is a cut, not a spin
        var still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var lastCommand: UUID?
        private var angle: Double
        private var tilt = 0.05
        private var velocity = 0.0
        private var tiltVelocity = 0.0
        private var dragging = false
        private var touch = false
        private var touched = 0.0
        private var last = 0.0
        /// the viewer's camera distance, and where a Front/Back/Spine/Reset eases it to
        private var distance: Double
        private var goal: (angle: Double, tilt: Double, distance: Double)?
        private var shown: [ObjectIdentifier?] = [nil, nil, nil]
        private var shownConsole: Console?

        static let restDistance = 5.9
        /// the viewer's: the box about two thirds of the window's height
        static let viewerDistance = 6.6

        init(rest: Double, viewer: Bool) {
            self.rest = rest
            self.viewer = viewer
            angle = rest
            distance = viewer ? Self.viewerDistance : Self.restDistance
            let insert = SCNBox(width: CaseSize.insertWidth, height: CaseSize.insertHeight, length: CaseSize.insertDepth, chamferRadius: 0.002)
            materials = (0..<6).map { _ in
                let m = SCNMaterial()
                m.lightingModel = .blinn
                m.diffuse.contents = NSColor(white: 0.12, alpha: 1)
                m.specular.contents = NSColor(white: 0.18, alpha: 1)
                m.shininess = 0.25
                return m
            }
            insert.materials = materials   // front, right, back, left (the spine), top, bottom
            let paper = SCNNode(geometry: insert)
            paper.position = SCNVector3(x: CGFloat(CaseSize.insertShift), y: 0, z: 0)
            node.addChildNode(paper)
            // the clear plastic: a rounded slab, glossy on its faces and seen edge-on, thicker, along its sides
            let outline = NSBezierPath(roundedRect: NSRect(x: -CaseSize.width / 2, y: -CaseSize.height / 2, width: CaseSize.width, height: CaseSize.height),
                                       xRadius: CaseSize.corner, yRadius: CaseSize.corner)
            outline.flatness = 0.002
            let shell = SCNShape(path: outline, extrusionDepth: CaseSize.depth)
            shell.chamferRadius = 0.004
            for m in [shellFaces, shellEdges] {
                m.lightingModel = .blinn
                m.blendMode = .alpha
                m.writesToDepthBuffer = false
                m.isDoubleSided = false
                m.shininess = 0.9
            }
            shellFaces.specular.contents = NSColor(white: 0.85, alpha: 1)
            shellEdges.specular.contents = NSColor(white: 0.6, alpha: 1)
            // SCNShape's elements: front, back, sides, then the chamfers on each face
            shell.materials = [shellFaces, shellFaces, shellEdges, shellEdges, shellEdges]
            let plastic = SCNNode(geometry: shell)
            plastic.renderingOrder = 10   // over the insert, which shows through it
            plastic.castsShadow = false
            node.addChildNode(plastic)
            super.init()
            scene.rootNode.addChildNode(node)
            if !viewer {
                let under = node.clone()   // shares the geometry and the materials: new art reaches both
                let holder = SCNNode()
                holder.scale = SCNVector3(x: 1, y: -1, z: 1)
                holder.position = SCNVector3(x: 0, y: -1.725, z: 0)
                holder.addChildNode(under)
                scene.rootNode.addChildNode(holder)
                mirror = under
            }
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 24
            camera.camera?.zNear = 0.05
            // the shelf's camera looks a little below the box's middle, so the floor and the reflection under it are in view
            // (GameCase.floor); the viewer's looks straight at it
            camera.position = SCNVector3(x: 0, y: viewer ? 0 : -0.30, z: CGFloat(distance))
            scene.rootNode.addChildNode(camera)
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 620
            scene.rootNode.addChildNode(ambient)
            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 760
            key.eulerAngles = SCNVector3(x: -0.45, y: 0.55, z: 0)
            scene.rootNode.addChildNode(key)
            let rim = SCNNode()
            rim.light = SCNLight()
            rim.light?.type = .directional
            rim.light?.intensity = 420
            rim.eulerAngles = SCNVector3(x: -0.2, y: -2.3, z: 0)
            scene.rootNode.addChildNode(rim)
            if viewer {
                // light from below and behind as well: the viewer shows every side
                let fill = SCNNode()
                fill.light = SCNLight()
                fill.light?.type = .directional
                fill.light?.intensity = 300
                fill.eulerAngles = SCNVector3(x: 1.1, y: 2.6, z: 0)
                scene.rootNode.addChildNode(fill)
            }
            node.eulerAngles = SCNVector3(x: CGFloat(tilt), y: CGFloat(rest), z: 0)
            mirror?.eulerAngles = node.eulerAngles
        }

        func set(front: NSImage?, back: NSImage?, spine: NSImage?, edge: NSColor, console: Console) {
            let ids = [front, back, spine].map { $0.map { ObjectIdentifier($0) } }
            if ids != shown {
                shown = ids
                materials[0].diffuse.contents = front ?? edge
                materials[2].diffuse.contents = back ?? edge
                materials[3].diffuse.contents = spine ?? edge
            }
            guard console != shownConsole else { return }
            shownConsole = console
            let red = console == .switch2
            // what shows through the plastic on the three sides that open: the insert's white edges, front and back, and the
            // inside of the case between them
            materials[1].diffuse.contents = CaseEdgeArt.image(red: red, across: true)
            for i in [4, 5] { materials[i].diffuse.contents = CaseEdgeArt.image(red: red, across: false) }
            for i in [1, 4, 5] {
                // see-through between the cover's two edges: the case is hollow there, its tray clear
                let m = materials[i]
                m.specular.contents = NSColor(white: 0.05, alpha: 1)
                m.blendMode = .alpha
                m.transparencyMode = .aOne
                m.writesToDepthBuffer = false
            }
            // Switch: colourless and nearly clear; Switch 2: see-through red
            shellFaces.diffuse.contents = red ? NSColor(red: 0.85, green: 0.10, blue: 0.12, alpha: 0.10) : NSColor(white: 1, alpha: 0.05)
            shellEdges.diffuse.contents = red ? NSColor(red: 0.80, green: 0.06, blue: 0.10, alpha: 0.42) : NSColor(white: 0.95, alpha: 0.16)
            shellEdges.specular.contents = NSColor(white: red ? 0.7 : 0.95, alpha: 1)
        }

        /// The viewer's buttons
        func apply(_ c: CaseCommand) {
            let turn = 2 * Double.pi
            func near(_ a: Double) -> Double { a + turn * ((angle - a) / turn).rounded() }
            switch c.kind {
            case .front: goal = (near(0), 0, distance)
            case .back: goal = (near(.pi), 0, distance)
            case .spine: goal = (near(.pi / 2), 0, distance)
            case .reset: goal = (near(rest), 0.05, Self.viewerDistance)
            case .zoom(let k): goal = (angle, tilt, Self.clampDistance((goal?.distance ?? distance) / k))
            case .turn(let dx, let dy): goal = ((goal?.angle ?? angle) + dx, Self.clampTilt((goal?.tilt ?? tilt) + dy), goal?.distance ?? distance)
            }
            velocity = 0
            tiltVelocity = 0
            touch = true
        }

        static func clampDistance(_ d: Double) -> Double { min(max(d, 1.25), 12) }
        static func clampTilt(_ t: Double) -> Double { min(max(t, -1.45), 1.45) }

        @MainActor @objc func pan(_ g: NSPanGestureRecognizer) {
            let dx = Double(g.translation(in: g.view).x)
            let dy = Double(g.translation(in: g.view).y)
            g.setTranslation(.zero, in: g.view)
            goal = nil
            // nearer in, a drag turns it less: the part under the pointer keeps up with it
            let k = viewer ? 0.010 * min(1, distance / Self.viewerDistance) + 0.002 : 0.012
            switch g.state {
            case .began, .changed:
                dragging = true
                angle += dx * k
                velocity = Double(g.velocity(in: g.view).x) * k
                if viewer {
                    tilt = Self.clampTilt(tilt - dy * k)
                    tiltVelocity = -Double(g.velocity(in: g.view).y) * k
                }
            default:
                dragging = false
            }
            touch = true
        }

        @MainActor @objc func magnify(_ g: NSMagnificationGestureRecognizer) {
            goal = nil
            distance = Self.clampDistance(distance / (1 + Double(g.magnification)))
            g.magnification = 0
            touch = true
        }

        @MainActor @objc func reset(_ g: NSClickGestureRecognizer) { apply(CaseCommand(.reset)) }

        /// A scroll wheel or two fingers on a trackpad: up zooms in
        @MainActor func scroll(_ e: NSEvent) {
            guard viewer else { return }
            goal = nil
            let dy = Double(e.scrollingDeltaY) * (e.hasPreciseScrollingDeltas ? 1 : 12)
            distance = Self.clampDistance(distance * exp(-dy * 0.004))
            touch = true
        }

        func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = last == 0 ? 0 : min(time - last, 0.1)
            last = time
            if touch { touch = false; touched = time }
            let stick = CaseStick.x, stickY = viewer ? CaseStick.y : 0
            if abs(stick) > 0.15 || abs(stickY) > 0.15 {
                goal = nil
                velocity = abs(stick) > 0.15 ? stick * 3.2 : 0
                angle += velocity * dt
                if abs(stickY) > 0.15 { tilt = Self.clampTilt(tilt - stickY * 2.0 * dt) }
                tiltVelocity = 0
                touched = time
            } else if let g = goal {
                let k = still ? 1 : min(1, 7 * dt)
                angle += (g.angle - angle) * k
                tilt += (g.tilt - tilt) * k
                distance += (g.distance - distance) * k
                if abs(g.angle - angle) < 0.001, abs(g.tilt - tilt) < 0.001, abs(g.distance - distance) < 0.001 { goal = nil }
            } else if !dragging {
                angle += velocity * dt
                velocity *= exp(-4 * dt)
                if viewer {
                    tilt = Self.clampTilt(tilt + tiltVelocity * dt)
                    tiltVelocity *= exp(-4 * dt)
                } else if still && abs(velocity) < 0.01 {
                    let turn = 2 * Double.pi
                    angle = rest + turn * ((angle - rest) / turn).rounded()
                } else if time - touched > 2.5 {
                    // ease to the nearest turn that shows the resting side, with a slow sway
                    let turn = 2 * Double.pi
                    let target = rest + turn * ((angle - rest) / turn).rounded() + 0.07 * sin(time * 0.6)
                    angle += (target - angle) * min(1, 2.4 * dt)
                }
            }
            node.eulerAngles = SCNVector3(x: CGFloat(tilt), y: CGFloat(angle), z: 0)
            mirror?.eulerAngles = node.eulerAngles
            if viewer { camera.position = SCNVector3(x: 0, y: 0, z: CGFloat(distance)) }
        }
    }
}

/// A button of the box viewer, picked up by the box's render loop once
struct CaseCommand: Equatable {
    enum Kind: Equatable { case front, back, spine, reset, zoom(Double), turn(Double, Double) }
    let id = UUID()
    let kind: Kind
    init(_ kind: Kind) { self.kind = kind }
}

/// What shows through the clear plastic along a side that opens: the insert's front and back edges, white, with the inside of the
/// case between them (grey through clear plastic, dark red through Switch 2's)
enum CaseEdgeArt {
    @MainActor static var cache: [String: NSImage] = [:]

    /// `across`: the lines run down the picture (the side that opens), else along it (top and bottom)
    nonisolated static func image(red: Bool, across: Bool) -> NSImage {
        let key = "\(red)\(across)"
        if let i = MainActor.assumeIsolated({ cache[key] }) { return i }
        let n = 48, len = 8
        let size = across ? NSSize(width: n, height: len) : NSSize(width: len, height: n)
        let img = NSImage(size: size, flipped: false) { r in
            let inside = red ? NSColor(red: 0.55, green: 0.04, blue: 0.08, alpha: 0.30) : NSColor(white: 0.85, alpha: 0.10)
            inside.setFill()
            r.fill(using: .copy)
            NSColor(white: 0.93, alpha: 1).setFill()
            let line = 4.0
            if across {
                NSRect(x: 0, y: 0, width: line, height: r.height).fill()
                NSRect(x: r.width - line, y: 0, width: line, height: r.height).fill()
            } else {
                NSRect(x: 0, y: 0, width: r.width, height: line).fill()
                NSRect(x: 0, y: r.height - line, width: r.width, height: line).fill()
            }
            // the clear tray's ridge, in the middle
            (red ? NSColor(red: 0.45, green: 0.02, blue: 0.05, alpha: 0.45) : NSColor(white: 0.9, alpha: 0.28)).setFill()
            if across { NSRect(x: r.width * 0.45, y: 0, width: r.width * 0.10, height: r.height).fill() }
            else { NSRect(x: 0, y: r.height * 0.45, width: r.width, height: r.height * 0.10).fill() }
            return true
        }
        MainActor.assumeIsolated { cache[key] = img }
        return img
    }
}

/// The box's view: it draws only while its window is on screen (a game in front of NXForge, or NXForge hidden, stops it: the GPU is the
/// game's), and on a screen more than 4K wide with 2X multisampling instead of 4X, which costs a quarter as much there.
final class CaseSCNView: SCNView {
    private var watch: [NSObjectProtocol] = []
    weak var coordinator: CaseModelView.Coordinator?

    override func scrollWheel(with e: NSEvent) {
        if let c = coordinator, c.viewer { c.scroll(e) } else { super.scrollWheel(with: e) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        watch.forEach { NotificationCenter.default.removeObserver($0) }
        watch = []
        guard let w = window else { return }
        let nc = NotificationCenter.default
        watch.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToScreen() }
        })
        watch.append(nc.addObserver(forName: NSWindow.didChangeScreenNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToScreen() }
        })
        fitToScreen()
    }

    func fitToScreen() {
        guard let w = window else { return }
        // a snapshot's window may be behind others: it keeps drawing, so the picture shows the box where it was turned to
        let visible = w.occlusionState.contains(.visible) || ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] != nil
        if rendersContinuously != visible { rendersContinuously = visible; isPlaying = visible }
        let px = (w.screen?.frame.width ?? 0) * (w.screen?.backingScaleFactor ?? 1)
        let aa: SCNAntialiasingMode = px > 4000 ? .multisampling2X : .multisampling4X
        if antialiasingMode != aa { antialiasingMode = aa }
    }

    deinit { watch.forEach { NotificationCenter.default.removeObserver($0) } }
}

/// A game's box in 3D with its art, standing on a floor that reflects it, in a pool of its own colour.
struct GameCase: View {
    let game: StageGame
    var flipped = false
    /// how strong the game's colour glows behind the box (the game page keeps it faint over the key art)
    var glow: Double = 0.40
    /// where the floor is, down the view (CaseModelView's camera)
    static let floor = 0.722

    var body: some View {
        let _ = CoverStore.shared.revision
        let tint = CoverArt.tint(game)
        CaseModelView(front: CoverArt.front(game), back: CoverArt.back(game), spine: CoverArt.spine(game), console: game.console, rest: flipped ? 0.48 + .pi : 0.48)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: Self.floor + 0.004),
                                         .init(color: .black.opacity(0.24), location: Self.floor + 0.03), .init(color: .clear, location: 0.93)],
                                 startPoint: .top, endPoint: .bottom))
            .background {
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    Ellipse().fill(RadialGradient(colors: [tint.opacity(glow), tint.opacity(0)], center: .center, startRadius: 0, endRadius: h * 0.55))
                        .frame(width: h * 1.1, height: h * 0.95).position(x: w / 2, y: h * 0.38)
                    Ellipse().fill(.black.opacity(0.62)).frame(width: h * 0.50, height: h * 0.045).blur(radius: h * 0.028).position(x: w / 2, y: h * (Self.floor + 0.012))
                }
            }
            .accessibilityLabel("\(game.name) box")
    }
}
