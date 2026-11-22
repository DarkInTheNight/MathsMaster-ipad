import Foundation

/// `settings.json`: shared, non-secret settings (secrets live in each app copy's Keychain).
struct LibrarySettings: Codable, Hashable, Sendable {
    static let currentSchema = 1
    var schemaVersion: Int = LibrarySettings.currentSchema
    var newCardsPerDay: Int = 15
    var desiredRetention: Double = 0.90
    var defaultTemplate: PageTemplate = .default
    /// VPS base URL, e.g. "https://maths.example.com" (the token is in the Keychain).
    var vpsURL: String?
}

/// `devices.json`: install IDs → human names, so logs and conflicts can say where an edit came from.
struct DevicesFile: Codable, Hashable, Sendable {
    var devices: [String: String] = [:]
}
