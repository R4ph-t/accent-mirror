// Distinct ID types (plan §1, §8.1). Each encodes as its bare raw value in JSON.

import Foundation

/// One analysis request. Stale responses are rejected by request ID plus inputs (§8.1).
public struct RequestID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(UUID.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var description: String { rawValue.uuidString }
}

/// A phrase in the library (starter or imported).
public struct PhraseID: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// One native recording (a model voice) of a phrase.
public struct RecordingID: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// One of your takes.
public struct TakeID: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// The zero-based position of a word in the phrase text.
public struct WordIndex: RawRepresentable, Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public static func < (lhs: WordIndex, rhs: WordIndex) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { String(rawValue) }
}

/// A span of time in seconds on one speaker's own timeline. `start <= end`, both finite.
public struct TimeRange: Sendable, Hashable, Codable {
    public let start: Double
    public let end: Double

    public enum Invalid: Error, Equatable { case notFinite, endBeforeStart }

    public init(start: Double, end: Double) throws {
        guard start.isFinite, end.isFinite else { throw Invalid.notFinite }
        guard start <= end else { throw Invalid.endBeforeStart }
        self.start = start
        self.end = end
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decode(Double.self, forKey: .start)
        let end = try container.decode(Double.self, forKey: .end)
        do {
            try self.init(start: start, end: end)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .end, in: container, debugDescription: "TimeRange needs finite start <= end")
        }
    }

    public var duration: Double { end - start }
    public func contains(_ t: Double) -> Bool { start <= t && t <= end }
}
