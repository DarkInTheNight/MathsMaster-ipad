import SwiftUI

/// Full-screen destinations pushed over the split view (design plan §2.2).
/// Pushing any route hides the sidebar; popping restores it.
///
/// Seams:
/// - `.document` → `DocumentEditorView` (workstream B owns Features/Editor)
/// - `.review` / `.cardBrowser` → `ReviewSessionView` / `CardBrowserView` (workstream C owns Features/Review, Features/Cards)
enum AppRoute: Hashable {
    case document(DocumentSummary)
    case review(ReviewScope)
    case cardBrowser(courseID: UUID?)
}

enum ReviewScope: Hashable {
    case all
    case course(UUID)
}

struct RouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .document(let document):
            DocumentEditorView(document: document)
        case .review(let scope):
            ReviewSessionView(scope: scope)
        case .cardBrowser(let courseID):
            CardBrowserView(courseID: courseID)
        }
    }
}

/// Lets any view push a route: `@Environment(\.openRoute) var openRoute; openRoute(.review(.all))`.
struct OpenRouteAction {
    let handler: (AppRoute) -> Void
    func callAsFunction(_ route: AppRoute) { handler(route) }
}

private struct OpenRouteKey: EnvironmentKey {
    static let defaultValue = OpenRouteAction { _ in }
}

extension EnvironmentValues {
    var openRoute: OpenRouteAction {
        get { self[OpenRouteKey.self] }
        set { self[OpenRouteKey.self] = newValue }
    }
}
