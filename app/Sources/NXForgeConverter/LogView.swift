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
        // one pass over the log per redraw: each line's level is read once, for the shown lines and the tabs' counts alike
        let scan = scanned
        let shown = scan.shown
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // All / Warnings / Errors as tabs with their counts
                HStack(spacing: 2) {
                    ForEach(LogFilter.allCases, id: \.self) { f in tab(f, count: scan.count(f)) }
                }
                .padding(3)
                .background(.white.opacity(0.08), in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search the log…", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty { Button { search = "" } label: { Label("Clear Search", systemImage: "xmark.circle.fill").labelStyle(.iconOnly).foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 10).frame(height: 32).frame(maxWidth: 520)
                .background(.white.opacity(0.08), in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                Spacer()
                Toggle("Follow", isOn: $follow).toggleStyle(.checkbox).help("Keep the newest line in view while the build runs")
                Button { copy() } label: { Label("Copy log", systemImage: "doc.on.clipboard") }.buttonStyle(.stage)
                if let file {
                    Button { NSWorkspace.shared.open(file.url) } label: { Label("Open log file", systemImage: "doc.text") }.buttonStyle(.stage)
                        .help(file.tildePath)
                }
            }
            ScrollViewReader { proxy in
                ScrollView([.vertical]) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(shown, id: \.offset) { i, line, level in
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

    /// The lines the filter and search leave, with their line numbers (the scroll position's ids) and levels, and how many
    /// warnings and errors the whole log has.
    struct Scan {
        var shown: [(offset: Int, line: String, level: LogLevel)] = []
        var total = 0, warnings = 0, errors = 0

        func count(_ f: LogFilter) -> Int {
            switch f {
            case .all: total
            case .warnings: warnings + errors
            case .errors: errors
            }
        }
    }

    var scanned: Scan {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        var s = Scan(total: lines.count)
        for (i, l) in lines.enumerated() {
            let level = LogLevel(l)
            if level == .error { s.errors += 1 } else if level == .warning { s.warnings += 1 }
            switch filter {
            case .all: break
            case .warnings: if level == .info { continue }
            case .errors: if level != .error { continue }
            }
            if q.isEmpty || l.lowercased().contains(q) { s.shown.append((i, l, level)) }
        }
        return s
    }

    func tab(_ f: LogFilter, count: Int) -> some View {
        let on = filter == f
        let (symbol, tint): (String, Color) = switch f {
        case .all: ("list.bullet.circle.fill", StageLook.soft)
        case .warnings: ("exclamationmark.triangle.fill", .yellow)
        case .errors: ("xmark.circle.fill", .red)
        }
        return Button { filter = f } label: {
            Label { Text("\(f.rawValue) (\(count))") } icon: { Image(systemName: symbol).foregroundStyle(on ? Color.black : tint) }
                .fontWeight(.medium)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(on ? Color.black : Color.primary)
                .background(on ? Color.white.opacity(0.92) : .clear, in: .capsule)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
