// The front end's game page (its box in 3D over the game's key art, Play, the preset it starts with, its screenshots, then its save,
// playtime and build) and the Play options
// panel that slides over it: presets, then the game's settings in the General, Graphics and Advanced groups of its own
// settings window.
import AppKit
import SwiftUI

/// The game page's line under its headline, in window coordinates (GameKeyArt's banner ends on it)
struct GameBannerBottom: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

struct StageGamePage: View {
    @Bindable var model: AppModel
    let game: StageGame
    /// More details under the media: the store's About
    @State private var aboutOpen = ProcessInfo.processInfo.environment["NXC_ABOUT"] != nil   // snapshot hook: opened
    @State private var lineY: CGFloat?
    @State private var scrollTop: CGFloat = 0

    var body: some View {
        let _ = model.revision
        let g = game
        let (_, record) = model.resolve(g.ref)
        GeometryReader { geo in
            let showCase = geo.size.width > 760
            let caseH = min(max(geo.size.height * 0.37, 250), 390)
            let gutter: CGFloat = geo.size.width > 1250 ? 56 : 40
            let inner = geo.size.width - gutter * 2
            let info = model.settings.downloadStoreInfo ? StoreInfoStore.shared.info(g.coverKey) : nil
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { model.gameDetail = nil } label: { Label(model.stageTab.rawValue, systemImage: "chevron.backward") }
                        .buttonStyle(StageButton(height: 36, glass: true))
                    Spacer()
                    Menu {
                        StageGameMenu(model: model, game: g)
                        if let record {
                            Divider()
                            Button("Rebuild") { model.showConverter(); model.rebuildAsked(record) }.disabled(model.run.running || !model.allOK)
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).accessibilityLabel("More")
                }
                .padding(.horizontal, gutter - 18).padding(.top, 6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: showCase ? 30 : 0) {
                            if showCase { boxColumn(g, height: caseH) }
                            GameHeroColumn(model: model, game: g, info: info, titleSize: geo.size.width > 1100 ? 50 : 42)
                                .frame(maxWidth: 640, alignment: .leading)
                                .padding(.top, showCase ? caseH * 0.12 : 10)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 10)
                        Rectangle().fill(.white.opacity(0.13)).frame(height: 1).padding(.top, 16)
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("gamePage")).maxY } action: { lineY = $0 }
                        // Media across the page (three tiles), then the store's one-line pitch with More details, which opens About
                        GameMedia(model: model, game: g, width: inner).padding(.top, 22)
                        if let info {
                            let pitch = GameAbout.pitch(info)
                            HStack(alignment: .center, spacing: 16) {
                                if let pitch { Text(pitch).font(.system(size: 17, weight: .medium)).lineLimit(1).truncationMode(.tail) }
                                Spacer(minLength: 0)
                                Button { withAnimation(.easeOut(duration: 0.2)) { aboutOpen.toggle() } } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).rotationEffect(.degrees(aboutOpen ? 90 : 0))
                                        Text(aboutOpen ? "Fewer details" : "More details")
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(CoverArt.tint(g)).brightness(0.35)
                                .help("The store's description and facts")
                            }
                            .padding(.top, 16)
                            if aboutOpen {
                                GameAbout(game: g, info: info, full: true).frame(maxWidth: 820, alignment: .leading)
                                    .padding(.top, 18).transition(.opacity)
                            }
                        }
                        Spacer(minLength: 0)
                        Rectangle().fill(.white.opacity(0.13)).frame(height: 1).padding(.top, 28)
                        infoRow(g, record).fixedSize(horizontal: false, vertical: true).padding(.vertical, 16)
                    }
                    .padding(.horizontal, gutter)
                    .padding(.bottom, 4)
                    .frame(minHeight: geo.size.height - 48)
                    .animation(.easeOut(duration: 0.2), value: aboutOpen)   // Save, Playtime and Build sit at the foot of the window
                    .coordinateSpace(.named("gamePage"))   // scrolls with the page, so the line's place in it stays put
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { scrollTop = $0 }
                .scrollIndicators(.never)
                // snapshot hook: NXC_SCROLL=1 opens the page scrolled to its end
                .defaultScrollAnchor(ProcessInfo.processInfo.environment["NXC_SCROLL"] == nil ? .top : .bottom)
            }
        }
        // where the line under the headline sits in the window, unscrolled: the key art behind the page reaches down to it
        .preference(key: GameBannerBottom.self, value: lineY.map { scrollTop + $0 })
        .task(id: g.coverKey + (model.settings.downloadStoreInfo ? "1" : "0")) {
            if model.settings.downloadStoreInfo { StoreInfoStore.shared.load(key: g.coverKey, titleID: g.titleID, name: g.name) }
        }
    }

    /// The game's box, small, still turning to a drag, with View box (the box viewer) and the manual under it
    func boxColumn(_ g: StageGame, height caseH: CGFloat) -> some View {
        let accent = CoverArt.tint(g)
        return GameCase(game: g, flipped: model.caseFlipped, glow: 0.16).frame(width: caseH * 0.66, height: caseH)
            .contextMenu { Button("View Box") { model.openCaseViewer(g) } }
            .help("Drag to turn it. View box (Y) shows it full screen.")
            .overlay(alignment: .bottom) {
                HStack(spacing: 16) {
                    if let m = GameManual.find(g) {
                        Button { model.openManual(m, title: g.name) } label: {
                            HStack(spacing: 6) { Image(systemName: "book.pages").font(.system(size: 13, weight: .semibold)); Text("Manual") }.contentShape(.rect)
                        }
                        .help("Read the manual")
                    }
                }
                .buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).foregroundStyle(accent).brightness(0.35)
                .fixedSize()
                .padding(.bottom, caseH * 0.12)
            }
            .padding(.top, -caseH * 0.04)
            .padding(.bottom, -caseH * 0.12)   // the floor's reflection may run under the line below
    }

    @ViewBuilder func infoRow(_ g: StageGame, _ record: BuildRecord?) -> some View {
        let manage = { model.showConverter(); model.page = .library; model.openGame(g.ref) }
        HStack(alignment: .center, spacing: 0) {
            if let app = g.app, let t = g.titleID {
                let loc = SaveSnapshots.location(app: app, titleID: t)
                let n = SaveSnapshots.list(loc).count
                info("cylinder.split.1x2.fill", "Save", SaveSnapshots.hasSave(loc) ? "Save on this Mac" : "No save yet",
                     model.backupStatus[t]?.text ?? (n > 0 ? "\(n) snapshot\(n == 1 ? "" : "s") kept" : "No snapshots yet"), action: manage)
                separator
            }
            if let app = g.app {
                if let r = FrameTimes.all(app: app, titleID: g.titleID).last, g.total == 0 {
                    info("waveform.path.ecg", "Last recording", String(format: "%.1f fps average", r.summary.fps),
                         r.summary.hitches == 0 ? "No hitches" : "\(r.summary.hitches) hitch\(r.summary.hitches == 1 ? "" : "es")", action: manage)
                } else {
                    info("clock", "Playtime", g.total > 0 ? Playtime.text(g.total) : "Not played yet",
                         g.last.map { "Last played \(relativeDay($0).lowercasedFirst)" } ?? "Counted while NXForge is open", action: manage)
                }
                separator
            }
            if let t = g.titleID {
                let c = CheatsSummary.of(app: g.app, titleID: t)
                info("wand.and.stars", "Cheats", c.value, c.note) { model.cheatsFor = g.ref }
                separator
            }
            if let record {
                let ok = !g.outdated
                info("hammer.fill", "Build", g.outdated ? "Older engine" : record.kept == true ? "Kept as it is" : "Up to date",
                     "NXForge \(record.engine.short) · built \(record.date.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? record.builtAt)",
                     seal: ok, action: manage)
            } else if g.app == nil {
                let st = model.status(g)
                info(st.symbol, "Build", st.text, st.detail, action: manage)
            }
        }
    }

    var separator: some View {
        Rectangle().fill(.white.opacity(0.13)).frame(width: 1, height: 66).padding(.horizontal, 18)
    }

    func info(_ symbol: String, _ title: String, _ value: String, _ note: String, seal: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).foregroundStyle(CoverArt.tint(game)).brightness(0.35)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(StageLook.soft)
                    HStack(spacing: 8) {
                        Text(value).font(.system(size: 19, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        if seal { Image(systemName: "checkmark.circle.fill").font(.system(size: 17)).foregroundStyle(.white, Color(red: 0.30, green: 0.75, blue: 0.40)) }
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(StageLook.soft)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(note + " · Manage in Converter")
        .accessibilityLabel("\(title): \(value). \(note)")
    }
}

/// The game page's headline beside the box: what it is, Play and Play options, and the preset it starts with
struct GameHeroColumn: View {
    let model: AppModel
    let game: StageGame
    /// the store's facts, for the two lines under the name
    var info: StoreInfo? = nil
    var titleSize: CGFloat = 66

    var body: some View {
        let g = game
        let list = g.app.map { LaunchSettings.load(app: $0) } ?? []
        let values = Dictionary(list.map { ($0.env, LaunchSettings.value($0, app: g.app ?? "")) }, uniquingKeysWith: { a, _ in a })
        let tint = CoverArt.tint(g)
        let playing = model.isPlaying(app: g.app ?? "")
        VStack(alignment: .leading, spacing: 0) {
            Text(g.name).font(.system(size: titleSize, weight: .heavy)).tracking(-1.4).lineLimit(2).minimumScaleFactor(0.55)
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ConsoleGlyph(console: g.console).frame(width: 22, height: 18)
                if playing {
                    Circle().fill(Color(red: 0.38, green: 0.65, blue: 0.98)).frame(width: 7, height: 7)
                }
                Text(facts.joined(separator: "  ·  ")).lineLimit(1)
            }
            .font(.system(size: 17, weight: .medium)).foregroundStyle(Color(white: 0.9))
            .shadow(color: .black.opacity(0.5), radius: 8)
            .padding(.top, 8)
            .help(game.version.map { "Version \($0)" } ?? "")
            if !storeLine.isEmpty {
                Text(storeLine).lineLimit(1)
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(Color(white: 0.9))
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .padding(.top, 6)
            }
            StageActions(model: model, game: g, playing: playing, tint: tint, height: 56, spacing: 12)
            .padding(.top, 20)
            if !list.isEmpty {
                let parts = [PlayOptions.current(settings: list, values: values).rawValue] + PlayOptions.summary(settings: list, values: values).prefix(1).map(\.value)
                Button { model.libraryFocus = g.id; model.openPlayOptions(g.ref) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .semibold)).foregroundStyle(StageLook.soft)
                        Text(parts.joined(separator: "  ·  ")).font(.system(size: 15.5, weight: .semibold)).lineLimit(1)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 8).contentShape(.rect)
                }
                .buttonStyle(.plain).padding(.leading, -8).padding(.top, 18)
                .help("What the game starts with: opens Play options")
            }
            AttentionRows(items: (model.attention[g.id] ?? []).filter { $0.kind != .update })   // the Build line says Older engine
                .padding(.top, 18)
        }
    }

    /// "Nintendo Switch · Inti Creates · 20 Mar 2019", or with no store facts, how it stands ("Not played yet")
    var facts: [String] {
        var out = [game.console == .switch2 ? "Nintendo Switch 2" : "Nintendo Switch"]
        let suspended = model.isSuspended(app: game.app ?? ""), playing = model.isPlaying(app: game.app ?? "")
        // a game not built yet says how it stands in the Build card below, not here
        if game.app == nil {}
        else if suspended { out.append("Paused · still running") }
        else if playing { out.append("Playing now") }
        if let info, info.publisher != nil || info.released != nil {
            out += [info.publisher, GameAbout.date(info.released)].compactMap { $0 }.filter { !$0.isEmpty }
        } else if game.app != nil && !suspended && !playing {
            out.append(game.last.map { "Played \(relativeDay($0).lowercasedFirst)" } ?? "Not played yet")
        }
        return out
    }

    /// "Action, Adventure  ·  1 player  ·  PEGI 7  ·  227 MB": the store's genres, players, rating and size, with the same dots as the line above
    var storeLine: String {
        guard let info else { return "" }
        let genres = info.genres.prefix(2).joined(separator: ", ")
        let size = info.size.map { $0.replacingOccurrences(of: ".0 ", with: " ") }
        return [genres.isEmpty ? nil : genres, info.players, info.rating, size].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }
}

/// The console's mark beside a game's name: the two Joy-Con, drawn (SF Symbols has no Switch)
struct ConsoleGlyph: View {
    let console: Console

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, gap = w * 0.08, half = (w - gap) / 2
            HStack(spacing: gap) {
                UnevenRoundedRectangle(topLeadingRadius: half * 0.75, bottomLeadingRadius: half * 0.75, bottomTrailingRadius: 1.5, topTrailingRadius: 1.5)
                    .fill(.white.opacity(0.92))
                    .overlay(Circle().fill(.black.opacity(0.75)).frame(width: half * 0.38).offset(y: -h * 0.18))
                    .frame(width: half, height: h)
                UnevenRoundedRectangle(topLeadingRadius: 1.5, bottomLeadingRadius: 1.5, bottomTrailingRadius: half * 0.75, topTrailingRadius: half * 0.75)
                    .strokeBorder(.white.opacity(0.92), lineWidth: max(1.4, w * 0.075))
                    .overlay(Circle().fill(.white.opacity(0.92)).frame(width: half * 0.38).offset(y: h * 0.12))
                    .frame(width: half, height: h)
            }
        }
        .accessibilityHidden(true)
    }
}

struct PlayOptionsPanel: View {
    let model: AppModel
    @Bindable var state: PlayOptionsState
    @Environment(\.accessibilityReduceTransparency) private var solid

    var body: some View {
        let rows = state.rows
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Play options").font(.system(size: 26, weight: .heavy)).tracking(-0.5)
                    Text("\(state.name) · kept for this game").font(.system(size: 13.5)).foregroundStyle(StageLook.soft).lineLimit(1)
                }
                Spacer()
                Button { model.closePlayOptions() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 32, height: 32)
                        .background(.white.opacity(0.10), in: .circle).contentShape(.circle)
                }
                .buttonStyle(.plain).help("Done: keeps these options").accessibilityLabel("Done")
            }
            HStack(spacing: 8) {
                ForEach(PlayPreset.allCases) { p in
                    let on = state.preset == p
                    Button { state.choose(p) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: symbol(p)).font(.system(size: 15, weight: .semibold)).frame(height: 20)
                                .foregroundStyle(on ? Color.black : Color.white.opacity(p == .custom ? 0.5 : 0.9))
                            Text(p.rawValue).font(.system(size: 14, weight: .bold))
                            Text(p.note).font(.system(size: 11)).foregroundStyle(on ? Color(white: 0.25) : StageLook.faint)
                                .lineLimit(3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(11).frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
                        .foregroundStyle(on ? Color.black : Color.white)
                        .background(on ? AnyShapeStyle(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(StageLook.card), in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? AnyShapeStyle(Color.clear) : AnyShapeStyle(StageLook.edge), lineWidth: 1))
                        .shadow(color: .white.opacity(on ? 0.22 : 0), radius: 14, y: 4)
                        .contentShape(.rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain).disabled(p == .custom)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if state.tabs.count > 1 {
                HStack(spacing: 0) {
                    ForEach(state.tabs) { t in
                        Button { state.tab = t; state.focus = 0 } label: {
                            Text(t.rawValue).font(.system(size: 13.5, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 32)
                                .background(state.tab == t ? Color.white.opacity(0.20) : Color.clear, in: .rect(cornerRadius: 9)).contentShape(.rect)
                        }
                        .buttonStyle(.plain).accessibilityAddTraits(state.tab == t ? .isSelected : [])
                    }
                }
                .padding(4).background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, s in
                            row(s, focused: i == state.focus).id(s.env)
                            if i + 1 < rows.count { Rectangle().fill(.white.opacity(0.10)).frame(height: 1) }
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: state.focus) { _, f in if rows.indices.contains(f) { proxy.scrollTo(rows[f].env) } }
            }
            .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button { model.playWithOptions(save: true) } label: { Label("Play", systemImage: "play.fill") }
                        .buttonStyle(StageButton(primary: true, height: 50, glow: .white, fill: true))
                    Button("Play once, don't keep") { model.playWithOptions(save: false) }.buttonStyle(StageButton(height: 50))
                        .disabled(state.changed.isEmpty)
                        .help("Starts the game with these options for this run only. The options kept for the game stay as they were.")
                }
                HStack {
                    Text("Play keeps these for next time. The game opens straight in.").font(.system(size: 12)).foregroundStyle(StageLook.faint)
                    Spacer()
                    Button("Reset to Tested Defaults") { state.reset() }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).underline()
                        .foregroundStyle(StageLook.soft).disabled(state.allDefault)
                }
            }
        }
        .padding(24)
        .frame(width: 600)
        .frame(maxHeight: .infinity)
        .background(StageLook.panel.opacity(solid ? 1 : 0.78), in: .rect(cornerRadius: 28))
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.55), radius: 50, y: 24)
    }

    func symbol(_ p: PlayPreset) -> String {
        switch p {
        case .battery: "leaf.fill"
        case .balanced: "circle.lefthalf.filled"
        case .quality: "sparkles"
        case .custom: "slider.horizontal.3"
        }
    }

    @ViewBuilder func row(_ s: LaunchSetting, focused: Bool) -> some View {
        let v = state.value(s)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.label).font(.system(size: 14.5, weight: .medium))
                if !s.note.isEmpty { Text(s.note).font(.system(size: 12)).foregroundStyle(StageLook.faint).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            switch s.kind {
            case "choice":
                let opts = s.options ?? []
                if opts.count <= 3, opts.map({ ($0.count > 1 ? $0[1] : $0[0]).count }).reduce(0, +) <= 24 {
                    HStack(spacing: 0) {
                        ForEach(opts, id: \.self) { o in
                            let on = o.first == v
                            Button { state.set(s, o[0]) } label: {
                                Text(o.count > 1 ? o[1] : o[0]).font(.system(size: 13, weight: on ? .bold : .semibold)).padding(.horizontal, 13).frame(height: 28)
                                    .foregroundStyle(on ? Color.black : Color(white: 0.85))
                                    .background(on ? Color.white : Color.clear, in: .rect(cornerRadius: 8)).contentShape(.rect)
                            }
                            .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(3).background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
                } else {
                    Picker(s.label, selection: Binding(get: { state.value(s) }, set: { state.set(s, $0) })) {
                        ForEach(opts, id: \.self) { o in Text(o.count > 1 ? o[1] : o[0]).tag(o[0]) }
                    }
                    .labelsHidden().frame(width: 200)
                }
            case "toggle":
                Toggle(s.label, isOn: Binding(get: { state.value(s) == s.onValue }, set: { state.set(s, $0 ? s.onValue : s.offValue) }))
                    .toggleStyle(.switch).labelsHidden().tint(.green)
            case "range":
                Text(PlayOptions.valueText(s, v)).font(.system(size: 13).monospacedDigit()).foregroundStyle(StageLook.soft).frame(width: 52, alignment: .trailing)
                Slider(value: Binding(get: { Double(state.value(s)) ?? 0 }, set: { state.set(s, PlayOptions.format(s, $0)) }),
                       in: (s.min ?? 0)...max(s.max ?? 1, (s.min ?? 0) + 0.0001), step: s.step ?? 0.05)
                    .frame(width: 170).tint(.white).accessibilityLabel(s.label)
            default:
                Text(v).foregroundStyle(StageLook.soft)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 10)
        .background(focused ? Color.white.opacity(0.07) : Color.clear, in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .onTapGesture { if let i = state.rows.firstIndex(of: s) { state.focus = i } }
    }
}
