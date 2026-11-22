import SwiftUI

/// Export PDF / Print / Hand in: one options sheet (design plan §3.7, §3.8).
struct ExportSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(editorHandInNameKey) private var name = ""
    @State private var options = ExportOptions()
    @State private var working = false
    @State private var result: EditorModel.ExportResult?

    init(model: EditorModel, handIn: Bool) {
        self.model = model
        var options = ExportOptions()
        options.handIn = handIn
        // Template lines are off by default for notebooks (dots and grids vanish on paper).
        options.templateLines = model.document.kind != .notebook
        _options = State(initialValue: options)
    }

    var body: some View {
        NavigationStack {
            Form {
                if options.handIn {
                    Section {
                        TextField("Your name", text: $name)
                            .textContentType(.name)
                    } header: {
                        Text("Hand-in")
                    } footer: {
                        Text("Answers in question order. File: \(model.exportFileName(options: options))")
                    }
                }
                Section("Pages") {
                    Picker("Pages", selection: $options.scope) {
                        ForEach(scopes) { scope in Text(scope.title).tag(scope) }
                    }
                    .pickerStyle(.segmented)
                    Text("\(model.pageIndices(for: options).count) page(s)").foregroundStyle(.secondary)
                }
                Section("Appearance") {
                    Toggle("Template lines", isOn: $options.templateLines)
                    Toggle("Highlighter", isOn: $options.highlighter)
                    Toggle("All ink black", isOn: $options.allBlack)
                    Toggle("Footer and page numbers", isOn: $options.footer)
                    if model.isExampleSheet && !options.handIn {
                        Toggle("Answers in question order", isOn: $options.handIn)
                    }
                }
                Section {
                    Button {
                        Task { await runExport() }
                    } label: {
                        Label(options.handIn ? "Make hand-in PDF" : "Export PDF", systemImage: "doc.richtext")
                    }
                    .disabled(working)
                    Button {
                        model.printPDF(options: options)
                    } label: {
                        Label("Print…", systemImage: "printer")
                    }
                    .disabled(working)
                    if working { ProgressView() }
                }
                if let result {
                    Section {
                        ShareLink(item: result.shareURL) {
                            Label("Share \(result.fileName)", systemImage: "square.and.arrow.up")
                        }
                    } footer: {
                        Text(result.libraryURL != nil ? "Also saved in MathsMaster › Exports." : "Couldn't save a copy in Exports; share it instead.")
                    }
                }
            }
            .navigationTitle(options.handIn ? "Hand in" : "Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .onChange(of: options) { result = nil }
        }
    }

    private var scopes: [ExportOptions.Scope] {
        model.isExampleSheet ? ExportOptions.Scope.allCases : [.all, .current]
    }

    private func runExport() async {
        working = true
        result = nil
        // Let the progress indicator appear before the (main-thread) rendering starts.
        try? await Task.sleep(for: .milliseconds(50))
        result = await model.export(options: options)
        working = false
    }
}
