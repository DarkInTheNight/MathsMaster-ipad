import SwiftUI
import UniformTypeIdentifiers

/// First run: pick (or create) the library folder in iCloud Drive (design plan §7.6).
struct WelcomeView: View {
    @Environment(LibraryStore.self) private var library
    @State private var picking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 60)
                VStack(spacing: 10) {
                    Text("Welcome to MathsMaster")
                        .font(.largeTitle.bold())
                    Text("Your notes, example sheets and flashcards live as ordinary files in one folder you choose. Nothing is locked inside the app.")
                        .font(.title3)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        step("1.circle.fill", "In the picker, open iCloud Drive and create a folder called **MathsMaster** (or choose it if it already exists).")
                        step("2.circle.fill", "Do the same in every copy of the app (Playgrounds and the installed app). They all share this folder.")
                        step("icloud.and.arrow.down", "Tip: in the Files app, long-press the folder and choose **Keep Downloaded** so everything works offline.")
                    }
                }
                .frame(maxWidth: 560)
                Button {
                    picking = true
                } label: {
                    Label("Choose library folder", systemImage: "folder.badge.plus")
                        .font(.headline)
                        .frame(minWidth: 280)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                Task { await library.useFolder(url) }
            case .failure(let error):
                AppLog.shared.error("Folder picker failed: \(error.localizedDescription)")
            }
        }
    }

    private func step(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.accent)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
