// The window frame and the pieces every page uses: sidebar, toolbar, cards, status dots, path fields.
import AppKit
import SwiftUI

let helpURL = URL(string: "https://github.com/gnosticgeek/nxforge/blob/main/app/README.md")!

struct RootView: View {
    @Bindable var model: AppModel
    @State private var width: CGFloat = 1200

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.page }, set: { if let p = $0 { model.page = p } })) {
                ForEach(Page.allCases) { p in
                    Label(p.rawValue, systemImage: p.symbol).font(.system(size: 15)).padding(.vertical, 3).tag(p)
                }
            }
            .safeAreaInset(edge: .top) { SidebarBrand() }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
            .safeAreaInset(edge: .bottom) { ToolchainFooter(model: model) }
        } detail: {
            Group {
                switch model.page {
                case .convert: ScrollView { ConvertPage(model: model, wide: width > 860).padding(20) }
                case .library: LibraryPage(model: model)
                case .builds: BuildsPage(model: model)
                case .storage: StoragePage(model: model)
                case .toolchain: ScrollView { ToolchainPage(model: model).padding(20) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // the page sits on the navy; Convert's banner sits behind its heading, up under the toolbar
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Theme.background
                    if model.page == .convert || model.page == .storage { HeroBanner(scene: .dish).frame(height: 230) }
                    if model.page == .toolchain { HeroBanner(scene: .peaks).frame(height: 230) }
                }
                .ignoresSafeArea()
            }
            // pages with their own banner heading drop the window title over it
            .toolbar(removing: model.page.hasHero ? .title : nil)
            .toolbarBackgroundVisibility(model.page.hasHero ? .hidden : .automatic, for: .windowToolbar)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // the window title names the page, as Mac apps do; the subtitle names the game being converted
            .navigationTitle(model.page.rawValue)
            .navigationSubtitle(model.page == .convert ? model.game?.name ?? "" : "")
            // a game folder (or a file in it) dropped anywhere on the window becomes the game to convert
            .dropDestination(for: URL.self) { urls, _ in
                guard !model.run.running, !urls.isEmpty else { return false }
                model.openDropped(urls)
                return true
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button { NSWorkspace.shared.open(helpURL) } label: { Image(systemName: "questionmark") }.help("NXForge Converter Help")
                }
            }
        }
    }
}

/// The app's mark and name over the sidebar.
struct SidebarBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("NXForge").font(.title3.weight(.bold))
                Text("Game Conversion Toolkit").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }
}

/// The page's one-line description; its trailing controls (the page's actions) go in the window toolbar.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Text(subtitle).foregroundStyle(.secondary)
            .toolbar { ToolbarItemGroup(placement: .primaryAction) { trailing } }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
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
                Image(systemName: symbol).foregroundStyle(.blue)
                Text(value ?? "Not chosen").foregroundStyle(value == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(.background.opacity(0.5), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .help(value ?? "")
            Button(button, action: action).buttonStyle(.glass)
        }
    }
}

struct ToolchainFooter: View {
    let model: AppModel

    var body: some View {
        Button { model.page = .toolchain } label: {
            HStack(spacing: 10) {
                if model.checking { ProgressView().controlSize(.small).frame(width: 22) } else { StatusIcon(ok: model.allOK, size: 22) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.checking ? "Checking toolchain…" : model.allOK ? "Toolchain ready" : "Toolchain incomplete").font(.headline).lineLimit(1)
                    Text("\(model.passed) of \(model.checks?.count ?? 0) checks passed").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .padding(12)
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
