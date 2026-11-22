import Foundation

/// Shared JSON settings: stable key order (clean diffs and backups), ISO-8601 dates.
enum JSONCoding {
    static func encoder(pretty: Bool = true) -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func encode<T: Encodable>(_ value: T, pretty: Bool = true) throws -> Data {
        try encoder(pretty: pretty).encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }

    /// One compact JSON object per line (review logs).
    static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder(pretty: false).encode(value)
        data.append(0x0A)
        return data
    }

    /// Decodes a JSON-lines file, skipping blank or corrupt lines (a half-synced last line must not lose the rest).
    static func decodeLines<T: Decodable>(_ type: T.Type, from data: Data) -> [T] {
        let d = decoder()
        return data.split(separator: 0x0A, omittingEmptySubsequences: true).compactMap { try? d.decode(type, from: Data($0)) }
    }
}
