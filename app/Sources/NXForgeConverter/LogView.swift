// The build log: every line, or only the warnings or errors, a search, and following the newest line while a build runs.
import AppKit
import SwiftUI

enum LogFilter: String, CaseIterable { case all = "All", warnings = "Warnings", errors = "Errors" }

enum LogLevel {
    case info, warning, error

    /// The script marks a failure "[RED]" (and ✗); tools write "error:" / "warning:"; ⚠ is a stage that ended without its output.
    init(_ line: String) {
        let l = line.lowercased()
        if line.contains("[RED]") || line.contains("✗") || l.contains("error:") || l.contains(" error ") || l.hasPrefix("error") || l.contains("failed") || l.contains("traceback") {
            self = .error
        } else if line.contains("⚠") || l.contains("warning") || l.contains("[yel") {
            self = .warning
        } else {
            self = .info
        }
    }

    var color: Color { switch self { case .info: .secondary; case .warning: .orange; case .error: .red } }
}

struct LogView: View {
    let lines: [String]
    let running: Bool
    /// the log written to <id>_build/logs, once the build ended
    var file: String?
    /// shown in the empty log, as a prompt line
    var placeholder = "Nothing logged yet."
    var copy: () -> Void
    @State private var filter: LogFilter = .all
    @State private var search = ""
    @State private var follow = true

    var body: some View {
        let shown = visible
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // All / Warnings / Errors as tabs with their counts
                HStack(spacing: 2) {
                    ForEach(LogFilter.allCases, id: \.self) { f in tab(f) }
                }
                .padding(3)
                .background(Theme.card, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardStroke))
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search the log…", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 10).frame(height: 32).frame(maxWidth: 520)
                .background(Theme.card, in: .rect(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.cardStroke))
                Spacer()
                Toggle("Follow", isOn: $follow).toggleStyle(.checkbox).help("Keep the newest line in view while the build runs")
                Button { copy() } label: { Label("Copy log", systemImage: "doc.on.clipboard") }.buttonStyle(.glass)
                if let file {
                    Button { NSWorkspace.shared.open(file.url) } label: { Label("Open log file", systemImage: "doc.text") }.buttonStyle(.glass)
                        .help(file.tildePath)
                }
            }
            ScrollViewReader { proxy in
                ScrollView([.vertical]) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(shown, id: \.offset) { i, line in
                            let level = LogLevel(line)
                            Text(line.isEmpty ? " " : line)
                                .font(.caption.monospaced())
                                .foregroundStyle(level == .info ? Color.primary.opacity(0.8) : level.color)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 140, idealHeight: 240, maxHeight: 320)
                .background(Theme.well, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardStroke))
                .overlay(alignment: .topLeading) {
                    if shown.isEmpty {
                        Text("> " + (lines.isEmpty ? placeholder : "No lines match."))
                            .font(.callout.monospaced()).foregroundStyle(.secondary).padding(14)
                    }
                }
                .onChange(of: lines.count) { _, _ in
                    if follow, running, let last = shown.last { proxy.scrollTo(last.offset, anchor: .bottom) }
                }
                .onAppear { if let last = shown.last { proxy.scrollTo(last.offset, anchor: .bottom) } }
            }
        }
    }

    /// The lines the filter and search leave, with their line numbers (the scroll position's ids).
    var visible: [(offset: Int, element: String)] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return lines.enumerated().filter { _, l in
            let level = LogLevel(l)
            switch filter {
            case .all: break
            case .warnings: if level == .info { return false }
            case .errors: if level != .error { return false }
            }
            return q.isEmpty || l.lowercased().contains(q)
        }.map { (offset: $0.offset, element: $0.element) }
    }

    func count(_ f: LogFilter) -> Int {
        switch f {
        case .all: lines.count
        case .warnings: lines.filter { LogLevel($0) != .info }.count
        case .errors: lines.filter { LogLevel($0) == .error }.count
        }
    }

    func tab(_ f: LogFilter) -> some View {
        let on = filter == f
        let (symbol, tint): (String, Color) = switch f {
        case .all: ("list.bullet.circle.fill", .accentColor)
        case .warnings: ("exclamationmark.triangle.fill", .yellow)
        case .errors: ("xmark.circle.fill", .red)
        }
        return Button { filter = f } label: {
            Label { Text("\(f.rawValue) (\(count(f)))") } icon: { Image(systemName: symbol).foregroundStyle(on ? .white : tint) }
                .fontWeight(.medium)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(on ? .white : .primary)
                .background(on ? Color.accentColor : .clear, in: .rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
