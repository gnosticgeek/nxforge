// A game's box, for the front end: flat covers for the shelf and the grid (CoverTile), and a real box that turns
// (CaseModelView, SceneKit: front, back and spine as textures on a 105 × 170 × 10 box; drag it, or use a controller's right
// stick, and it eases back to its resting angle). The art is CoverStore's; a game without any gets a cover drawn from its
// icon, and every game's back falls back to a panel of its details.
import AppKit
import SceneKit
import SwiftUI

/// A front cover drawn from the game's icon, its name and its console (420 × 680, rendered once into a picture)
struct DrawnFront: View {
    let name: String
    let console: String
    let icon: NSImage?
    let tint: Color

    var body: some View {
        ZStack {
            Color.black
            LinearGradient(colors: [tint, tint.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                HStack { Text(console.uppercased()).font(.system(size: 19, weight: .bold)).kerning(4); Spacer() }
                    .padding(.horizontal, 28).frame(height: 54).background(Color.black.opacity(0.42))
                Spacer(minLength: 0)
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(1, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 40)).shadow(color: .black.opacity(0.45), radius: 22, y: 12).padding(.horizontal, 40)
                } else {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 130)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Text(name).font(.system(size: 42, weight: .heavy)).lineLimit(3).minimumScaleFactor(0.55)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 30)
            }
            .foregroundStyle(.white)
        }
        .frame(width: 420, height: 680)
    }
}

/// A back cover with the game's details, for a game with no back art
struct DrawnBack: View {
    let name: String
    let lines: [(String, String)]
    let tint: Color

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.065, blue: 0.08)
            LinearGradient(colors: [tint.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
            VStack(alignment: .leading, spacing: 22) {
                Text(name).font(.system(size: 36, weight: .heavy)).lineLimit(3).minimumScaleFactor(0.6)
                Rectangle().fill(.white.opacity(0.25)).frame(height: 2)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l.0.uppercased()).font(.system(size: 14, weight: .bold)).kerning(2.5).foregroundStyle(.white.opacity(0.6))
                        Text(l.1).font(.system(size: 24, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
                Text("NXFORGE").font(.system(size: 16, weight: .heavy)).kerning(5).foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white)
            .padding(34)
        }
        .frame(width: 420, height: 680)
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
        if let a = g.app { return NSWorkspace.shared.icon(forFile: a) }
        return nil
    }

    static func tint(_ g: StageGame) -> Color { CoverStore.shared.tint(g.coverKey, icon: g.icon ?? g.app) }

    static func front(_ g: StageGame) -> NSImage? {
        let store = CoverStore.shared
        if let i = store.image(g.coverKey, .front) { return i }
        return store.drawn(g.coverKey + "-front-" + (g.icon ?? g.app ?? "")) {
            render(DrawnFront(name: g.name, console: g.console.rawValue, icon: icon(g), tint: tint(g)))
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
        return store.drawn(g.coverKey + "-back-\(Int(g.total))") { render(DrawnBack(name: g.name, lines: lines, tint: tint(g))) }
    }

    static func spine(_ g: StageGame) -> NSImage? {
        let store = CoverStore.shared
        if let i = store.image(g.coverKey, .spine) { return i }
        return store.drawn(g.coverKey + "-spine") { render(DrawnSpine(name: g.name, tint: tint(g))) }
    }
}

/// A flat cover, as on the shelf and in the grid: the art under a gloss, lifted with a white ring when it has the focus.
struct CoverTile: View {
    let game: StageGame
    var focused = false
    var dim = false

    var body: some View {
        let _ = CoverStore.shared.revision
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 3, bottomTrailing: 7, topTrailing: 7))
        Color.gray.opacity(0.3)
            .aspectRatio(CoverSource.aspect, contentMode: .fit)
            .overlay {
                if let img = CoverArt.front(game) {
                    Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                }
            }
            .overlay { LinearGradient(stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .clear, location: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing) }
            .overlay(alignment: .leading) { LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 6) }
            .overlay { if dim { Color.black.opacity(0.58) } }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white, lineWidth: focused ? 3 : 0))
            .shadow(color: .black.opacity(focused ? 0.7 : 0.5), radius: focused ? 22 : 9, y: focused ? 16 : 7)
            .scaleEffect(focused ? 1.07 : 1)
            .offset(y: focused ? -8 : 0)
            .animation(.spring(duration: 0.25), value: focused)
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
        let v = SCNView(frame: .zero)
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
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
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
        let scene = SCNScene()
        let node: SCNNode
        private let materials: [SCNMaterial]
        // read by the render loop, written by the main thread: plain numbers, a late read only costs a frame
        var rest: Double
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
            super.init()
            scene.rootNode.addChildNode(node)
            let cam = SCNNode()
            cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 24
            cam.position = SCNVector3(x: 0, y: 0, z: 4.9)
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
            node.eulerAngles = SCNVector3(x: 0.05, y: CGFloat(rest), z: 0)
        }

        func set(front: NSImage?, back: NSImage?, spine: NSImage?, edge: NSColor) {
            let ids = [front, back, spine].map { $0.map { ObjectIdentifier($0) } }
            guard ids != shown else { return }
            shown = ids
            materials[0].diffuse.contents = front ?? edge
            materials[2].diffuse.contents = back ?? edge
            materials[3].diffuse.contents = spine ?? edge
            for i in [1, 4, 5] { materials[i].diffuse.contents = edge }
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
                if time - touched > 2.5 {
                    // ease to the nearest turn that shows the resting side, with a slow sway
                    let turn = 2 * Double.pi
                    let target = rest + turn * ((angle - rest) / turn).rounded() + 0.07 * sin(time * 0.6)
                    angle += (target - angle) * min(1, 2.4 * dt)
                }
            }
            node.eulerAngles = SCNVector3(x: 0.05, y: CGFloat(angle), z: 0)
        }
    }
}

/// A game's box in 3D with its art, its shadow under it.
struct GameCase: View {
    let game: StageGame
    var flipped = false

    var body: some View {
        let _ = CoverStore.shared.revision
        CaseModelView(front: CoverArt.front(game), back: CoverArt.back(game), spine: CoverArt.spine(game), rest: flipped ? 0.48 + .pi : 0.48)
            .background(alignment: .bottom) {
                Ellipse().fill(.black.opacity(0.6)).frame(height: 30).padding(.horizontal, 40).blur(radius: 18).offset(y: -6)
            }
            .accessibilityLabel("\(game.name) box")
    }
}
