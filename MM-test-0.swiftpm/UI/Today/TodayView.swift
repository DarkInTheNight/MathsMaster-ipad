import SwiftUI

/// The launch screen: what to do now (design plan §2.3).
struct TodayView: View {
    @Environment(LibraryStore.self) private var library
    @Binding var selection: SidebarItem?
    @State private var showingAddCourses = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today").font(.largeTitle.bold())
                    Text(subtitle).font(.title3).foregroundStyle(Theme.ink2)
                }

                if library.manifest.courses.isEmpty {
                    gettingStarted
                }

                ReviewHeroCard()

                upNext

                continueSection
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .sheet(isPresented: $showingAddCourses) { AddCoursesSheet() }
    }

    private var subtitle: String {
        let date = Date().formatted(.dateTime.weekday(.wide).day().month(.wide))
        if let position = library.termPosition {
            return "\(date) · \(position.label)"
        }
        return date
    }

    private var gettingStarted: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Set up your courses", systemImage: "graduationcap")
                    .font(.headline)
                Text("Pick your Part IB courses to create a folder for each one, then import lecture notes and example sheets.")
                    .foregroundStyle(Theme.ink2)
                Button("Add courses") { showingAddCourses = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Up next").font(.title2.bold())
            Panel {
                let upcoming = library.upcomingSheets.prefix(4)
                if upcoming.isEmpty {
                    Text("No supervisions or hand-ins yet. Dates you add to example sheets show up here.")
                        .foregroundStyle(Theme.ink2)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(upcoming)) { item in
                            NavigationLink(value: AppRoute.document(item.document)) {
                                HStack(spacing: 14) {
                                    RoundedRectangle(cornerRadius: 2.5)
                                        .fill(colour(for: item.document))
                                        .frame(width: 5, height: 40)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(courseName(item.document)) · \(item.document.title)")
                                            .font(.headline)
                                        Text(detail(item))
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.ink2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.ink2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue").font(.title2.bold())
            let recent = Array(library.recentDocuments.prefix(6))
            if recent.isEmpty {
                Panel {
                    Text("Documents you open appear here so you can jump straight back in.")
                        .foregroundStyle(Theme.ink2)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(recent) { document in
                            NavigationLink(value: AppRoute.document(document)) {
                                DocumentTile(document: document, colour: colour(for: document))
                                    .frame(width: 150)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func courseName(_ document: DocumentSummary) -> String {
        library.course(of: document)?.name ?? ""
    }

    private func colour(for document: DocumentSummary) -> Color {
        library.course(of: document)?.colour.color ?? Theme.accent
    }

    private func detail(_ item: UpcomingSheet) -> String {
        let when = item.date.date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        var parts = ["\(item.isSupervision ? "Supervision" : "Hand-in") \(when)"]
        if let sheet = item.document.sheet {
            if sheet.stuckCount > 0 { parts.append("⚑ \(sheet.stuckCount) stuck") }
            if !sheet.questions.isEmpty { parts.append("\(sheet.doneCount) of \(sheet.questions.count) done") }
        }
        return parts.joined(separator: " · ")
    }
}
