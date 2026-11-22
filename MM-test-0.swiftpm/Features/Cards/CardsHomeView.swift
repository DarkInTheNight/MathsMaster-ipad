import SwiftUI

// WORKSTREAM C: see Features/Review/ReviewSessionView.swift for the contract.

struct CardsHomeView: View {
    var body: some View {
        PlaceholderScreen(title: "Cards", systemImage: "rectangle.on.rectangle.angled",
                          message: "Decks, the card browser and stats arrive in the next build.")
    }
}

struct CardBrowserView: View {
    let courseID: UUID?

    var body: some View {
        PlaceholderScreen(title: "Card browser", systemImage: "list.bullet.rectangle",
                          message: "Browse and edit cards here soon.")
    }
}

struct CourseDeckSummaryView: View {
    let course: Course

    var body: some View {
        Panel {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(course.colour.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(course.name) deck").font(.headline)
                    Text("Your cards for this course, and your imported Anki deck, will appear here.")
                        .foregroundStyle(Theme.ink2)
                }
            }
        }
    }
}
