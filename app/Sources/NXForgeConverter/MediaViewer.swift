// The front end's full-window viewers, over everything on the stage (StageView), each taking the whole screen (the window goes full
// screen while one is open, and back after, when it was not already):
// - GalleryViewer: a game's pictures and trailers. Pictures zoom (pinch, scroll wheel, double-click) and pan (drag, two fingers);
//   arrows, a swipe or a controller's D-pad and shoulders go from one to the next, with a strip of them along the bottom. Nintendo's
//   own trailer files play in AVPlayer; Nintendo's trailers on YouTube in YouTube's embedded player, from youtube-nocookie.com, with
//   the ad servers it calls blocked (VideoAds).
// - CaseViewer: the game's box alone, to turn any way (drag, arrows, right stick) and zoom (pinch, scroll, + and −).
// - ManualViewer: a game's manual (a PDF: one beside the game's files, or one added on its page; GameManual), a page at a time.
import AppKit
import AVKit
import PDFKit
import SwiftUI
import WebKit

/// One thing in the gallery: a picture on disk, or a trailer with its picture
enum GalleryItem: Hashable, Identifiable {
    case image(URL)
    case video(StoreVideo, thumb: URL?)

    var id: String {
        switch self {
        case .image(let u): u.path
        case .video(let v, _): v.youtube ?? v.file ?? "video"
        }
    }

    var thumb: URL? {
        switch self {
        case .image(let u): u
        case .video(_, let t): t
        }
    }
}

@MainActor @Observable
final class GalleryState: Identifiable {
    let id = UUID()
    let title: String
    let items: [GalleryItem]
    var index: Int
    /// bumped by Space or a controller's Y: the trailer on screen plays or pauses
    var playToggle = 0
    /// bumped by + and −: the picture on screen zooms (sign: in or out), 0 back to fit
    var zoomStep = 0
    var zoomIn = true
    var zoomReset = 0

    init(title: String, items: [GalleryItem], index: Int) {
        self.title = title
        self.items = items
        self.index = min(max(index, 0), max(items.count - 1, 0))
    }

    var current: GalleryItem? { items.indices.contains(index) ? items[index] : nil }

    func step(_ d: Int) {
        guard !items.isEmpty else { return }
        index = (index + d + items.count) % items.count
    }
}

/// The game in the box viewer, and the viewer's last button
struct CaseViewerState: Identifiable, Equatable {
    let id = UUID()
    let game: StageGame
    var command: CaseCommand?
}

@MainActor @Observable
final class ManualState: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    /// bumped by the keys and a controller: the page to turn to or the zoom to set, picked up by the PDF view
    var action: (UUID, ManualAction)?

    init(title: String, url: URL) { self.title = title; self.url = url }
    func send(_ a: ManualAction) { action = (UUID(), a) }
}

enum ManualAction { case next, previous, zoomIn, zoomOut, fit }

extension AppModel {
    func openGallery(_ items: [GalleryItem], at index: Int, title: String) {
        guard !items.isEmpty else { return }
        gallery = GalleryState(title: title, items: items, index: index)
        viewerFullScreen(true)
    }

    func openCaseViewer(_ g: StageGame) {
        caseViewer = CaseViewerState(game: g, command: caseFlipped ? CaseCommand(.back) : nil)
        viewerFullScreen(true)
    }

    func openManual(_ url: URL, title: String) {
        manual = ManualState(title: title, url: url)
        viewerFullScreen(true)
    }

    func closeViewers() {
        gallery = nil
        caseViewer = nil
        manual = nil
        viewerFullScreen(false)
    }

    var viewerOpen: Bool { gallery != nil || caseViewer != nil || manual != nil }

    func caseCommand(_ k: CaseCommand.Kind) { caseViewer?.command = CaseCommand(k) }

    /// The window full screen while a viewer is open, and back as it was after (not for a snapshot: the picture is of the window)
    func viewerFullScreen(_ on: Bool) {
        guard ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil,
              let w = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) ?? NSApp.mainWindow else { return }
        let full = w.styleMask.contains(.fullScreen)
        if on, !full { viewerMadeFullScreen = true; w.toggleFullScreen(nil) }
        else if !on, viewerMadeFullScreen { viewerMadeFullScreen = false; if full { w.toggleFullScreen(nil) } }
    }

    /// A controller's button, or its key, while a viewer is open
    func viewerPad(_ k: PadKey) {
        if let g = gallery {
            switch k {
            case .left, .l: g.step(-1)
            case .right, .r: g.step(1)
            case .up: g.zoomIn = true; g.zoomStep += 1
            case .down: g.zoomIn = false; g.zoomStep += 1
            case .y, .a: g.playToggle += 1
            case .b, .menu: closeViewers()
            default: break
            }
        } else if caseViewer != nil {
            switch k {
            case .left: caseCommand(.turn(-.pi / 4, 0))
            case .right: caseCommand(.turn(.pi / 4, 0))
            case .up: caseCommand(.turn(0, -0.35))
            case .down: caseCommand(.turn(0, 0.35))
            case .l: caseCommand(.zoom(1 / 1.25))
            case .r: caseCommand(.zoom(1.25))
            case .y: caseCommand(.back)
            case .a: caseCommand(.reset)
            case .b, .menu: closeViewers()
            default: break
            }
        } else if let m = manual {
            switch k {
            case .left, .l, .up: m.send(.previous)
            case .right, .r, .down, .a: m.send(.next)
            case .y: m.send(.fit)
            case .b, .menu: closeViewers()
            default: break
            }
        }
    }

    /// A key while a viewer is open (ViewerKeys, which sees them first: a trailer's player or the manual may have the focus)
    func viewerKey(_ e: NSEvent) -> Bool {
        let chars = e.charactersIgnoringModifiers ?? ""
        switch e.keyCode {
        case 53: closeViewers(); return true                       // Esc
        case 123: viewerPad(.left); return true
        case 124: viewerPad(.right); return true
        case 125: if gallery != nil, gallery?.current.map({ if case .image = $0 { true } else { false } }) == false { return false }; viewerPad(.down); return true
        case 126: if gallery != nil, gallery?.current.map({ if case .image = $0 { true } else { false } }) == false { return false }; viewerPad(.up); return true
        case 49:                                                   // Space
            if caseViewer != nil { caseCommand(.back); return true }
            if let g = gallery, case .video(let v, _) = g.current, v.file != nil { g.playToggle += 1; return true }
            if manual != nil { viewerPad(.right); return true }
            return false
        default: break
        }
        if chars == "+" || chars == "=" {
            if let g = gallery { g.zoomIn = true; g.zoomStep += 1 } else if caseViewer != nil { caseCommand(.zoom(1.25)) } else { manual?.send(.zoomIn) }
            return true
        }
        if chars == "-" || chars == "_" {
            if let g = gallery { g.zoomIn = false; g.zoomStep += 1 } else if caseViewer != nil { caseCommand(.zoom(1 / 1.25)) } else { manual?.send(.zoomOut) }
            return true
        }
        if chars == "0" {
            if let g = gallery { g.zoomReset += 1 } else if caseViewer != nil { caseCommand(.reset) } else { manual?.send(.fit) }
            return true
        }
        return false
    }
}

/// Sees the keys before anything in the window while a viewer is open
struct ViewerKeys: View {
    let model: AppModel
    @State private var monitor: Any?

    var body: some View {
        Color.clear
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] e in
                    MainActor.assumeIsolated { model.viewerOpen && model.viewerKey(e) } ? nil : e
                }
            }
            .onDisappear { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }
            .allowsHitTesting(false)
    }
}

/// A round glass button of the viewers
struct ViewerButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.38, weight: .bold)).frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle).contentShape(.circle)
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

/// A capsule glass button of the viewers
struct ViewerPill: View {
    let title: String
    var symbol: String? = nil
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12.5, weight: .bold)) }
                Text(title).font(.system(size: 13.5, weight: .semibold))
            }
            .padding(.horizontal, 16).frame(height: 36)
            .glassEffect(on ? .regular.tint(.white.opacity(0.25)).interactive() : .regular.interactive(), in: .capsule).contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: gallery

struct GalleryViewer: View {
    let model: AppModel
    @Bindable var state: GalleryState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let item = state.current {
                GalleryPage(item: item, state: state).id(item.id)
                    .padding(.top, 70).padding(.bottom, state.items.count > 1 ? 116 : 30).padding(.horizontal, 84)
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title).font(.system(size: 17, weight: .bold)).lineLimit(1)
                        Text(caption).font(.system(size: 13)).foregroundStyle(StageLook.faint).lineLimit(1)
                    }
                    Spacer()
                    if case .image(let u) = state.current {
                        ViewerButton(symbol: "folder", label: "Show in Finder", size: 36) { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                        ShareLink(item: u) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36)
                                .glassEffect(.regular.interactive(), in: .circle).contentShape(.circle)
                        }
                        .buttonStyle(.plain).help("Share")
                    }
                    if case .video(let v, _) = state.current, let w = v.watchURL {
                        ViewerButton(symbol: "safari", label: v.youtube != nil ? "Open on YouTube" : "Open the video in the browser", size: 36) { NSWorkspace.shared.open(w) }
                    }
                    ViewerButton(symbol: "xmark", label: "Close (Esc)") { model.closeViewers() }
                }
                .padding(.horizontal, 24).padding(.top, 14)
                Spacer()
                if state.items.count > 1 { GalleryStrip(state: state).padding(.bottom, 16) }
            }
            if state.items.count > 1 {
                HStack {
                    ViewerButton(symbol: "chevron.left", label: "Previous (←)", size: 48) { withAnimation(.easeOut(duration: 0.18)) { state.step(-1) } }
                    Spacer()
                    ViewerButton(symbol: "chevron.right", label: "Next (→)", size: 48) { withAnimation(.easeOut(duration: 0.18)) { state.step(1) } }
                }
                .padding(.horizontal, 20)
            }
        }
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.18), value: state.index)
    }

    var caption: String {
        let n = "\(state.index + 1) of \(state.items.count)"
        switch state.current {
        case .video(let v, _): return n + " · " + (v.title ?? "Trailer") + (v.youtube != nil ? " · Nintendo on YouTube" : " · Nintendo")
        case .image(let u): return n + " · " + u.deletingPathExtension().lastPathComponent
        case nil: return ""
        }
    }
}

/// The strip along the bottom: every picture and trailer, the one on screen lit
struct GalleryStrip: View {
    @Bindable var state: GalleryState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(state.items.enumerated()), id: \.element.id) { i, item in
                        Button { state.index = i } label: {
                            let img = item.thumb.flatMap { ThumbStore.shared.image($0) }
                            Color(white: 0.14).frame(width: 112, height: 63)
                                .overlay { if let img { Image(nsImage: img).resizable().interpolation(.medium).aspectRatio(contentMode: .fill) } }
                                .overlay { if case .video = item { PlayGlyph(size: 26) } }
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(i == state.index ? Color.white : .white.opacity(0.15), lineWidth: i == state.index ? 2.5 : 1))
                                .opacity(i == state.index ? 1 : 0.62)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain).id(i)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 4)
                .frame(minWidth: 0)
            }
            .frame(maxWidth: .infinity)
            .onChange(of: state.index, initial: true) { _, i in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(i, anchor: .center) } }
        }
    }
}

/// The play mark on a trailer's picture
struct PlayGlyph: View {
    var size: CGFloat = 54

    var body: some View {
        Image(systemName: "play.fill").font(.system(size: size * 0.4, weight: .bold)).offset(x: size * 0.04)
            .frame(width: size, height: size)
            .background(.black.opacity(0.45), in: .circle)
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: max(1.5, size / 26)))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            .foregroundStyle(.white)
    }
}

struct GalleryPage: View {
    let item: GalleryItem
    let state: GalleryState

    var body: some View {
        switch item {
        case .image(let u):
            ZoomableImage(url: u, state: state)
        case .video(let v, _):
            if let id = v.youtube { YouTubePlayer(id: id) .aspectRatio(16 / 9, contentMode: .fit).clipShape(.rect(cornerRadius: 10)) }
            else if let f = v.file.flatMap(URL.init(string:)) { VideoFilePlayer(url: f, state: state).aspectRatio(16 / 9, contentMode: .fit) }
        }
    }
}

/// A picture that zooms and pans, natively: an NSScrollView that magnifies (pinch, a scroll wheel, a double-click, + and −), its picture
/// centred while it is smaller than the view. At its fitted size a swipe or a drag sideways goes to the next or the previous one.
struct ZoomableImage: NSViewRepresentable {
    let url: URL
    let state: GalleryState

    func makeNSView(context: Context) -> GalleryScrollView {
        let v = GalleryScrollView()
        v.onPage = { [weak state] d in MainActor.assumeIsolated { withAnimation(.easeOut(duration: 0.18)) { state?.step(d) } } }
        v.show(ThumbStore.shared.images[url])
        let u = url
        Task.detached(priority: .userInitiated) {
            guard let img = NSImage(contentsOf: u) else { return }
            await MainActor.run { v.show(img) }
        }
        context.coordinator.zoom = (state.zoomStep, state.zoomReset)
        return v
    }

    func updateNSView(_ v: GalleryScrollView, context: Context) {
        let now = (state.zoomStep, state.zoomReset)
        let was = context.coordinator.zoom
        context.coordinator.zoom = now
        if now.1 != was.1 { v.fit() } else if now.0 != was.0 { v.zoom(by: state.zoomIn ? 1.5 : 1 / 1.5) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var zoom = (0, 0) }
}

final class GalleryScrollView: NSScrollView {
    private let picture = GalleryImageView()
    var onPage: ((Int) -> Void)?
    private var swipe = 0.0
    private var swiped = false
    /// where a zoom is heading (the animator's magnification is the old one until it ends)
    private var target: CGFloat = 1

    init() {
        super.init(frame: .zero)
        contentView = CenteringClipView()
        drawsBackground = false
        contentView.drawsBackground = false
        hasHorizontalScroller = false
        hasVerticalScroller = false
        allowsMagnification = true
        minMagnification = 1
        maxMagnification = 8
        scrollerStyle = .overlay
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.wantsLayer = true
        picture.layer?.cornerRadius = 6
        picture.layer?.masksToBounds = true
        picture.owner = self
        documentView = picture
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ img: NSImage?) {
        guard let img else { return }
        let first = picture.image == nil
        picture.image = img
        if first { fit() } else { layoutPicture() }
    }

    /// The picture at the size that fits the view (magnification 1)
    func layoutPicture() {
        guard let img = picture.image, img.size.width > 0, img.size.height > 0, bounds.width > 0 else { return }
        let k = min(bounds.width / img.size.width, bounds.height / img.size.height)
        let size = NSSize(width: (img.size.width * k).rounded(), height: (img.size.height * k).rounded())
        if picture.frame.size != size { picture.setFrameSize(size) }
    }

    func fit() {
        layoutPicture()
        target = 1
        animator().magnification = 1
    }

    var fitted: Bool { magnification < 1.01 }

    func zoom(by k: CGFloat, at p: NSPoint? = nil) {
        target = min(max(max(target, magnification) * k, minMagnification), maxMagnification)
        let at = p ?? NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        let to = target
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().setMagnification(to, centeredAt: at)
        }
    }

    override func setFrameSize(_ s: NSSize) {
        super.setFrameSize(s)
        if fitted { layoutPicture() }
    }

    override func magnify(with e: NSEvent) {
        super.magnify(with: e)
        target = magnification
    }

    override func endGesture(with e: NSEvent) {
        super.endGesture(with: e)
        target = magnification
    }

    override func scrollWheel(with e: NSEvent) {
        // a mouse's wheel zooms at the pointer
        if !e.hasPreciseScrollingDeltas, e.phase.isEmpty, e.momentumPhase.isEmpty {
            let p = picture.convert(e.locationInWindow, from: nil)
            zoom(by: e.scrollingDeltaY > 0 ? 1.25 : 1 / 1.25, at: p)
            return
        }
        // two fingers sideways at the fitted size: the next or the previous picture
        if fitted {
            if e.phase == .began { swipe = 0; swiped = false }
            if !e.phase.isEmpty {
                swipe += e.scrollingDeltaX
                if !swiped, abs(swipe) > 70 { swiped = true; onPage?(swipe > 0 ? -1 : 1) }
            }
            return
        }
        super.scrollWheel(with: e)
    }

    /// A drag at the fitted size: far enough sideways, the next or the previous picture
    func dragEnded(dx: CGFloat) {
        if abs(dx) > 90 { onPage?(dx > 0 ? -1 : 1) }
    }
}

/// The picture: a double-click zooms in where it was clicked (or back to fit), a drag pans it when it is zoomed in
final class GalleryImageView: NSImageView {
    weak var owner: GalleryScrollView?
    private var start: NSPoint?
    private var origin: NSPoint = .zero

    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with e: NSEvent) {
        guard let o = owner else { return }
        if e.clickCount == 2 {
            if o.fitted { o.zoom(by: 2.5, at: convert(e.locationInWindow, from: nil)) } else { o.fit() }
            return
        }
        start = e.locationInWindow
        origin = o.contentView.bounds.origin
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with e: NSEvent) {
        guard let o = owner, let s = start, !o.fitted else { return }
        let k = 1 / o.magnification
        var p = NSPoint(x: origin.x - (e.locationInWindow.x - s.x) * k, y: origin.y - (e.locationInWindow.y - s.y) * k)
        let doc = frame.size, view = o.contentView.bounds.size
        p.x = min(max(p.x, 0), max(doc.width - view.width, 0))
        p.y = min(max(p.y, 0), max(doc.height - view.height, 0))
        o.contentView.scroll(to: p)
        o.reflectScrolledClipView(o.contentView)
    }

    override func mouseUp(with e: NSEvent) {
        NSCursor.pop()
        if let o = owner, let s = start, o.fitted { o.dragEnded(dx: e.locationInWindow.x - s.x) }
        start = nil
    }
}

/// Keeps a picture smaller than the view in its middle
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposed)
        guard let doc = documentView?.frame else { return r }
        if r.width > doc.width { r.origin.x = (doc.width - r.width) / 2 }
        if r.height > doc.height { r.origin.y = (doc.height - r.height) / 2 }
        return r
    }
}

/// Nintendo's own trailer file, in AVKit's player; it starts on its own and stops when it leaves the screen
struct VideoFilePlayer: NSViewRepresentable {
    let url: URL
    let state: GalleryState

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .floating
        v.showsFullScreenToggleButton = false
        v.allowsPictureInPicturePlayback = true
        v.videoGravity = .resizeAspect
        let p = AVPlayer(url: url)
        v.player = p
        context.coordinator.toggle = state.playToggle
        if ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil { p.play() }
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        guard state.playToggle != context.coordinator.toggle, let p = v.player else { return }
        context.coordinator.toggle = state.playToggle
        if p.timeControlStatus == .paused { p.play() } else { p.pause() }
    }

    static func dismantleNSView(_ v: AVPlayerView, coordinator: Coordinator) { v.player?.pause(); v.player = nil }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var toggle = 0 }
}

/// A trailer on YouTube in YouTube's own embedded player (youtube-nocookie.com: no cookies until it plays), with VideoAds' list
/// blocking the requests that fetch ads and count them. The page around the player is NXForge's own, so nothing else of YouTube's
/// shows.
struct YouTubePlayer: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.preferences.isElementFullscreenEnabled = true
        cfg.websiteDataStore = .nonPersistent()
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.setValue(false, forKey: "drawsBackground")
        v.underPageBackgroundColor = .black
        let autoplay = ProcessInfo.processInfo.environment["NXC_SNAPSHOT"] == nil ? 1 : 0
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
        iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head><body>
        <iframe src="https://www.youtube-nocookie.com/embed/\(id)?autoplay=\(autoplay)&rel=0&modestbranding=1&iv_load_policy=3&playsinline=1&fs=0&color=white"
          allow="autoplay; encrypted-media; picture-in-picture" referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
        VideoAds.rules { list in
            if let list { v.configuration.userContentController.add(list) }
            // a page of NXForge's own (YouTube's player wants to know which site it is on)
            v.loadHTMLString(html, baseURL: URL(string: "https://github.com/gnosticgeek/nxforge"))
        }
        return v
    }

    func updateNSView(_ v: WKWebView, context: Context) {}

    static func dismantleNSView(_ v: WKWebView, coordinator: ()) {
        v.stopLoading()
        v.loadHTMLString("", baseURL: nil)
    }
}

/// The content blocker for the YouTube player: the ad servers and the ad and tracking calls of YouTube's embedded player. Compiled
/// once by WebKit and kept.
@MainActor
enum VideoAds {
    private static var list: WKContentRuleList?
    private static var waiting: [(WKContentRuleList?) -> Void] = []
    private static var compiling = false

    static let json: String = {
        let filters = [
            #"^https?://([^/]+\.)?doubleclick\.net/"#,
            #"^https?://([^/]+\.)?googlesyndication\.com/"#,
            #"^https?://([^/]+\.)?googleadservices\.com/"#,
            #"^https?://([^/]+\.)?googletagservices\.com/"#,
            #"^https?://imasdk\.googleapis\.com/"#,
            #"^https?://([^/]+\.)?google\.com/pagead/"#,
            #"^https?://([^/]+\.)?youtube(-nocookie)?\.com/pagead/"#,
            #"^https?://([^/]+\.)?youtube(-nocookie)?\.com/api/stats/ads"#,
            #"^https?://([^/]+\.)?youtube(-nocookie)?\.com/ptracking"#,
            #"^https?://([^/]+\.)?youtube(-nocookie)?\.com/get_midroll_"#,
            #"^https?://([^/]+\.)?youtube(-nocookie)?\.com/youtubei/v1/log_event"#,
        ]
        let rules = filters.map { ["trigger": ["url-filter": $0], "action": ["type": "block"]] }
        let d = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(decoding: d, as: UTF8.self)
    }()

    static func rules(_ done: @escaping (WKContentRuleList?) -> Void) {
        if let list { done(list); return }
        waiting.append(done)
        guard !compiling else { return }
        compiling = true
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "nxforge-video-ads", encodedContentRuleList: json) { l, _ in
            MainActor.assumeIsolated {
                list = l
                compiling = false
                let w = waiting
                waiting = []
                w.forEach { $0(l) }
            }
        }
    }
}

// MARK: box

/// The box alone on a dark stage, in its own colour: drag to turn it any way, pinch or scroll to zoom, double-click to stand it back
struct CaseViewer: View {
    let model: AppModel
    let state: CaseViewerState

    var body: some View {
        let g = state.game
        let tint = CoverArt.tint(g)
        let _ = CoverStore.shared.revision
        ZStack {
            StageLook.background.ignoresSafeArea()
            RadialGradient(colors: [tint.opacity(0.42), tint.opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: 760).ignoresSafeArea()
            CaseModelView(front: CoverArt.front(g), back: CoverArt.back(g), spine: CoverArt.spine(g), console: g.console, rest: 0.48,
                          viewer: true, command: state.command)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.name).font(.system(size: 17, weight: .bold)).lineLimit(1)
                        Text(g.console == .switch2 ? "Nintendo Switch 2 case · 105 × 170 × 10.5 mm" : "Nintendo Switch case · 105 × 170 × 10.5 mm")
                            .font(.system(size: 13)).foregroundStyle(StageLook.faint)
                    }
                    Spacer()
                    if let m = GameManual.find(g) {
                        ViewerPill(title: "Manual", symbol: "book.pages") { model.caseViewer = nil; model.openManual(m, title: g.name) }
                    }
                    ViewerButton(symbol: "xmark", label: "Close (Esc)") { model.closeViewers() }
                }
                .padding(.horizontal, 24).padding(.top, 14)
                Spacer()
                HStack(spacing: 10) {
                    ViewerPill(title: "Front") { model.caseCommand(.front) }
                    ViewerPill(title: "Spine") { model.caseCommand(.spine) }
                    ViewerPill(title: "Back") { model.caseCommand(.back) }
                    ViewerButton(symbol: "minus.magnifyingglass", label: "Zoom out (−)", size: 36) { model.caseCommand(.zoom(1 / 1.25)) }
                    ViewerButton(symbol: "plus.magnifyingglass", label: "Zoom in (+)", size: 36) { model.caseCommand(.zoom(1.25)) }
                    ViewerPill(title: "Reset", symbol: "arrow.counterclockwise") { model.caseCommand(.reset) }
                }
                Text("Drag to turn it · pinch or scroll to zoom · double-click to stand it back up · right stick turns it too")
                    .font(.system(size: 12.5)).foregroundStyle(StageLook.faint).padding(.top, 10).padding(.bottom, 20)
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: manual

/// A game's manual: a PDF beside the game's files (a file named like "manual" first, else the only PDF there), or one added on the
/// game's page and kept in NXForge's own folder (manuals/<key>.pdf)
enum GameManual {
    nonisolated static var dir: URL { Settings.supportDir.appending(path: "manuals") }
    nonisolated static func added(_ key: String) -> URL { dir.appending(path: "\(key).pdf") }

    @MainActor static var found: [String: URL?] = [:]

    @MainActor static func find(_ g: StageGame) -> URL? {
        let _ = CoverStore.shared.revision
        if let f = found[g.coverKey] { return f }
        let fm = FileManager.default
        var out: URL?
        let mine = added(g.coverKey)
        if fm.fileExists(atPath: mine.path) { out = mine }
        else {
            var folders: [URL] = []
            if let p = g.game?.path {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: p, isDirectory: &isDir) { folders.append(isDir.boolValue ? URL(fileURLWithPath: p) : URL(fileURLWithPath: p).deletingLastPathComponent()) }
            }
            if let a = g.app { folders.append(URL(fileURLWithPath: a).deletingLastPathComponent()) }
            for f in folders {
                let pdfs = ((try? fm.contentsOfDirectory(at: f, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []).filter { $0.pathExtension.lowercased() == "pdf" }
                if let m = pdfs.first(where: { $0.lastPathComponent.localizedCaseInsensitiveContains("manual") }) { out = m; break }
                // a folder of one game's files may hold its manual under any name; a folder shared by games only one named "manual"
                if pdfs.count == 1, g.game?.shared != true { out = pdfs[0]; break }
            }
        }
        found[g.coverKey] = .some(out)
        return out
    }

    /// Keep a copy of a PDF as the game's manual
    @MainActor static func add(_ src: URL, for g: StageGame) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dst = added(g.coverKey)
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: src, to: dst)
        found[g.coverKey] = nil
        CoverStore.shared.revision += 1
    }

    @MainActor static func remove(for g: StageGame) {
        try? FileManager.default.trashItem(at: added(g.coverKey), resultingItemURL: nil)
        found[g.coverKey] = nil
        CoverStore.shared.revision += 1
    }

    @MainActor static func pick(for g: StageGame) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.pdf]
        p.allowsMultipleSelection = false
        p.message = "Choose the manual for \(g.name) (a PDF)"
        p.prompt = "Add Manual"
        guard p.runModal() == .OK, let u = p.url else { return }
        try? add(u, for: g)
    }
}

struct ManualViewer: View {
    let model: AppModel
    @Bindable var state: ManualState
    @State private var page = 1
    @State private var pages = 1

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()
            ManualPDFView(state: state, page: $page, pages: $pages)
                .padding(.top, 64).padding(.bottom, 70).padding(.horizontal, 84)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title).font(.system(size: 17, weight: .bold)).lineLimit(1)
                        Text("Manual · page \(page) of \(pages)").font(.system(size: 13)).foregroundStyle(StageLook.faint)
                    }
                    Spacer()
                    ViewerButton(symbol: "minus.magnifyingglass", label: "Zoom out (−)", size: 36) { state.send(.zoomOut) }
                    ViewerButton(symbol: "plus.magnifyingglass", label: "Zoom in (+)", size: 36) { state.send(.zoomIn) }
                    ViewerButton(symbol: "folder", label: "Show in Finder", size: 36) { NSWorkspace.shared.activateFileViewerSelecting([state.url]) }
                    ViewerButton(symbol: "xmark", label: "Close (Esc)") { model.closeViewers() }
                }
                .padding(.horizontal, 24).padding(.top, 14)
                Spacer()
                Text("← → or swipe to turn the page · pinch to zoom").font(.system(size: 12.5)).foregroundStyle(StageLook.faint).padding(.bottom, 22)
            }
            HStack {
                ViewerButton(symbol: "chevron.left", label: "Previous page (←)", size: 48) { state.send(.previous) }
                Spacer()
                ViewerButton(symbol: "chevron.right", label: "Next page (→)", size: 48) { state.send(.next) }
            }
            .padding(.horizontal, 20)
        }
        .foregroundStyle(.white)
    }
}

/// PDFKit's view of the manual: two pages side by side when the window is wide enough (a booklet's spread, its cover alone), a page
/// at a time otherwise
struct ManualPDFView: NSViewRepresentable {
    let state: ManualState
    @Binding var page: Int
    @Binding var pages: Int

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.backgroundColor = NSColor(white: 0.06, alpha: 1)
        v.autoScales = true
        v.displayMode = .singlePage
        v.displaysAsBook = true
        v.displaysPageBreaks = true
        v.pageShadowsEnabled = true
        v.document = PDFDocument(url: state.url)
        context.coordinator.view = v
        context.coordinator.binding = { p, n in page = p; pages = n }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.changed), name: .PDFViewPageChanged, object: v)
        context.coordinator.changed()
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        let wide = v.bounds.width > v.bounds.height * 1.15
        let mode: PDFDisplayMode = wide ? .twoUp : .singlePage
        if v.displayMode != mode { v.displayMode = mode; v.autoScales = true }
        guard let (id, a) = state.action, id != context.coordinator.last else { return }
        context.coordinator.last = id
        switch a {
        case .next: v.goToNextPage(nil)
        case .previous: v.goToPreviousPage(nil)
        case .zoomIn: v.zoomIn(nil)
        case .zoomOut: v.zoomOut(nil)
        case .fit: v.autoScales = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        weak var view: PDFView?
        var last: UUID?
        var binding: ((Int, Int) -> Void)?

        @objc func changed() {
            guard let v = view, let d = v.document else { return }
            let i = v.currentPage.map { d.index(for: $0) + 1 } ?? 1
            let n = d.pageCount
            DispatchQueue.main.async { self.binding?(i, n) }
        }
    }
}
