// A game's box, for the front end: flat covers for the shelf and the grid (CoverTile), and a real box that turns
// (CaseModelView, SceneKit: front, back and spine as textures on a 105 × 170 × 10 box; drag it, or use a controller's right
// stick, and it eases back to its resting angle). The art is CoverStore's; a game without any gets a cover drawn from its
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

    static func icon(_ g: StageGame) -> NSImage? {
        if let i = g.icon, let img = NSImage(contentsOfFile: i) { return img }
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
    @State private var hover: CGPoint?
    @State private var size: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let _ = CoverStore.shared.revision
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 3, bottomTrailing: 7, topTrailing: 7))
        let img = CoverArt.front(game)
        let tint = CoverArt.tint(game)
        Color(white: 0.14)
            .aspectRatio(CoverSource.aspect, contentMode: .fit)
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
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.40), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 5)
                    Rectangle().fill(.white.opacity(0.16)).frame(width: 1)
                }
            }
            .overlay { if dim { Color.black.opacity(0.44) } }
            .overlay(alignment: .top) { if game.favorite || attention != nil { CoverMarks(favorite: game.favorite, attention: attention) } }
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay {
                RoundedRectangle(cornerRadius: 11).strokeBorder(.white, lineWidth: 2.5).padding(-6)
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

/// The right stick turns the box on screen (ControllerNav writes it, the box's render loop reads it)
enum CaseStick {
    nonisolated(unsafe) static var x: Double = 0
}

/// The box in 3D.
struct CaseModelView: NSViewRepresentable {
    var front: NSImage?
    var back: NSImage?
    var spine: NSImage?
    var edge: NSColor = NSColor(white: 0.12, alpha: 1)
    /// the angle it rests at, in radians: a little turned, its spine in view; add π to show its back
    var rest: Double = 0.48

    func makeCoordinator() -> Coordinator { Coordinator(rest: rest) }

    func makeNSView(context: Context) -> SCNView {
        let v = CaseSCNView(frame: .zero)
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X   // 2X on a screen over 4K wide (CaseSCNView.fitToScreen)
        v.allowsCameraControl = false
        v.scene = context.coordinator.scene
        v.delegate = context.coordinator
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        v.addGestureRecognizer(NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:))))
        context.coordinator.set(front: front, back: back, spine: spine, edge: edge)
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        context.coordinator.set(front: front, back: back, spine: spine, edge: edge)
        context.coordinator.rest = rest
        context.coordinator.still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
        let scene = SCNScene()
        let node: SCNNode
        /// the box again upside down under the floor: its reflection (GameCase fades it out)
        private let mirror: SCNNode
        private let materials: [SCNMaterial]
        private let mirrorMaterials: [SCNMaterial]
        // read by the render loop, written by the main thread: plain numbers, a late read only costs a frame
        var rest: Double
        /// Reduce Motion: no sway, and a turn to the other side is a cut, not a spin
        var still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        private var angle: Double
        private var velocity = 0.0
        private var dragging = false
        private var touch = false
        private var touched = 0.0
        private var last = 0.0
        private var shown: [ObjectIdentifier?] = [nil, nil, nil]

        init(rest: Double) {
            self.rest = rest
            angle = rest
            let box = SCNBox(width: 1.05, height: 1.70, length: 0.10, chamferRadius: 0.006)
            materials = (0..<6).map { _ in
                let m = SCNMaterial()
                m.lightingModel = .blinn
                m.diffuse.contents = NSColor(white: 0.12, alpha: 1)
                m.specular.contents = NSColor(white: 0.35, alpha: 1)
                m.shininess = 0.35
                return m
            }
            box.materials = materials   // front, right, back, left, top, bottom
            node = SCNNode(geometry: box)
            let under = SCNBox(width: 1.05, height: 1.70, length: 0.10, chamferRadius: 0.006)
            mirrorMaterials = (0..<6).map { _ in
                let m = SCNMaterial()
                m.lightingModel = .blinn
                m.diffuse.contents = NSColor(white: 0.12, alpha: 1)
                m.specular.contents = NSColor.black
                return m
            }
            under.materials = mirrorMaterials
            mirror = SCNNode(geometry: under)
            super.init()
            scene.rootNode.addChildNode(node)
            let holder = SCNNode()
            holder.scale = SCNVector3(x: 1, y: -1, z: 1)
            holder.position = SCNVector3(x: 0, y: -1.725, z: 0)
            holder.addChildNode(mirror)
            scene.rootNode.addChildNode(holder)
            let cam = SCNNode()
            cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 24
            // looks a little below the box's middle, so the floor and the reflection under it are in view (GameCase.floor)
            cam.position = SCNVector3(x: 0, y: -0.30, z: 5.9)
            scene.rootNode.addChildNode(cam)
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
            node.eulerAngles = SCNVector3(x: 0.05, y: CGFloat(rest), z: 0)
            mirror.eulerAngles = node.eulerAngles
        }

        func set(front: NSImage?, back: NSImage?, spine: NSImage?, edge: NSColor) {
            let ids = [front, back, spine].map { $0.map { ObjectIdentifier($0) } }
            guard ids != shown else { return }
            shown = ids
            materials[0].diffuse.contents = front ?? edge
            materials[2].diffuse.contents = back ?? edge
            materials[3].diffuse.contents = spine ?? edge
            for i in [1, 4, 5] { materials[i].diffuse.contents = edge }
            for i in 0..<6 { mirrorMaterials[i].diffuse.contents = materials[i].diffuse.contents }
        }

        @MainActor @objc func pan(_ g: NSPanGestureRecognizer) {
            let dx = Double(g.translation(in: g.view).x)
            g.setTranslation(.zero, in: g.view)
            switch g.state {
            case .began, .changed:
                dragging = true
                angle += dx * 0.012
                velocity = Double(g.velocity(in: g.view).x) * 0.012
            default:
                dragging = false
            }
            touch = true
        }

        func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = last == 0 ? 0 : min(time - last, 0.1)
            last = time
            if touch { touch = false; touched = time }
            let stick = CaseStick.x
            if abs(stick) > 0.15 {
                velocity = stick * 3.2
                angle += velocity * dt
                touched = time
            } else if !dragging {
                angle += velocity * dt
                velocity *= exp(-4 * dt)
                if still && abs(velocity) < 0.01 {
                    let turn = 2 * Double.pi
                    angle = rest + turn * ((angle - rest) / turn).rounded()
                } else if time - touched > 2.5 {
                    // ease to the nearest turn that shows the resting side, with a slow sway
                    let turn = 2 * Double.pi
                    let target = rest + turn * ((angle - rest) / turn).rounded() + 0.07 * sin(time * 0.6)
                    angle += (target - angle) * min(1, 2.4 * dt)
                }
            }
            node.eulerAngles = SCNVector3(x: 0.05, y: CGFloat(angle), z: 0)
            mirror.eulerAngles = node.eulerAngles
        }
    }
}

/// The box's view: it draws only while its window is on screen (a game in front of NXForge, or NXForge hidden, stops it: the GPU is the
/// game's), and on a screen more than 4K wide with 2X multisampling instead of 4X, which costs a quarter as much there.
final class CaseSCNView: SCNView {
    private var watch: [NSObjectProtocol] = []

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
        let visible = w.occlusionState.contains(.visible)
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
    /// where the floor is, down the view (CaseModelView's camera)
    static let floor = 0.722

    var body: some View {
        let _ = CoverStore.shared.revision
        let tint = CoverArt.tint(game)
        CaseModelView(front: CoverArt.front(game), back: CoverArt.back(game), spine: CoverArt.spine(game), rest: flipped ? 0.48 + .pi : 0.48)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: Self.floor + 0.004),
                                         .init(color: .black.opacity(0.24), location: Self.floor + 0.03), .init(color: .clear, location: 0.93)],
                                 startPoint: .top, endPoint: .bottom))
            .background {
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    Ellipse().fill(RadialGradient(colors: [tint.opacity(0.40), tint.opacity(0)], center: .center, startRadius: 0, endRadius: h * 0.55))
                        .frame(width: h * 1.1, height: h * 0.95).position(x: w / 2, y: h * 0.38)
                    Ellipse().fill(.black.opacity(0.62)).frame(width: h * 0.50, height: h * 0.045).blur(radius: h * 0.028).position(x: w / 2, y: h * (Self.floor + 0.012))
                }
            }
            .accessibilityLabel("\(game.name) box")
    }
}
