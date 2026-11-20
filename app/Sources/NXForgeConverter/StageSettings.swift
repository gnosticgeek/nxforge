// Settings: one panel for the whole app, over whatever the window shows (the front end, the converter or Theatre). The
// sections are listed down its left side and the chosen one's rows fill the right, so a section is read without scrolling
// on most windows; the find field looks through every section at once. Before Converter 0.22.3 the panel was a single narrow
// column with the front end's options only, and the converter's lived in a Settings window of their own (⌘,).
import AppKit
import GameController
import SwiftUI

/// The panel's sections, in the order of its list
enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", playing = "Playing", library = "Library", artwork = "Artwork", theatre = "Theatre"
    case saves = "Saves", building = "Building", updates = "Updates", storage = "Storage"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .playing: "play.circle"
        case .library: "square.grid.2x2"
        case .artwork: "photo.on.rectangle"
        case .theatre: "tv"
        case .saves: "icloud"
        case .building: "hammer"
        case .updates: "arrow.down.circle"
        case .storage: "internaldrive"
        }
    }
    /// one line under the section's name
    var blurb: String {
        switch self {
        case .general: "How NXForge opens, and what it does around a game."
        case .playing: "What happens when you press Play."
        case .library: "Where your games are, and how they are shown."
        case .artwork: "Covers, wide art and store details, and where they are kept."
        case .theatre: "Your games full screen on a TV, for the sofa and a controller."
        case .saves: "Cloud saves, snapshots and backups for every game."
        case .building: "The keys file, and how a game becomes a Mac app."
        case .updates: "This version of NXForge, and how it stays current."
        case .storage: "What NXForge keeps on this Mac."
        }
    }
}

/// A Settings row a controller can stand on, in the order the rows are shown: up and down walk them (and so the sections),
/// left and right change the row, A flips a switch (AppModel.stepSetting).
enum StageSettingRow: Int, CaseIterable {
    case startIn, returnToLibrary, sessionRecap, lightWhilePlaying
    case straightPlay, firstPlayOptions, batteryPreset, localShaders
    case folderCheck, squareCovers, groupByConsole
    case downloadCovers, downloadHeroes, downloadStoreInfo, mediaInGameFolder
    case theatreTheme, theatreOnTV, theatreEdges, theatreSaver, theatreVolume, theatreSounds, theatreMusic, theatreTimeOfDay
    case cloudSaves, snapshotAfterPlay, saveBackupPush
    case notify, openAfterBuild, keepBackups, reuseCache
    case autoUpdate

    var section: SettingsSection {
        switch self {
        case .startIn, .returnToLibrary, .sessionRecap, .lightWhilePlaying: .general
        case .straightPlay, .firstPlayOptions, .batteryPreset, .localShaders: .playing
        case .folderCheck, .squareCovers, .groupByConsole: .library
        case .downloadCovers, .downloadHeroes, .downloadStoreInfo, .mediaInGameFolder: .artwork
        case .theatreTheme, .theatreOnTV, .theatreEdges, .theatreSaver, .theatreVolume, .theatreSounds, .theatreMusic, .theatreTimeOfDay: .theatre
        case .cloudSaves, .snapshotAfterPlay, .saveBackupPush: .saves
        case .notify, .openAfterBuild, .keepBackups, .reuseCache: .building
        case .autoUpdate: .updates
        }
    }
}

/// One row: its name, the note under it (the find field looks in both), its control, and anything shown under the row
struct SettingsRowSpec: Identifiable {
    let title: String
    let note: String
    var focus: StageSettingRow? = nil
    let control: AnyView
    var below: AnyView? = nil
    /// a switch: it stays beside its name on a narrow panel, where wider controls go under theirs
    var small = false
    var id: String { title }
}

/// Rows that belong together, in one card, with a small heading when the section has more than one card
struct SettingsGroup: Identifiable {
    var caption: String? = nil
    let rows: [SettingsRowSpec]
    var id: String { rows.first?.title ?? caption ?? "" }
}

struct StageSettings: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceTransparency) private var solid

    // NXC_FIND: the snapshot hook starts the find field with that text
    @State private var query = ProcessInfo.processInfo.environment["NXC_FIND"] ?? ""
    @State private var contentHeight: CGFloat = 640
    @State private var contentWidth: CGFloat = 700
    @State private var offset: CGFloat = 0
    @State private var viewport: CGFloat = 0
    @State private var position = ScrollPosition(edge: .top)
    @FocusState private var findFocused: Bool
    @FocusState private var scrollFocused: Bool

    var finding: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    var moreAbove: Bool { offset > 2 }
    var moreBelow: Bool { offset + viewport < contentHeight - 2 }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Rectangle().fill(.white.opacity(0.10)).frame(width: 1)
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    header
                    Rectangle().fill(.white.opacity(moreAbove ? 0.12 : 0)).frame(height: 1)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) { content }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 28).padding(.top, 6).padding(.bottom, 26)
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { contentHeight = $0.height; contentWidth = $0.width }
                    }
                    .scrollPosition($position)
                    .scrollIndicators(.visible)
                    .scrollBounceBehavior(.basedOnSize)
                    .onScrollGeometryChange(for: [CGFloat].self) { [$0.contentOffset.y, $0.containerSize.height] } action: { _, v in
                        offset = v[0]; viewport = v[1]
                    }
                    // the keyboard: arrows, page up and down, space, home and end
                    .focusable().focusEffectDisabled().focused($scrollFocused)
                    .onKeyPress(keys: [.upArrow, .downArrow, .pageUp, .pageDown, .space, .home, .end]) { press in
                        scroll(press); return .handled
                    }
                    // a section opens at its top; a controller's row stays in view
                    .onChange(of: model.settingsSection) { _, _ in position.scrollTo(edge: .top) }
                    .onChange(of: model.settingsFocus) { _, f in
                        guard let r = StageSettingRow(rawValue: f) else { return }
                        // after the section's rows are there
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(AnyHashable(r), anchor: .center) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 1020, maxHeight: 760)
        .background(StageLook.panel.opacity(solid ? 1 : 0.80))
        .clipShape(.rect(cornerRadius: 28))
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.55), radius: 50, y: 24)
        .onAppear { scrollFocused = true }
        // ⌘F finds a setting
        .background { Button("") { findFocused = true }.keyboardShortcut("f").hidden() }
    }

    // MARK: the list of sections

    var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings").font(.system(size: 26, weight: .heavy)).tracking(-0.5).padding(.horizontal, 10)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(StageLook.faint)
                TextField("Find a setting", text: $query).textFieldStyle(.plain).font(.system(size: 13.5)).focused($findFocused)
                    .onSubmit { scrollFocused = true }
                    .onExitCommand { if query.isEmpty { model.stageSettings = false } else { query = "" } }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(StageLook.faint) }
                        .buttonStyle(.plain).accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(StageLook.card, in: .capsule).overlay(Capsule().strokeBorder(StageLook.edge, lineWidth: 1))
            .padding(.top, 16).padding(.bottom, 14)
            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { s in
                    // while finding, the sections with a match stay bright and none is the chosen one
                    let on = !finding && s == model.settingsSection
                    let dim = finding && shownGroups(s).isEmpty
                    Button {
                        query = ""
                        model.settingsSection = s
                        scrollFocused = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: s.symbol).font(.system(size: 14, weight: .semibold)).frame(width: 22)
                            Text(s.rawValue).font(.system(size: 14.5, weight: on ? .bold : .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(on ? Color.white : StageLook.soft)
                        .padding(.horizontal, 10).frame(height: 34)
                        .background(on ? Color.white.opacity(0.14) : Color.clear, in: .rect(cornerRadius: 10))
                        .contentShape(.rect(cornerRadius: 10))
                        .opacity(dim ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Spacer(minLength: 12)
            Text("NXForge \(CONVERTER_VERSION)").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(StageLook.faint)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 14).padding(.top, 26).padding(.bottom, 20)
        .frame(width: 216)
        .background(Color.black.opacity(0.16))
        .animation(.easeOut(duration: 0.15), value: model.settingsSection)
    }

    // MARK: the chosen section

    var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(finding ? "Results" : model.settingsSection.rawValue).font(.system(size: 22, weight: .bold)).tracking(-0.3)
                Text(finding ? "Settings matching “\(query.trimmingCharacters(in: .whitespaces))”, from every section." : model.settingsSection.blurb)
                    .font(.system(size: 13)).foregroundStyle(StageLook.faint).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { model.stageSettings = false } label: {
                Text("Done").font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                    .padding(.horizontal, 16).frame(height: 32).background(.white, in: .capsule).contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 14)
    }

    @ViewBuilder var content: some View {
        if finding {
            let found = SettingsSection.allCases.filter { !shownGroups($0).isEmpty }
            ForEach(found) { s in
                VStack(alignment: .leading, spacing: 8) {
                    caption(s.rawValue)
                    ForEach(shownGroups(s)) { card($0, caption: false) }
                }
            }
            if found.isEmpty {
                Text("No setting matches “\(query)”.").font(.system(size: 14, weight: .medium)).foregroundStyle(StageLook.faint)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        } else {
            ForEach(groups(model.settingsSection)) { card($0, caption: true) }
        }
    }

    /// a section's cards with only the rows the find field matches; the cards left empty are dropped
    func shownGroups(_ s: SettingsSection) -> [SettingsGroup] {
        groups(s).compactMap { g in
            let rows = g.rows.filter { Self.matches(query, $0.title + " " + $0.note + " " + s.rawValue) }
            return rows.isEmpty ? nil : SettingsGroup(caption: g.caption, rows: rows)
        }
    }

    /// A row is found when every word typed starts a word of its title, its note or its section's name
    /// ("art" finds box art and the artwork folder, not "starts")
    nonisolated static func matches(_ query: String, _ text: String) -> Bool {
        let typed = query.lowercased().split(separator: " ")
        if typed.isEmpty { return true }
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        return typed.allSatisfy { t in words.contains { $0.hasPrefix(t) } }
    }

    func caption(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold)).fontWidth(.expanded).kerning(1.6).foregroundStyle(StageLook.soft)
            .padding(.leading, 4)
    }

    func card(_ g: SettingsGroup, caption show: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if show, let c = g.caption { caption(c) }
            VStack(spacing: 0) {
                ForEach(Array(g.rows.enumerated()), id: \.element.id) { i, r in
                    rowView(r)
                    if i < g.rows.count - 1 { Rectangle().fill(.white.opacity(0.10)).frame(height: 1) }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 3)
            .background(StageLook.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(StageLook.edge, lineWidth: 1))
        }
    }

    func rowView(_ r: SettingsRowSpec) -> some View {
        // the row a controller is on is lit (only while one is connected: the pointer needs no mark)
        let lit = r.focus != nil && r.focus?.rawValue == model.settingsFocus && !GCController.controllers().isEmpty
        // a small window: paths, pickers and buttons go under the row's words, which keep the full width
        let stacked = !r.small && contentWidth < 640
        let words = VStack(alignment: .leading, spacing: 2) {
            Text(r.title).font(.system(size: 14.5, weight: .semibold))
            if !r.note.isEmpty {
                Text(r.note).font(.system(size: 12.5)).foregroundStyle(StageLook.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        return VStack(alignment: .leading, spacing: 0) {
            if stacked {
                words
                r.control.frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 8)
            } else {
                HStack(spacing: 16) { words; r.control }
            }
            if let b = r.below { b.padding(.top, 8) }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(lit ? Color.white.opacity(0.10) : Color.clear, in: .rect(cornerRadius: 10))
        .padding(.horizontal, -8)
        .id(r.focus.map { AnyHashable($0) } ?? AnyHashable(r.title))
    }

    /// The keyboard over the scroll: a line, a page, or an end at a time
    func scroll(_ press: KeyPress) {
        let page = max(viewport - 60, 80)
        let top = max(contentHeight - viewport, 0)
        var y = offset
        switch press.key {
        case .upArrow: y -= 48
        case .downArrow: y += 48
        case .pageUp: y -= page
        case .pageDown: y += page
        case .space: y += press.modifiers.contains(.shift) ? -page : page
        case .home: y = 0
        case .end: y = top
        default: return
        }
        withAnimation(.easeOut(duration: 0.18)) { position.scrollTo(y: min(max(y, 0), top)) }
    }

    // MARK: building rows

    func toggle(_ title: String, _ note: String, _ on: Binding<Bool>, _ focus: StageSettingRow? = nil, disabled: Bool = false) -> SettingsRowSpec {
        SettingsRowSpec(title: title, note: note, focus: focus,
                        control: AnyView(Toggle(title, isOn: on).toggleStyle(.switch).labelsHidden().tint(.green).disabled(disabled)), small: true)
    }

    func row<C: View>(_ title: String, _ note: String, _ focus: StageSettingRow? = nil, @ViewBuilder _ control: () -> C) -> SettingsRowSpec {
        SettingsRowSpec(title: title, note: note, focus: focus, control: AnyView(HStack(spacing: 8) { control() }))
    }

    func segmented<T: Hashable>(_ selection: Binding<T>, _ all: [T], width: CGFloat, _ label: @escaping (T) -> String) -> some View {
        Picker("", selection: selection) { ForEach(all, id: \.self) { Text(label($0)) } }
            .pickerStyle(.segmented).labelsHidden().frame(width: width)
    }

    /// a chosen folder or file beside its button; `none` in its place while nothing is chosen
    func path(_ p: String?, none: String, width: CGFloat = 250) -> some View {
        Text(p ?? none).font(.system(size: 12.5)).foregroundStyle(p == nil ? StageLook.faint : StageLook.soft)
            .lineLimit(1).truncationMode(.middle).frame(maxWidth: width, alignment: .trailing)
            // as wide as its words, up to `width`: the note beside it keeps the rest of the row
            .fixedSize(horizontal: true, vertical: false).help(p ?? "")
    }

    func button(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(StageButton(height: 32))
    }

    /// leaves Settings for one of the converter's pages
    func go(_ p: Page) {
        model.showConverter()
        model.page = p
    }

    // MARK: the rows, section by section

    func groups(_ s: SettingsSection) -> [SettingsGroup] {
        switch s {
        case .general: general
        case .playing: playing
        case .library: library
        case .artwork: artwork
        case .theatre: theatre
        case .saves: saves
        case .building: building
        case .updates: updates
        case .storage: storage
        }
    }

    var general: [SettingsGroup] {
        let opening: [SettingsRowSpec] = [
            row("Open on", "Where NXForge starts: Home, Discover, Theatre (on the game and filter it was left on) or the Converter.", .startIn) {
                segmented($model.settings.startIn, StartIn.allCases, width: 330) { $0.title }
            },
        ]
        let around: [SettingsRowSpec] = [
            toggle("Return here when a game quits", "NXForge comes back to the front, ready for the next game. The game's sidebar also has Library, which quits to this game's page.", $model.settings.returnToLibrary, .returnToLibrary),
            toggle("Show a recap when a game quits", "How long you played this time and in total, with the game's peak memory.", $model.settings.sessionRecap, .sessionRecap),
            toggle("Rest while a game runs", "Behind a running game, NXForge shows a plain card and lets go of its artwork, so the game has the memory.", $model.settings.lightWhilePlaying, .lightWhilePlaying),
        ]
        let pads: [SettingsRowSpec] = [
            row("Test controllers", "See every button, stick and trigger as a game reads it, and try the rumble.") {
                button("Test…") { model.stageSettings = false; model.showControllerTest = true }
            },
        ]
        return [SettingsGroup(rows: opening), SettingsGroup(caption: "Around a game", rows: around), SettingsGroup(caption: "Controllers", rows: pads)]
    }

    var playing: [SettingsGroup] {
        let rows: [SettingsRowSpec] = [
            toggle("Play goes straight into the game", "Uses each game's saved Play options and still checks its cloud save. Its own settings window stays closed.", $model.settings.straightPlay, .straightPlay),
            toggle("Show Play options the first time", "A game you have not played yet opens its options once before it starts.", $model.settings.firstPlayOptions, .firstPlayOptions),
            toggle("Battery preset on battery", "Unplugged, a run takes the Battery preset (lowest frame rate, 75 % render scale) for the options still on the game's default. A choice you saved for a game, such as its frame rate, is kept.", $model.settings.batteryPreset, .batteryPreset),
            toggle("Keep shaders on this Mac", "A game on another drive has its compiled shaders copied here once, so it starts sooner and uses less memory. Not done when it would leave under 10 GB free.", $model.settings.localShaders, .localShaders),
        ]
        return [SettingsGroup(rows: rows)]
    }

    var library: [SettingsGroup] {
        let folder: [SettingsRowSpec] = [
            row("Games folder", "Searched, with every folder inside it, for your games. Refresh scans it now, as the top bar's button does.") {
                path(model.settings.gamesRoot?.tildePath, none: "Not chosen", width: 200)
                button(model.settings.gamesRoot == nil ? "Choose…" : "Change…") { model.chooseGamesRoot() }.disabled(model.libraryScanning)
                button(model.libraryScanning ? "Refreshing…" : "Refresh") { model.scanLibrary() }.disabled(model.libraryScanning || model.settings.gamesRoot == nil)
            },
            row("Look for new games", "How often NXForge looks at the games folder, in front or not, and scans when a game was added or removed. It also looks each time it comes to the front. Manual leaves it to Refresh.", .folderCheck) {
                segmented($model.settings.folderCheck, FolderCheck.allCases, width: 290) { $0.rawValue }
            },
        ]
        let look: [SettingsRowSpec] = [
            toggle("Square covers", "Shows each game's square shop art instead of its box on Home and in Discover: smaller, so more fit in a row. The same as Discover's square button.", $model.settings.squareCovers, .squareCovers),
            toggle("Group Game Files by console", "The Converter's Game Files page in a Switch 2 section and a Switch one.", $model.settings.libraryGroupByConsole, .groupByConsole),
        ]
        return [SettingsGroup(rows: folder), SettingsGroup(caption: "How games are shown", rows: look)]
    }

    var artwork: [SettingsGroup] {
        let downloads: [SettingsRowSpec] = [
            toggle("Download box art", "Front and back covers from GameTDB, matched by the game's name; a download-only game gets a box made from its square art on Nintendo Life. Only a cover's ID or the game's name is sent.", $model.settings.downloadCovers, .downloadCovers),
            toggle("Download wide art", "The header art from each game's page on Nintendo Life, else the banner from Nintendo's European store, behind its page and Home. Found by name or title ID; only those are sent.", $model.settings.downloadHeroes, .downloadHeroes),
            toggle("Download store details", "A game's description, details and official screenshots from its store page, fetched when you open the game's page.", $model.settings.downloadStoreInfo, .downloadStoreInfo),
        ]
        let kept: [SettingsRowSpec] = [
            toggle("Keep media and cheats in each game's folder", "A built game's covers, wide art, screenshots and manual go in a media folder beside its app, with game.md listing its details, links and build; its cheats go in a cheats folder beside that. Both are read back on a Mac that has none for the game yet.", $model.settings.mediaInGameFolder, .mediaInGameFolder),
            row("Artwork folder", "Your own covers and the downloaded art, kept on this Mac only. Look Again tries the downloads that found nothing.") {
                button("Look Again") { CoverStore.shared.lookAgain(); StoreInfoStore.shared.lookAgain(); model.fetchCovers(model.stageGames()) }
                button("Show") { try? FileManager.default.createDirectory(at: CoverStore.dir, withIntermediateDirectories: true); NSWorkspace.shared.open(CoverStore.dir) }
            },
        ]
        return [SettingsGroup(caption: "Downloads", rows: downloads), SettingsGroup(caption: "Where it is kept", rows: kept)]
    }

    var theatre: [SettingsGroup] {
        let theme = Binding(get: { model.settings.theatreTheme }, set: { model.settings.theatreTheme = $0; model.theatreTheme = $0 })
        let volume = Binding(get: { Double(model.settings.theatreVolume) }, set: { model.settings.theatreVolume = Int($0.rounded()); model.theatreVolumeTick += 1 })
        let screen: [SettingsRowSpec] = [
            row("Theatre", "Your games full screen, for the sofa and a controller. Also ⇧⌘F. B leaves it.") {
                button(model.theatre ? "Leave Theatre" : "Open Theatre") { model.stageSettings = false; model.toggleTheatre() }
            },
            row("Theme", "Carousel turns a ring of your boxes; Cinema shows big art with rows like a TV app; Gallery shows three covers on a quiet wall; Trailer plays the game's trailer. ZL and ZR switch them on Theatre.", .theatreTheme) {
                segmented(theme, TheatreTheme.allCases, width: 300) { $0.rawValue }
            },
            row("When a TV is plugged in", "Ask offers Theatre when a controller is connected too; Always opens it straight away.", .theatreOnTV) {
                segmented($model.settings.theatreOnTV, TheatreOnTV.allCases, width: 240) { $0.rawValue }
            },
            row("TV edges", "Some TVs crop the edges of the picture. If Theatre's clock or buttons are cut off, inset the picture.", .theatreEdges) {
                segmented($model.settings.theatreEdges, TheatreEdges.allCases, width: 240) { $0.title }
            },
            row("Screensaver", "Left alone this long, Theatre cycles your games' art with a dim clock, and after an hour lets the TV sleep. Any button wakes it.", .theatreSaver) {
                segmented($model.settings.theatreSaver, TheatreSaver.allCases, width: 240) { $0.rawValue }
            },
        ]
        let sound: [SettingsRowSpec] = [
            row("Volume", "Of everything Theatre plays: its sounds, a game's music and trailers. The right stick sets it on Theatre, and its press mutes.", .theatreVolume) {
                Slider(value: volume, in: 0...100, step: 10).frame(width: 190).tint(.white).accessibilityLabel("Theatre volume")
                Text("\(model.settings.theatreVolume) %").font(.system(size: 12.5, weight: .medium)).monospacedDigit().foregroundStyle(StageLook.soft).frame(width: 46, alignment: .trailing)
            },
            toggle("Sounds", "A soft tick for each step, a quiet tick as the Carousel or Fan turns and a thunk on launch.", $model.settings.theatreSounds, .theatreSounds),
            toggle("Music", "Plays your music folder in the background (not in Trailer); a game with its own music.m4a or .mp3 in its media folder plays that while it is in focus.", $model.settings.theatreMusic, .theatreMusic),
            row("Music folder", "MP3 or Opus files (and M4A, FLAC, WAV), shuffled through in turn.") {
                path(model.settings.theatreMusicFolder?.tildePath, none: "None chosen", width: 220)
                if model.settings.theatreMusicFolder != nil { button("Clear") { model.settings.theatreMusicFolder = nil } }
                button(model.settings.theatreMusicFolder == nil ? "Choose…" : "Change…") {
                    if let f = model.choose(folder: true, start: model.settings.theatreMusicFolder) { model.settings.theatreMusicFolder = f }
                }
            },
            toggle("Light follows the time of day", "A cooler, brighter room in the morning, a warm evening, and a dimmer one after 10 pm.", $model.settings.theatreTimeOfDay, .theatreTimeOfDay),
        ]
        return [SettingsGroup(rows: screen), SettingsGroup(caption: "Sound and light", rows: sound)]
    }

    var saves: [SettingsGroup] {
        let s = model.settings
        let cloud: [SettingsRowSpec] = [
            SettingsRowSpec(title: "Cloud saves for every game", note: "Each game brings its save in when it starts and sends it after every save, so another Mac or the iPhone app can carry on.", focus: .cloudSaves,
                            control: AnyView(Toggle("Cloud saves for every game", isOn: Binding(get: { model.settings.cloudSavesAll }, set: { model.setCloudSavesForAll($0) }))
                                .toggleStyle(.switch).labelsHidden().tint(.green)), small: true),
            row("Cloud saves folder", "Every game's save goes here, each in a folder named after its title ID. A folder in iCloud Drive syncs with your other devices.") {
                path(s.cloudSavesFolder.map { CloudSaves.shown($0) }, none: "Chosen when it is turned on")
                button(s.cloudSavesFolder == nil ? "Choose…" : "Change…") { model.chooseCloudSavesFolder() }
            },
        ]
        let snapshots: [SettingsRowSpec] = [
            toggle("Snapshot after every session", "A checked copy of the save each time a game quits with it changed. The newest \(SaveSnapshots.keepAutomatic) stay for each game.", $model.settings.snapshotAfterPlay, .snapshotAfterPlay),
            row("Snapshot folder", "Another drive, a NAS or iCloud Drive keeps the snapshots safe from the save's own drive.") {
                path(s.saveSnapshotsFolder?.tildePath, none: "Beside each save")
                button("Choose…") { model.chooseSnapshotFolder() }
                if s.saveSnapshotsFolder != nil { button("Reset") { model.setSnapshotFolder(nil) } }
            },
        ]
        let backup: [SettingsRowSpec] = [
            row("Save backup repository", "A clone of a private Git repository: each game's save is committed to it when the game quits.") {
                path(s.saveBackupRepo?.tildePath, none: "Off")
                button("Choose…") { model.chooseSaveBackupRepo() }
                if s.saveBackupRepo != nil { button("Turn Off") { model.settings.saveBackupRepo = nil } }
            },
            toggle("Push after each backup", "Sends each commit to the repository's remote, so the saves leave this Mac.", $model.settings.saveBackupPush, .saveBackupPush, disabled: s.saveBackupRepo == nil),
        ]
        let page: [SettingsRowSpec] = [
            row("Every game's save", "The Saves page lists each game's save with its snapshots, and moves a save in or out.") { button("Open Saves") { go(.saves) } },
        ]
        return [SettingsGroup(caption: "Cloud", rows: cloud), SettingsGroup(caption: "Snapshots", rows: snapshots), SettingsGroup(caption: "Git backup", rows: backup), SettingsGroup(rows: page)]
    }

    var building: [SettingsGroup] {
        let s = model.settings
        let out = Binding(get: { model.settings.outDir ?? "" }, set: { model.settings.outDir = $0.isEmpty ? nil : $0 })
        var keysRow = row("Keys file (prod.keys)", "Chosen once and used for every build, rebuild and the nxforge command. A game folder's own prod.keys is used only when none is saved.") {
            path(s.defaultKeys?.tildePath, none: "None", width: 200)
            button(s.defaultKeys == nil ? "Choose…" : "Change…") { model.chooseSavedKeys() }
            if s.defaultKeys != nil { button("Clear") { model.saveKeys(nil) } }
        }
        keysRow.below = AnyView(KeysStatusRow(model: model, dark: true))
        let after: [SettingsRowSpec] = [
            SettingsRowSpec(title: "Notify when a build finishes", note: "A notification when the build is complete, or has stopped.", focus: .notify,
                            control: AnyView(Toggle("Notify when a build finishes", isOn: $model.settings.notify).toggleStyle(.switch).labelsHidden().tint(.green)
                                .onChange(of: model.settings.notify) { _, on in if on { model.requestNotifications() } }), small: true),
            toggle("Open the app after building", "The new app opens by itself when its build completes.", $model.settings.openAfterBuild, .openAfterBuild),
            toggle("Keep previous app builds", "A rebuild moves the app it replaces to app-backups; off moves it to the Trash.", $model.settings.keepBackups, .keepBackups),
            row("Build folder after a build", s.cleanup == .all ? "Deletes the build folders, keeping the logs in ~/Library/Logs/NXForge; the next build starts over (about 30 min)." : s.cleanup == .shaders ? "Deletes the build's copies of the game files and keeps the shader work beside the game, so a rebuild skips the shader steps while they are unchanged." : "Remove unused files clears old versions' extracted files; Remove build cache frees the most, and the next build starts over.") {
                Picker("", selection: $model.settings.cleanup) { ForEach(Cleanup.allCases, id: \.self) { Text($0.label) } }.labelsHidden().fixedSize()
            },
        ]
        let how: [SettingsRowSpec] = [
            row("Save new apps", "Where a build puts the Mac app.") {
                Picker("", selection: out) {
                    Text("Beside the game files").tag("")
                    if let o = s.outDir { Text(o.tildePath).tag(o) }
                }
                .labelsHidden().fixedSize()
                button("Choose…") { if let d = model.choose(folder: true, start: model.settings.outDir) { model.settings.outDir = d } }
            },
            row("Sign apps with", "Ad-hoc apps open on this Mac; a developer identity signs them as you.") {
                Picker("", selection: $model.settings.signIdentity) {
                    Text("Ad-hoc (this Mac only)").tag(String?.none)
                    ForEach(model.identities, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .labelsHidden().fixedSize()
            },
            toggle("Reuse finished build steps", "A rebuild skips the steps whose files have not changed. Off runs every step again.", $model.settings.reuseCache, .reuseCache),
            row("Build logs", "Detailed adds each tool's own log to Copy log.") {
                segmented($model.settings.logDetail, LogDetail.allCases, width: 190) { $0.rawValue }
            },
        ]
        return [SettingsGroup(caption: "Keys", rows: [keysRow]), SettingsGroup(caption: "When a build finishes", rows: after), SettingsGroup(caption: "How apps are built", rows: how)]
    }

    var updates: [SettingsGroup] {
        let state = model.engineBusy ? "Checking…" : model.anyUpdate ? "Updates are available." : "Everything is up to date."
        let checked = model.lastUpdateCheck.map { "Last checked \(relativeDay($0).lowercasedFirst)." } ?? "Not checked yet."
        let rows: [SettingsRowSpec] = [
            row("NXForge \(CONVERTER_VERSION)", model.converterUpdate.map { "Version \($0.version) is ready to install." } ?? "This is the newest version of the app.") {
                button("What's New") { model.stageSettings = false; model.showWhatsNew() }
                if model.converterUpdate != nil { button("Update…") { model.stageSettings = false; model.updateConverter() }.disabled(model.converterUpdating) }
            },
            row("Check for updates", "\(state) \(checked)") {
                button("Check Now") { model.engineAction(update: false, reason: .manual) }.disabled(model.engineBusy || model.engine == nil)
            },
            toggle("Update automatically", "At launch and when NXForge comes back to the front, the engine and the app update without asking (never during a build). A game is never rebuilt without asking.", $model.settings.autoUpdate, .autoUpdate),
            row("What changed", "The Updates page lists the engine's and the app's new versions with their notes, and the games whose sidebar is older.") { button("Open Updates") { go(.updates) } },
        ]
        return [SettingsGroup(rows: rows)]
    }

    var storage: [SettingsGroup] {
        var rows: [SettingsRowSpec] = [
            row("Games' storage", "Every game's build cache, older app copies and the shared shader cache, with their sizes.") { button("Manage Storage…") { go(.storage) } },
            row("Everything else", "What NXForge and its games keep outside the games' folders: settings, artwork, logs, game data and the command line tool.") {
                button("What NXForge Keeps…") { model.stageSettings = false; model.showLeftovers = true }
            },
            row("Health", "What is wrong with the library, the drives or a build, listed before anything changes, each with its repair.") { button("Open Health") { go(.health) } },
        ]
        // the game on Convert, when it has a build folder
        if let c = model.buildCache {
            rows.insert(row("Build cache of the game on Convert", "\(c.tildePath). The next build makes it again, which takes much longer.") {
                button("Show") { reveal(c) }
                button("Clear Cache…") { clearCache(c) }.disabled(model.run.running)
            }, at: 1)
        }
        let reset: [SettingsRowSpec] = [
            row("Restore defaults", "Notifications, output, keys, build and signing choices go back to their defaults. Your games folder, artwork and saves stay.") {
                button("Restore Defaults…") {
                    if model.confirm("Restore default settings?", "Notifications, output, keys, build and signing preferences go back to their defaults. Your game folder and engine stay.", action: "Restore") {
                        model.settings.restoreDefaults(); model.recheck()
                    }
                }
            },
        ]
        return [SettingsGroup(rows: rows), SettingsGroup(caption: "Reset", rows: reset)]
    }

    /// The whole <id>_build folder goes to the Trash: the next build extracts and compiles everything again.
    func clearCache(_ c: String) {
        let size = Disk.size(c)
        guard model.confirm("Clear the build cache?", "\(c.lastComponent) (\(Disk.gb(size))) moves to the Trash. The next build extracts the game and compiles its shaders again, which takes much longer. Built apps are not affected.", action: size > 0 ? "Move \(Disk.gb(size)) to Trash" : "Move to Trash") else { return }
        try? FileManager.default.trashItem(at: c.url, resultingItemURL: nil)
        model.revision += 1
    }
}
