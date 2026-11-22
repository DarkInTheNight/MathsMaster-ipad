import SwiftUI

/// A document on a shelf. Real page thumbnails arrive with the editor (workstream B);
/// until then this draws a page-shaped placeholder.
struct DocumentTile: View {
    let document: DocumentSummary
    let colour: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.line)
                    )
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Theme.ink2.opacity(0.6))
                    }
                Rectangle()
                    .fill(colour)
                    .frame(height: 4)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
            }
            .aspectRatio(0.72, contentMode: .fit)
            .shadow(color: .black.opacity(0.06), radius: 5, y: 2)

            Text(document.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(meta)
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private var symbol: String {
        switch document.kind {
        case .lectureNotes: return "doc.richtext"
        case .exampleSheet: return "list.number"
        case .notebook: return "pencil.and.scribble"
        }
    }

    private var meta: String {
        var parts = ["\(document.pageCount) page\(document.pageCount == 1 ? "" : "s")"]
        if let sheet = document.sheet {
            if let date = sheet.supervisionDate {
                parts.append("supervision \(date.date().formatted(.dateTime.day().month(.abbreviated)))")
            }
            if sheet.stuckCount > 0 { parts.append("\(sheet.stuckCount) stuck") }
        }
        return parts.joined(separator: " · ")
    }
}

/// A titled horizontal group of document tiles.
struct DocumentGrid: View {
    let documents: [DocumentSummary]
    let colourFor: (DocumentSummary) -> Color

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 20, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            ForEach(documents) { document in
                NavigationLink(value: AppRoute.document(document)) {
                    DocumentTile(document: document, colour: colourFor(document))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
