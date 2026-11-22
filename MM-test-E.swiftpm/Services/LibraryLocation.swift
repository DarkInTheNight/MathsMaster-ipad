import Foundation

/// Remembers the user-picked library folder with a security-scoped bookmark (design plan §7.6).
/// Each app copy (Playgrounds, SideStore) keeps its own bookmark in its own sandbox.
@MainActor
final class LibraryLocation {
    private let defaultsKey = "libraryFolderBookmark"
    private(set) var accessedURL: URL?

    var hasBookmark: Bool { UserDefaults.standard.data(forKey: defaultsKey) != nil }

    /// Resolves the saved bookmark and starts security-scoped access. Nil if none or unusable.
    func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            AppLog.shared.error("Library bookmark could not be resolved")
            return nil
        }
        startAccess(url)
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: defaultsKey)
            AppLog.shared.info("Refreshed stale library bookmark")
        }
        return url
    }

    /// Saves a folder chosen in the document picker.
    func save(pickedFolder url: URL) throws {
        startAccess(url)
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    func forget() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private func startAccess(_ url: URL) {
        if let accessedURL, accessedURL != url {
            accessedURL.stopAccessingSecurityScopedResource()
        }
        _ = url.startAccessingSecurityScopedResource()
        accessedURL = url
    }
}
