// The window frame and the pieces every page uses: the page row, cards, status dots, path fields.
import AppKit
import SwiftUI

let helpURL = URL(string: "https://github.com/gnosticgeek/nxforge/blob/main/app/README.md")!

/// The window: the front end (Stage.swift), or the converter's pages behind its Converter tab.
struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
        ZStack {
            // the games and the converter are one window on one stage: the same top bar, the same light
            if model.standby { StandbyView(model: model).transition(.opacity) }
            else if model.theatre { TheatreView(model: model).transition(.opacity) }
            else if model.frontEnd { StageView(model: model).transition(.opacity) } else { ConverterRoot(model: model).transition(.opacity) }
            if let tv = model.theatreOffer, !model.theatre, !model.standby { TheatreOffer(model: model, tv: tv).transition(.opacity) }
            if model.stageSettings {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { model.stageSettings = false }
                StageSettings(model: model, openConverterSettings: { openSettings() })
                    // never taller than the window: the rows scroll inside it
                    .padding(.top, 44).padding(.bottom, 28)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .foregroundStyle(.white)
                    .onExitCommand { model.stageSettings = false }
            }
        }
            // a running build, under every page (BuildStrip.swift)
            if model.showsBuildStrip { BuildStrip(model: model).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .background(StageLook.background)
        .animation(.easeInOut(duration: 0.25), value: model.showsBuildStrip)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: model.frontEnd)
        .animation(.easeInOut(duration: 0.35), value: model.theatre)
        .animation(.easeInOut(duration: 0.25), value: model.theatreOffer)
        .animation(.spring(duration: 0.3), value: model.stageSettings)
        // a note for work that ended in the background, over the foot of the window (idea 7)
        .overlay(alignment: .bottom) {
            if let b = model.banner {
                BannerView(model: model, banner: b).id(b.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: model.banner?.id)
        // what the session that just ended came to (PlayExtras)
        .overlay(alignment: .bottomTrailing) {
            if let r = model.recap, !model.standby {
                RecapCard(model: model, recap: r).id(r.id).padding(24)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: model.recap?.id)
        .sheet(isPresented: $model.showControllerTest) { ControllerTestSheet(model: model) }
        .sheet(isPresented: $model.showLeftovers) { LeftoversSheet(model: model) }
        .sheet(item: $model.whatsNew) { WhatsNewSheet(model: model, news: $0) }
        .sheet(item: $model.updateOffer) { UpdateOfferSheet(model: model, offer: $0) }
        .sheet(item: $model.preview) { PreviewSheet(model: model, ref: $0) }
        .sheet(item: $model.cheatsFor) { CheatsSheet(model: model, ref: $0) }
        .sheet(item: $model.enhancementsFor) { EnhancementsSheet(model: model, ref: $0) }
        .sheet(isPresented: $model.commandPalette) { CommandPalette(model: model) }
        .task { ControllerNav.shared.start(model); TheatreWatch.shared.start(model) }
    }
}

/// The converter's pages, on the front end's stage: its top bar, a row of the pages under it, then the page.
struct ConverterRoot: View {
    @Bindable var model: AppModel
    @State private var width: CGFloat = 1200

    /// The light is the game's whose page is open, else the one the front end was on, so changing tabs keeps the room as it was.
    var lit: StageGame? {
        // Convert: the game being converted, so the room has its colour as the card has its art
        if model.page == .convert, model.gameDetail == nil, let g = model.convertStageGame { return g }
        let games = model.stageGames()
        return model.gameDetail.flatMap { r in games.first { $0.isRef(r) } } ?? model.stageFocus(model.stageShown(games))
    }

    var body: some View {
        ZStack {
            let g = lit
            StageBackdrop(tint: g.map { CoverArt.tint($0) } ?? Color(red: 0.25, green: 0.35, blue: 0.75), art: g.flatMap { CoverArt.ambient($0) }, artKey: g?.id ?? "", strength: 0.55)
            VStack(spacing: 0) {
                StageTopBar(model: model)
                ConverterNav(model: model)
                Group {
                    if let r = model.gameDetail, model.page == .library || model.page == .builds {
                        GamePage(model: model, ref: r, wide: width > 860)
                    } else {
                        switch model.page {
                        case .convert: ScrollView { ConvertPage(model: model, wide: width > 860).pagePadding() }
                        case .library: LibraryPage(model: model)
                        case .builds: BuildsPage(model: model)
                        case .saves: SavesPage(model: model)
                        case .storage: StoragePage(model: model)
                        case .health: ScrollView { HealthPage(model: model).pagePadding() }
                        case .toolchain: ScrollView { ToolchainPage(model: model).pagePadding() }
                        case .updates: ScrollView { UpdatesPage(model: model).pagePadding() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle("NXForge")
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // a game folder (or a file in it) dropped anywhere on the window becomes the game to convert
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.run.running, !urls.isEmpty else { return false }
            model.openDropped(urls)
            return true
        }
        .onChange(of: model.page) { model.gameDetail = nil }
        // Health's badge: its problems and warnings, read again whenever something on disk may have changed
        .task(id: "\(model.revision)|\(model.lastDataBackup?.timeIntervalSince1970 ?? 0)|\(model.dataBackupFailed)") {
            model.noteHealth(model.healthFindings())
        }
    }
}

extension View {
    /// A page's margins: the top bar's at the sides.
    func pagePadding() -> some View { padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 28) }
}

/// The converter's pages as a row of text tabs under the top bar, centred, the open one underlined; Health's count is red or
/// amber by its worst finding and names them on hover, Toolchain carries its state as a dot, and a waiting update sits at the right.
struct ConverterNav: View {
    @Bindable var model: AppModel
    @Namespace private var line

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            ViewThatFits(in: .horizontal) {
                pages
                ScrollView(.horizontal, showsIndicators: false) { pages }
            }
            .layoutPriority(1)
            HStack { Spacer(minLength: 0); UpdateCapsule(model: model) }.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 10)
    }

    var pages: some View {
        HStack(spacing: 4) {
            ForEach(Page.allCases) { p in
                let on = model.page == p
                let count = p == .updates ? (model.engineUpdate == nil ? 0 : 1) + (model.converterUpdate == nil ? 0 : 1) : p == .health ? model.healthBadge : 0
                Button { if on { model.gameDetail = nil } else { model.page = p } } label: {
                    VStack(spacing: 7) {
                        HStack(spacing: 7) {
                            Text(p.title)
                            if p == .toolchain, model.checks != nil, !model.allOK || model.checking {
                                Circle().fill(model.checking ? Color(white: 0.6) : Color(red: 0.98, green: 0.75, blue: 0.14)).frame(width: 7, height: 7)
                            }
                            if count > 0 {
                                Text("\(count)").font(.system(size: 11, weight: .bold)).frame(minWidth: 18, minHeight: 18)
                                    .foregroundStyle(.black).background(badgeColor(p), in: .circle)
                            }
                        }
                        .font(.system(size: 15, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.white : Color(white: 0.78))
                        ZStack {
                            Capsule().fill(.clear).frame(height: 3)
                            if on { Capsule().fill(convertAccent).frame(height: 3).matchedGeometryEffect(id: "line", in: line) }
                        }
                    }
                    .padding(.horizontal, 10).padding(.top, 6)
                    .fixedSize()
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(hint(p))
                .accessibilityLabel(count > 0 ? "\(p.title), \(count) waiting" : p.title)
                .accessibilityHint(p == .health ? model.healthHint : "")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(.spring(duration: 0.3), value: model.page)
        .fixedSize()
    }

    /// Health's badge: red for a problem, amber for warnings only; the others white
    func badgeColor(_ p: Page) -> Color {
        guard p == .health else { return Color.white.opacity(0.92) }
        return model.healthWorst == .problem ? Color(red: 1, green: 0.42, blue: 0.38) : Color(red: 0.98, green: 0.75, blue: 0.14)
    }

    func hint(_ p: Page) -> String {
        switch p {
        case .health: return model.healthHint.isEmpty ? "Nothing needs attention" : model.healthHint
        case .toolchain: return model.checking ? "Checking the toolchain…" : "\(model.passed) of \(model.checks?.count ?? 0) checks passed. Converter \(CONVERTER_VERSION)."
        default: return ""
        }
    }
}

/// A green, red, grey or blue dot with its word: the status column of every table.
struct StatusDot: View {
    let color: Color
    var text: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 10, height: 10)
            if let text { Text(text).foregroundStyle(color == .gray ? Color.secondary : color) }
        }
    }
}

/// A filled check, cross or dash: the larger summary marks.
struct StatusIcon: View {
    /// true = tick, false = cross, nil = not run / optional
    let ok: Bool?
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: ok == true ? "checkmark.circle.fill" : ok == false ? "xmark.circle.fill" : "minus.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, ok == true ? Color.green : ok == false ? Color.red : Color.gray)
            .font(.system(size: size))
            .accessibilityLabel(ok == true ? "Passed" : ok == false ? "Failed" : "Not run")
    }
}

struct Card<Content: View>: View {
    var title = ""
    var subtitle = ""
    /// the step this card is, in a blue circle before its title
    var number: Int? = nil
    var padding: CGFloat = 18
    /// Fill the height offered (for cards side by side in a row of equal heights)
    var fillHeight = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 9) {
                        if let number { NumberBadge(n: number) }
                        Text(title).font(number == nil ? .headline : .title3.weight(.bold))
                    }
                    if !subtitle.isEmpty { Text(subtitle).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke))
    }
}

/// A bordered inner table: rows separated by hairlines.
struct InsetTable<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(.background.opacity(0.35), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.8)))
            .clipShape(.rect(cornerRadius: 10))
    }
}

/// A path shown like a text field, with its icon and a Change button.
struct PathField: View {
    let label: String
    var labelWidth: CGFloat = 110
    let symbol: String
    let value: String?
    var button = "Change…"
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(label).frame(width: labelWidth, alignment: .leading)
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(StageLook.soft)
                Text(value ?? "Not chosen").foregroundStyle(value == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(.background.opacity(0.5), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .help(value ?? "")
            Button(button, action: action).buttonStyle(.stage)
        }
    }
}

/// An app's own icon, as Finder shows it.
struct AppIcon: View {
    let path: String
    var size: CGFloat = 96

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// The game's icon from its extracted control data, or a placeholder.
struct GameIcon: View {
    let url: URL?
    var size: CGFloat = 120

    var body: some View {
        Group {
            if let url, let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().interpolation(.high)
            } else {
                ZStack { Color.gray.opacity(0.25); Image(systemName: "gamecontroller").font(.system(size: size * 0.35)).foregroundStyle(.secondary) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.2))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([path.url]) }

func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
