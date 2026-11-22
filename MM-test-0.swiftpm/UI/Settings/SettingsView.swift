import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var confirmForget = false
    @State private var showingDiagnostics = false

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Folder", value: library.rootURL?.lastPathComponent ?? "—")
                LabeledContent("Courses", value: "\(library.manifest.courses.filter { !$0.archived }.count)")
                LabeledContent("Documents", value: "\(library.allDocuments.count)")
                Button("Rescan library") {
                    Task { await library.rescanAll() }
                }
                Button("Use a different folder…", role: .destructive) {
                    confirmForget = true
                }
            }

            if let year = library.manifest.currentYear {
                Section {
                    ForEach(year.terms, id: \.name) { term in
                        LabeledContent(term.name.displayName, value: "\(format(term.start)) – \(format(term.end))")
                    }
                } header: {
                    Text(year.name)
                } footer: {
                    Text("Full Term dates. Week numbers on Today count from the first Thursday of Full Term.")
                }
            }

            Section("This copy of the app") {
                LabeledContent("Install ID", value: String(InstallIdentity.id.prefix(8)))
                LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "—")
                LabeledContent("Version", value: appVersion)
                Button("Diagnostics") { showingDiagnostics = true }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Use a different library folder?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Choose another folder", role: .destructive) { library.forgetFolder() }
        } message: {
            Text("Nothing is deleted. The app just forgets this folder until you pick one again.")
        }
        .sheet(isPresented: $showingDiagnostics) {
            NavigationStack { DiagnosticsView() }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func format(_ date: CalendarDate) -> String {
        date.date().formatted(.dateTime.day().month(.abbreviated).year())
    }
}

/// The in-app log (there's no Xcode console on the iPad). Also written to Logs/ in the library.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    private let log = AppLog.shared

    var body: some View {
        List(log.lines.reversed()) { line in
            VStack(alignment: .leading, spacing: 2) {
                Text(line.message)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(line.level == .error ? Theme.again : Theme.ink)
                Text(line.date.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .overlay {
            if log.lines.isEmpty {
                ContentUnavailableView("No log lines yet", systemImage: "text.alignleft")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: log.text) {
                    Label("Share log", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
