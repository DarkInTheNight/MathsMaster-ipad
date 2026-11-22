import SwiftUI

/// Typed card editor: HTML + MathJax source on the left, live preview on the right, live lint (design plan §4.4).
struct CardEditorView: View {
    let original: Card
    var onSave: (Card) -> Void

    @Environment(CardStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var card: Card
    @State private var tagsText: String
    @State private var lectureText: String
    @State private var showPreview = true
    @FocusState private var focus: Field?
    private enum Field { case front, back }

    init(card: Card, onSave: @escaping (Card) -> Void) {
        self.original = card
        self.onSave = onSave
        _card = State(initialValue: card)
        _tagsText = State(initialValue: card.tags.joined(separator: ", "))
        _lectureText = State(initialValue: card.lecture.map(String.init) ?? "")
    }

    private var issues: [CardLintIssue] { CardText.lint(front: card.front, back: card.back) }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = geo.size.width > 800
                Group {
                    if wide {
                        HStack(spacing: 0) { source; Divider(); preview }
                    } else {
                        VStack(spacing: 0) { if showPreview { preview.frame(height: geo.size.height * 0.4); Divider() }; source }
                    }
                }
            }
            .navigationTitle(original.front.isEmpty && original.back.isEmpty ? "New card" : "Edit card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(card.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { showPreview.toggle() } label: { Label("Preview", systemImage: "eye") }
                }
            }
        }
    }

    private var source: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                field("Front", text: $card.front, which: .front, minHeight: 90)
                field("Back", text: $card.back, which: .back, minHeight: 240)
                lintList
                metadata
            }
            .padding(16)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                ForEach(snippets, id: \.0) { label, text in
                    Button(label) { insert(text) }
                }
            }
        }
    }

    private let snippets: [(String, String)] = [
        ("\\( \\)", "\\(  \\)"), ("\\[ \\]", "\\[  \\]"), ("<b>", "<b></b>"), ("<br>", "<br><br>"),
        ("<i>", "<i></i>"), ("aligned", "\\begin{aligned}  \\end{aligned}"), ("∎", "\\blacksquare"), ("&lt;", "&lt;"),
    ]

    private func insert(_ text: String) {
        if focus == .front { card.front += text } else { card.back += text }
    }

    private func field(_ title: String, text: Binding<String>, which: Field, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(Theme.ink2)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($focus, equals: which)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var lintList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(issues) { issue in
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.hard)
                    Text("\(issue.field == .front ? "Front" : "Back"): \(issue.message)").font(.callout)
                    Spacer()
                    if let fixed = issue.fixed {
                        Button("Fix") {
                            if issue.field == .front { card.front = fixed } else { card.back = fixed }
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Course", selection: $card.courseID) {
                ForEach(library.manifest.courses.filter { !$0.archived }) { Text($0.name).tag($0.id) }
            }
            Picker("Label", selection: $card.label) {
                ForEach(CardLabel.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            HStack {
                Text("Lecture"); TextField("e.g. 14", text: $lectureText).keyboardType(.numberPad).frame(width: 80)
                Text("Tags"); TextField("comma separated", text: $tagsText).textInputAutocapitalization(.never)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CardWebView(html: card.front, mediaFolder: store.mediaFolder(for: card.courseID), fontSize: 22)
                    .frame(height: 140)
                Divider()
                CardWebView(html: card.back, mediaFolder: store.mediaFolder(for: card.courseID))
                    .frame(height: 520)
            }
        }
        .background(Theme.background)
    }

    private func save() async {
        var c = card
        c.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        c.lecture = Int(lectureText)
        // Keep the old text as a revision; infer the label only if the user left it at Other.
        c.front = original.front; c.back = original.back
        c.edit(front: card.front, back: card.back)
        if c.label == .other { c.label = CardLabel.infer(fromFront: card.front) }
        await store.save(c)
        onSave(c)
        dismiss()
    }
}
