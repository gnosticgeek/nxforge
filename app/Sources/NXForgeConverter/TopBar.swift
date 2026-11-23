// The window's top bar: a real macOS toolbar on the row with the window's buttons, as Music, TV and the App Store have it.
// The title at the left, the Home / Discover / Saves / Converter switch in the middle, then one group of Theatre, Refresh and
// Settings, and Discover's search (StageView's .searchable). It is hidden wherever a page fills the window: a game's own page,
// the launch screen, the viewers, Theatre and standby. Full screen is the window's green button (⌃⌘F), as in every Mac app.
import AppKit
import GameController
import SwiftUI

/// The four places the switch in the middle goes to
enum TopPlace: String, CaseIterable, Identifiable {
    case home = "Home", discover = "Discover", saves = "Saves", converter = "Converter"
    var id: Self { self }
}

struct TopBar: ViewModifier {
    @Bindable var model: AppModel

    /// The bar shows over the shelves, Discover and the converter's pages; a page that fills the window has its own way back.
    var shown: Bool {
        if model.standby || model.theatre { return false }
        if model.frontEnd { return model.gameDetail == nil && model.launching == nil && !model.viewerOpen }
        return true
    }

    var place: Binding<TopPlace> {
        Binding {
            if model.frontEnd { return model.stageTab == .home ? .home : .discover }
            return model.page == .saves ? .saves : .converter
        } set: { p in
            switch p {
            case .home: model.showStage(.home)
            case .discover: model.showStage(.discover)
            case .saves: model.showConverter(); model.page = .saves
            case .converter:
                if model.frontEnd || model.page == .saves { model.showConverter(); if model.page == .saves { model.page = model.converterPage } }
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .navigationTitle("NXForge")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: place) {
                        ForEach(TopPlace.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Home, every game in Discover, every game's saves, or the converter's pages")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { model.enterTheatre() } label: { Label("Theatre", systemImage: "tv") }
                        .help(theatreHelp)
                    refresh
                    Button { model.openSettings() } label: { Label("Settings", systemImage: "gearshape") }
                        .help("Settings (⌘,)")
                }
            }
            .toolbar(shown ? .visible : .hidden, for: .windowToolbar)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            // the toolbar's glass and title follow the window's look, which is always dark here
            .preferredColorScheme(.dark)
    }

    var theatreHelp: String {
        let pad = GCController.controllers().first?.vendorName.map { " \($0) is connected." } ?? ""
        return "Theatre: your games full screen on a TV, driven by a controller (⇧⌘F).\(pad)"
    }

    /// Refresh: scans the games folder again now (NXForge also looks every 10 minutes and when it comes to the front); new games
    /// get their art and details. The arrow turns while it scans.
    var refresh: some View {
        Button { model.scanLibrary() } label: {
            Label(model.libraryScanning ? "Refreshing Library" : "Refresh Library", systemImage: "arrow.clockwise")
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: model.libraryScanning)
        }
        .disabled(model.libraryScanning || model.settings.gamesRoot == nil)
        .help(model.libraryScanning ? "Looking through \(model.settings.gamesRoot?.tildePath ?? "the games folder")…"
              : "Refresh the library: look for new games now (also every 10 minutes), and fetch their artwork and details (⌥⌘R)")
    }
}
