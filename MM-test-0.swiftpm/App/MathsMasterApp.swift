import SwiftUI

@main
struct MathsMasterApp: App {
    @State private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .task { await library.start() }
        }
    }
}

/// Chooses between first-run, loading, error and the main split view.
struct RootView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Group {
            switch library.phase {
            case .starting, .loading:
                ProgressView("Opening your library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            case .needsFolder:
                WelcomeView()
            case .ready:
                MainSplitView()
            case .failed(let message):
                LibraryErrorView(message: message)
            }
        }
        .tint(Theme.accent)
    }
}

struct LibraryErrorView: View {
    @Environment(LibraryStore.self) private var library
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't open the library", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { Task { await library.start() } }
            Button("Choose a different folder") { library.forgetFolder() }
        }
        .background(Theme.background)
    }
}
