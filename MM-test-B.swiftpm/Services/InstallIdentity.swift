import Foundation
import UIKit

/// A stable ID for this app install (Playgrounds and SideStore copies differ).
/// Used to name per-install review logs and log files.
enum InstallIdentity {
    private static let key = "installID"

    static var id: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString.lowercased()
        UserDefaults.standard.set(new, forKey: key)
        return new
    }

    /// e.g. "iPad · com.darkinthenight.mathsmaster"
    @MainActor static var displayName: String {
        "\(UIDevice.current.model) · \(Bundle.main.bundleIdentifier ?? "unknown")"
    }
}
