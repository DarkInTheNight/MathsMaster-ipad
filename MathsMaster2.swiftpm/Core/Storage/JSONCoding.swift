import Foundation

/// Shared JSON settings: stable key order (clean diffs and backups), ISO-8601 dates.
enum JSONCoding {
    static func encoder(pretty: Bool = true) -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// Reads ISO-8601 dates with or without fractional seconds (the VPS's Anki import writes `…T03:30:40.395Z`).
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = parseISODate(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO-8601 date: \(string)")
        }
        return d
    }

    private static let plainISO = ISO8601DateFormatter()
    private static let fractionalISO: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseISODate(_ string: String) -> Date? {
        plainISO.date(from: string) ?? fractionalISO.date(from: string)
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
