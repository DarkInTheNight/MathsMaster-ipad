import Foundation
import PDFKit

/// All file I/O on the library folder goes through here (design plan §7.4):
/// coordinated reads and writes (iCloud Drive safe), atomic replace, JSON helpers.
/// URLs passed in must be inside `root`.
actor FileStore {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    nonisolated func url(_ relativePath: String) -> URL {
        relativePath.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    nonisolated func relativePath(of url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: Reading

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func readData(at url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    func readJSON<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        try JSONCoding.decode(type, from: readData(at: url))
    }

    /// Lists a directory. iCloud placeholders (`.name.icloud`) are reported under their real
    /// name and a download is requested, so evicted files still show up.
    func listDirectory(_ url: URL) throws -> [URL] {
        guard exists(url) else { return [] }
        let items = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [])
        var result: [URL] = []
        for item in items {
            let name = item.lastPathComponent
            if let real = LibraryLayout.realNameForICloudPlaceholder(name) {
                let realURL = url.appendingPathComponent(real)
                try? FileManager.default.startDownloadingUbiquitousItem(at: realURL)
                result.append(realURL)
            } else if !name.hasPrefix(".") {
                result.append(item)
            }
        }
        return result.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    // MARK: Writing

    func ensureDirectory(_ url: URL) throws {
        if !isDirectory(url) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Coordinated, atomic write (temp file + replace).
    func writeData(_ data: Data, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            do { try data.write(to: writeURL, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try writeData(JSONCoding.encode(value), to: url)
    }

    /// Appends to a file (creating it if needed). For append-only logs.
    func append(_ data: Data, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { writeURL in
            do {
                if FileManager.default.fileExists(atPath: writeURL.path) {
                    let handle = try FileHandle(forWritingTo: writeURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: writeURL, options: .atomic)
                }
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    /// Copies a file into the library (e.g. an imported PDF), picking a free name. Returns the destination.
    func importFile(from source: URL, into directory: URL, preferredName: String? = nil) throws -> URL {
        try ensureDirectory(directory)
        let destination = freeURL(in: directory, name: preferredName ?? source.lastPathComponent)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: [], writingItemAt: destination, options: .forReplacing, error: &coordinationError) { readURL, writeURL in
            do { try FileManager.default.copyItem(at: readURL, to: writeURL) } catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return destination
    }

    /// Moves an item to `.trash/<timestamp> <name>` (purged after 30 days, design plan §7.2).
    func moveToTrash(_ url: URL) throws {
        let trash = self.url(LibraryLayout.trashDir)
        try ensureDirectory(trash)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = freeURL(in: trash, name: "\(stamp) \(url.lastPathComponent)")
        var coordinationError: NSError?
        var moveError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMoving, writingItemAt: destination, options: .forReplacing, error: &coordinationError) { from, to in
            do { try FileManager.default.moveItem(at: from, to: to) } catch { moveError = error }
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
    }

    private func freeURL(in directory: URL, name: String) -> URL {
        let base = LibraryLayout.stripExtension(name)
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    // MARK: PDFs

    /// Page sizes of a PDF (points), read under coordination.
    func pdfPageSizes(_ url: URL) throws -> [PageSize] {
        let data = try readData(at: url)
        guard let document = PDFDocument(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        return (0..<document.pageCount).map { index in
            let bounds = document.page(at: index)?.bounds(for: .mediaBox) ?? .zero
            return bounds.width > 0 ? PageSize(width: Double(bounds.width), height: Double(bounds.height)) : .a4Portrait
        }
    }
}
