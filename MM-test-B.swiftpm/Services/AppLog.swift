import Foundation
import Observation

/// In-app log (there's no Xcode console on the iPad). Keeps the last 500 lines in memory
/// for Settings → Diagnostics and appends to `Logs/<installID>.log` in the library.
@MainActor
@Observable
final class AppLog {
    static let shared = AppLog()

    struct Line: Identifiable, Hashable {
        let id = UUID()
        let date: Date
        let level: Level
        let message: String
    }

    enum Level: String { case info = "INFO", error = "ERROR" }

    private(set) var lines: [Line] = []
    private var fileStore: FileStore?
    private var pending: [String] = []

    func attach(_ store: FileStore) {
        fileStore = store
        flush()
    }

    func info(_ message: String) { add(.info, message) }
    func error(_ message: String) { add(.error, message) }

    var text: String {
        lines.map { "\(Self.format($0.date)) \($0.level.rawValue) \($0.message)" }.joined(separator: "\n")
    }

    private func add(_ level: Level, _ message: String) {
        let line = Line(date: Date(), level: level, message: message)
        lines.append(line)
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
        pending.append("\(Self.format(line.date)) \(level.rawValue) \(message)\n")
        flush()
    }

    private func flush() {
        guard let fileStore, !pending.isEmpty else { return }
        let data = Data(pending.joined().utf8)
        pending.removeAll()
        let url = fileStore.url("\(LibraryLayout.logsDir)/\(InstallIdentity.id).log")
        Task.detached { try? await fileStore.append(data, to: url) }
    }

    private static func format(_ date: Date) -> String {
        date.ISO8601Format()
    }
}
