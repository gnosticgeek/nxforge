// The window frame and the pieces every page uses: the page row, cards, status dots, path fields.
import AppKit
import SwiftUI

let helpURL = URL(string: "https://github.com/gnosticgeek/nxforge/blob/main/app/README.md")!

/// The window: the front end (Stage.swift), or the converter's pages behind its Converter tab.
struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            // the games and the converter are one window on one stage: the same top bar, the same light
            if model.frontEnd { StageView(model: model).transition(.opacity) } else { ConverterRoot(model: model).transition(.opacity) }
            if model.stageSettings {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { model.stageSettings = false }
                StageSettings(model: model, openConverterSettings: { openSettings() }).transition(.scale(scale: 0.96).combined(with: .opacity))
                    .foregroundStyle(.white)
                    .onExitCommand { model.stageSettings = false }
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: model.frontEnd)
        .animation(.spring(duration: 0.3), value: model.stageSettings)
        // a note for work that ended in the background, over the foot of the window (idea 7)
        .overlay(alignment: .bottom) {
            if let b = model.banner {
                BannerView(model: model, banner: b).id(b.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: model.banner?.id)
        .sheet(item: $model.whatsNew) { WhatsNewSheet(model: model, news: $0) }
        .sheet(item: $model.updateOffer) { UpdateOfferSheet(model: model, offer: $0) }
        .sheet(item: $model.preview) { PreviewSheet(model: model, ref: $0) }
        .sheet(isPresented: $model.commandPalette) { CommandPalette(model: model) }
        .task { ControllerNav.shared.start(model) }
    }
}

/// The converter's pages, on the front end's stage: its top bar, a row of the pages under it, then the page.
struct ConverterRoot: View {
    @Bindable var model: AppModel
    @State private var width: CGFloat = 1200

    /// The light is the game's whose page is open, else the one the front end was on, so changing tabs keeps the room as it was.
    var tint: Color {
        let games = model.stageGames()
        let g = model.gameDetail.flatMap { r in games.first { $0.isRef(r) } } ?? model.stageFocus(model.stageShown(games))
        return g.map { CoverArt.tint($0) } ?? Color(red: 0.25, green: 0.35, blue: 0.75)
    }

    var body: some View {
        ZStack {
            StageBackdrop(tint: tint, strength: 0.55)
            VStack(spacing: 0) {
                if !model.couchMode {
                    StageTopBar(model: model)
                    ConverterNav(model: model)
                }
                Group {
                    if let r = model.gameDetail, model.page == .library || model.page == .builds {
                        GamePage(model: model, ref: r, wide: width > 860)
                    } else {
                        switch model.page {
                        case .convert: ScrollView { ConvertPage(model: model, wide: width > 860).pagePadding() }
                        case .library: LibraryPage(model: model)
                        case .builds: BuildsPage(model: model)
                        case .storage: StoragePage(model: model)
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
    }
}

extension View {
    /// A page's margins: the top bar's at the sides.
    func pagePadding() -> some View { padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 28) }
}

/// The converter's pages as a row of capsules (the front end's filter chips), with the toolchain's state and a waiting
/// update at the right.
struct ConverterNav: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                pages
                ScrollView(.horizontal, showsIndicators: false) { pages }
            }
            Spacer(minLength: 8)
            UpdateCapsule(model: model)
            toolchain
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 2).padding(.bottom, 12)
    }

    var pages: some View {
        HStack(spacing: 8) {
            ForEach(Page.allCases) { p in
                let on = model.page == p
                let updates = p == .updates ? (model.engineUpdate == nil ? 0 : 1) + (model.converterUpdate == nil ? 0 : 1) : 0
                Button { if on { model.gameDetail = nil } else { model.page = p } } label: {
                    HStack(spacing: 6) {
                        Text(p.title)
                        if updates > 0 {
                            Text("\(updates)").font(.system(size: 11, weight: .bold)).frame(minWidth: 17, minHeight: 17)
                                .foregroundStyle(on ? Color.white : Color.black)
                                .background(on ? Color.black.opacity(0.8) : Color.white.opacity(0.9), in: .circle)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).frame(height: 32)
                    .foregroundStyle(on ? Color.black : Color(white: 0.9))
                    .background(on ? Color.white.opacity(0.92) : Color.white.opacity(0.07), in: .capsule)
                    .overlay(Capsule().strokeBorder(.white.opacity(on ? 0 : 0.16)))
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(updates > 0 ? "\(p.title), \(updates) waiting" : p.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .fixedSize()
    }

    /// Ready or not: it opens the Toolchain page
    var toolchain: some View {
        Button { model.page = .toolchain } label: {
            HStack(spacing: 7) {
                if model.checking { ProgressView().controlSize(.mini) }
                else { Circle().fill(model.allOK ? Color(red: 0.29, green: 0.87, blue: 0.50) : Color(red: 0.98, green: 0.75, blue: 0.14)).frame(width: 7, height: 7) }
                Text(model.checking ? "Checking the toolchain…" : model.allOK ? "Toolchain ready" : "Toolchain incomplete · \(model.passed) of \(model.checks?.count ?? 0)")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(StageLook.soft).lineLimit(1)
            }
            .padding(.horizontal, 4).frame(height: 32).contentShape(.rect)
        }
        .buttonStyle(.plain).fixedSize()
        .help("\(model.passed) of \(model.checks?.count ?? 0) checks passed. Converter \(CONVERTER_VERSION).")
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
