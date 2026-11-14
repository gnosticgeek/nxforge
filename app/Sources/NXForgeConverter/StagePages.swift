// The front end's game page (its box in 3D, Play, what it plays with, its save, last session and build) and the Play options
// panel that slides over it: presets, then the game's settings in the General, Graphics and Advanced groups of its own
// settings window.
import AppKit
import SwiftUI

struct StageGamePage: View {
    @Bindable var model: AppModel
    let game: StageGame

    var body: some View {
        let _ = model.revision
        let g = game
        let (_, record) = model.resolve(g.ref)
        GeometryReader { geo in
            let wide = geo.size.width > 900
            let caseH = min(max(geo.size.height - 110, 240), 680)
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
                .padding(.horizontal, 40).padding(.top, 6)
                HStack(alignment: .center, spacing: wide ? 50 : 20) {
                    if wide {
                        GameCase(game: g, flipped: model.caseFlipped).frame(width: caseH * 0.74, height: caseH)
                            .overlay(alignment: .bottom) {
                                Button { model.caseFlipped.toggle() } label: {
                                    Label(model.caseFlipped ? "Show the front" : "Turn over", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 12.5, weight: .semibold)).padding(.horizontal, 14).frame(height: 30)
                                        .glassEffect(.regular.interactive(), in: .capsule).contentShape(.capsule)
                                }
                                .buttonStyle(.plain).padding(.bottom, caseH * 0.045)
                                .help("Drag the box to turn it, or use a controller's right stick")
                            }
                        .padding(.leading, geo.size.width > 1250 ? 60 : 10)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            StageHero(model: model, game: g, first: false, titleSize: geo.size.width > 1100 ? 60 : 42, showDetails: false)
                            if let app = g.app { PlaysWith(model: model, game: g, app: app) }
                            cards(g, record)
                        }
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(.vertical, 20)
                    }
                    .scrollIndicators(.never)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 40)
                .frame(maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder func cards(_ g: StageGame, _ record: BuildRecord?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let app = g.app, let t = g.titleID {
                let loc = SaveSnapshots.location(app: app, titleID: t)
                let n = SaveSnapshots.list(loc).count
                card("externaldrive.fill", "SAVE", SaveSnapshots.hasSave(loc) ? "Save on this Mac" : "No save yet",
                     model.backupStatus[t]?.text ?? (n > 0 ? "\(n) snapshot\(n == 1 ? "" : "s") kept" : "No snapshots yet"))
            }
            if let app = g.app {
                if let r = FrameTimes.all(app: app, titleID: g.titleID).last {
                    card("waveform.path.ecg", "LAST RECORDING", String(format: "%.1f fps average", r.summary.fps), r.summary.hitches == 0 ? "No hitches" : "\(r.summary.hitches) hitch\(r.summary.hitches == 1 ? "" : "es")")
                } else {
                    card("clock.fill", "PLAYTIME", g.total > 0 ? Playtime.text(g.total) : "Not played yet", g.last.map { "Last played \(relativeDay($0).lowercasedFirst)" } ?? "Counted while NXForge is open")
                }
            }
            if let record {
                card("hammer.fill", "BUILD", g.outdated ? "Update ready" : record.kept == true ? "Kept as it is" : "Up to date",
                     "NXForge \(record.engine.short) · built \(record.date.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? record.builtAt)")
            } else if g.app == nil {
                card("hammer.fill", "BUILD", "Not built yet", "Build turns the game's files into a Mac app.")
            }
        }
    }

    func card(_ symbol: String, _ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(CoverArt.tint(game)).brightness(0.25)
                Text(title).font(.system(size: 10.5, weight: .bold)).fontWidth(.expanded).kerning(1.4).foregroundStyle(StageLook.soft)
            }
            Text(value).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.system(size: 12.5)).foregroundStyle(StageLook.faint).lineLimit(2)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(StageLook.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(StageLook.edge, lineWidth: 1))
    }
}

/// What the game starts with, at a glance; a click opens Play options.
struct PlaysWith: View {
    let model: AppModel
    let game: StageGame
    let app: String

    var body: some View {
        let list = LaunchSettings.load(app: app)
        let values = Dictionary(list.map { ($0.env, LaunchSettings.value($0, app: app)) }, uniquingKeysWith: { a, _ in a })
        let summary = PlayOptions.summary(settings: list, values: values)
        if !summary.isEmpty {
            Button { model.openPlayOptions(game.ref) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 7) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .bold)).foregroundStyle(CoverArt.tint(game)).brightness(0.25)
                        Text("PLAYS WITH").font(.system(size: 10.5, weight: .bold)).fontWidth(.expanded).kerning(1.4).foregroundStyle(StageLook.soft)
                        Spacer()
                        Text("\(PlayOptions.current(settings: list, values: values).rawValue) preset").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(StageLook.soft)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(StageLook.faint)
                    }
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(summary.enumerated()), id: \.offset) { i, s in
                            if i > 0 { Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 44).padding(.trailing, 16) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.value).font(.system(size: 24, weight: .heavy)).tracking(-0.4).lineLimit(1).minimumScaleFactor(0.6)
                                Text(s.label).font(.system(size: 12.5)).foregroundStyle(StageLook.faint).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(18)
                .background(StageLook.card, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(StageLook.edge, lineWidth: 1))
                .contentShape(.rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play options")
        }
    }
}

struct PlayOptionsPanel: View {
    let model: AppModel
    @Bindable var state: PlayOptionsState

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
                    Button { model.playWithOptions(save: true) } label: { Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(StageButton(primary: true, height: 50, glow: .white))
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
        .background(StageLook.panel.opacity(0.78), in: .rect(cornerRadius: 28))
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
