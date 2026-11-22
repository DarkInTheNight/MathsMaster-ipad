import SwiftUI
import PDFKit

/// The reference pane ◫ (design plan §3.2, §3.7): a second document beside the canvas.
/// For example sheets it shows the questions and follows the question navigator.
struct ReferencePane: View {
    let model: EditorModel
    let pdf: PDFDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.referenceTitle ?? "Reference")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    model.showReference = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close reference pane")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface)
            Divider()
            ReferencePDFView(document: pdf, target: model.referenceTarget)
        }
    }
}

struct ReferencePDFView: UIViewRepresentable {
    let document: PDFDocument
    let target: EditorModel.ReferenceTarget?

    final class Coordinator {
        var lastToken: UUID?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(hex: 0xE9E6E0)
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
            context.coordinator.lastToken = nil
        }
        guard let target, target.token != context.coordinator.lastToken else { return }
        context.coordinator.lastToken = target.token
        guard let page = document.page(at: target.pageIndex) else { return }
        // Let the layout settle first (the pane may have just appeared).
        DispatchQueue.main.async {
            if let range = target.selectionRange, let selection = page.selection(for: range) {
                let bounds = selection.bounds(for: page)
                view.go(to: PDFDestination(page: page, at: CGPoint(x: 0, y: bounds.maxY + 24)))
                selection.color = UIColor.systemYellow.withAlphaComponent(0.45)
                view.highlightedSelections = [selection]
            } else {
                view.go(to: page)
            }
        }
    }
}

/// Example-sheet question navigator and per-question status (design plan §3.7).
struct QuestionBar: View {
    let model: EditorModel

    var body: some View {
        HStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.questions) { question in
                            pill(question)
                                .id(question.number)
                        }
                        Button {
                            model.addQuestion()
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                                .frame(width: 30, height: 30)
                                .background(Theme.surface2, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add a question")
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: model.currentQuestion) { _, q in
                    if let q { withAnimation { proxy.scrollTo(q, anchor: .center) } }
                }
            }
            if let q = model.currentQuestion {
                statusMenu(q)
                    .padding(.trailing, 12)
            }
        }
        .padding(.vertical, 6)
        .background(Theme.surface)
    }

    private func pill(_ question: SheetQuestion) -> some View {
        let isCurrent = model.currentQuestion == question.number
        return Button {
            model.goToQuestion(question.number)
        } label: {
            HStack(spacing: 4) {
                if question.status == .stuck { Image(systemName: "flag.fill").font(.caption2) }
                if question.status == .done { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
                Text("Q\(question.number)").font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(isCurrent ? Color.white : question.status.tint)
            .background(isCurrent ? question.status.tint : question.status.tint.opacity(0.13), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Question \(question.number), \(question.status.displayName)")
    }

    private func statusMenu(_ q: Int) -> some View {
        let status = model.status(of: q)
        return Menu {
            ForEach(QuestionStatus.allCases, id: \.self) { s in
                Button {
                    model.setStatus(s, for: q)
                } label: {
                    Label(s.displayName, systemImage: s.symbol)
                }
            }
        } label: {
            Label("Q\(q): \(status.displayName)", systemImage: status.symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .foregroundStyle(status.tint)
                .background(status.tint.opacity(0.13), in: Capsule())
        }
    }
}

extension QuestionStatus {
    var tint: Color {
        switch self {
        case .notStarted: return Theme.ink2
        case .attempted: return Theme.hard
        case .done: return Theme.good
        case .stuck: return Theme.again
        }
    }

    var symbol: String {
        switch self {
        case .notStarted: return "circle"
        case .attempted: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        case .stuck: return "flag.fill"
        }
    }
}
