import SwiftUI

enum SidebarItem: Hashable {
    case today, cards, search, inbox
    case course(UUID)
    case allDocuments, notebooks, exampleSheets
    case settings
}

/// Two columns: sidebar → detail. Documents and reviews push full screen (design plan §2.2).
struct MainSplitView: View {
    @Environment(LibraryStore.self) private var library
    @State private var selection: SidebarItem? = .today
    @State private var path: [AppRoute] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 340)
        } detail: {
            NavigationStack(path: $path) {
                detailRoot
                    .navigationDestination(for: AppRoute.self) { route in
                        RouteDestination(route: route)
                    }
            }
        }
        .onChange(of: selection) {
            path = []
        }
        .onChange(of: path) {
            withAnimation(.snappy) {
                columnVisibility = path.isEmpty ? .automatic : .detailOnly
            }
        }
        .environment(\.openRoute, OpenRouteAction { route in path.append(route) })
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch selection ?? .today {
        case .today:
            TodayView(selection: $selection)
        case .cards:
            CardsHomeView()
        case .search:
            PlaceholderScreen(title: "Search", systemImage: "magnifyingglass",
                              message: "Search across notes, sheets, handwriting and cards is coming soon.")
        case .inbox:
            PlaceholderScreen(title: "Inbox", systemImage: "tray",
                              message: "Cards and changes proposed by Claude will wait here for you to accept.")
        case .course(let id):
            if let course = library.manifest.course(id) {
                CoursePageView(course: course)
            } else {
                PlaceholderScreen(title: "Course not found", systemImage: "questionmark.folder", message: "It may have been removed.")
            }
        case .allDocuments:
            DocumentListView(title: "All documents", kind: nil)
        case .notebooks:
            DocumentListView(title: "Notebooks", kind: .notebook)
        case .exampleSheets:
            DocumentListView(title: "Example sheets", kind: .exampleSheet)
        case .settings:
            SettingsView()
        }
    }
}

struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle(title)
    }
}
