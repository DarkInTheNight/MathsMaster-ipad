import SwiftUI

// WORKSTREAM C owns everything in Features/Review and Features/Cards.
//
// Contract with the rest of the app:
// - `ReviewSessionView(scope:)` is pushed full screen by `AppRoute.review`.
// - `ReviewHeroCard()` is the "Review" block at the top of Today.
// - `CourseDeckSummaryView(course:)` is the Cards shelf on a course page.
// - `CardsHomeView()` is the sidebar's Cards destination; `CardBrowserView(courseID:)` is pushed by `AppRoute.cardBrowser`.
// - Deck file: `library.deckURL(course)` → `DeckFile` (Core/Models/Card.swift).
// - Review log: append `ReviewEntry` lines with `JSONCoding.encodeLine` to `library.reviewLogURL()`
//   via `library.fileStore.append(_:to:)`. State is derived by replaying all logs under `Reviews/`.

struct ReviewSessionView: View {
    let scope: ReviewScope

    var body: some View {
        PlaceholderScreen(title: "Review", systemImage: "rectangle.on.rectangle.angled",
                          message: "Flashcard review arrives in the next build.")
    }
}

struct ReviewHeroCard: View {
    var body: some View {
        Panel {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REVIEW").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Theme.accent)
                    Text("Flashcards are coming").font(.title2.bold())
                    Text("Due cards, your streak and Start review will live here.")
                        .foregroundStyle(Theme.ink2)
                }
                Spacer()
                Button {} label: {
                    Label("Start review", systemImage: "play.fill").padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
            }
        }
    }
}
