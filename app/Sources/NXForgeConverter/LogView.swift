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
    var copy: () -> Void
    @State private var filter: LogFilter = .all
    @State private var search = ""
    @State private var follow = true

    var body: some View {
        let shown = visible
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("", selection: $filter) {
                    ForEach(LogFilter.allCases, id: \.self) { f in Text(label(f)).tag(f) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search the log", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 8).frame(height: 26)
                .background(.background.opacity(0.5), in: .rect(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator))
                Toggle("Follow", isOn: $follow).toggleStyle(.checkbox).help("Keep the newest line in view while the build runs")
                Spacer()
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
                .frame(height: 260)
                .background(.background.opacity(0.35), in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.8)))
                .overlay {
                    if shown.isEmpty { Text(lines.isEmpty ? "Nothing logged yet." : "No lines match.").foregroundStyle(.secondary) }
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

    func label(_ f: LogFilter) -> String {
        switch f {
        case .all: return "All \(lines.count)"
        case .warnings: return "Warnings \(lines.filter { LogLevel($0) != .info }.count)"
        case .errors: return "Errors \(lines.filter { LogLevel($0) == .error }.count)"
        }
    }
}
