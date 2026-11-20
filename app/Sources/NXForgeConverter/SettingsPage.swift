// The keys row's status line in Settings (StageSettings.swift). Before Converter 0.22.3 this file also held a Settings window
// of its own (⌘,), with the converter's options; they are sections of the one Settings panel now.
import AppKit
import SwiftUI

/// The saved keys file's status (found, missing, unreadable, incomplete) and, while none reads, a prod.keys found in a usual place.
struct KeysStatusRow: View {
    @Bindable var model: AppModel
    /// true on the front end's dark panel
    let dark: Bool

    var body: some View {
        let st = model.keysStatus
        VStack(alignment: .leading, spacing: 6) {
            Label(st.text, systemImage: st.symbol)
                .foregroundStyle(st.ok ? Color.green : st == .notSet ? (dark ? Color.white.opacity(0.6) : Color.secondary) : Color.orange)
                .font(.system(size: 12.5, weight: .medium))
            if let s = model.keysSuggestion {
                HStack(spacing: 8) {
                    Text("Found one at \(s.tildePath)").font(.system(size: 12.5)).foregroundStyle(dark ? Color.white.opacity(0.6) : Color.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    if dark { Button("Use This") { model.saveKeys(s) }.buttonStyle(StageButton(height: 28)) }
                    else { Button("Use This") { model.saveKeys(s) } }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(model.settings.defaultKeys ?? "")|\(model.settings.gamesRoot ?? "")") { model.refreshKeysStatus() }
    }
}
