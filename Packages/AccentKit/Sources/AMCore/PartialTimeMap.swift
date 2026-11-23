// Partial time map data (plan §4.4). This spec ships the data and its validation; `toModel`, `toYou` and the
// playback lookup are spec 09.

import Foundation

public struct PartialTimeMap: Sendable, Hashable, Codable {
    /// Ordered by model time, then your time.
    public let segments: [Segment]

    public enum Segment: Sendable, Hashable, Codable {
        /// Present (`comparable` true) or substituted (false); monotone piecewise-linear between anchors.
        case mapped(model: TimeRange, you: TimeRange, anchors: [Anchor], comparable: Bool)
        /// A missing word: model speech with no counterpart.
        case modelOnly(model: TimeRange)
        /// An insertion.
        case youOnly(you: TimeRange)

        public var modelRange: TimeRange? {
            switch self {
            case .mapped(let model, _, _, _), .modelOnly(let model): model
            case .youOnly: nil
            }
        }

        public var yourRange: TimeRange? {
            switch self {
            case .mapped(_, let you, _, _), .youOnly(let you): you
            case .modelOnly: nil
            }
        }
    }

    /// A matched instant: a syllable boundary of a present word, or a word edge of a substituted one.
    public struct Anchor: Sendable, Hashable, Codable {
        public let model: Double
        public let you: Double
        public init(model: Double, you: Double) {
            self.model = model
            self.you = you
        }
    }

    public enum Invalid: Error, Equatable {
        /// Segments with model time must not go back or overlap in model time.
        case modelTimeOrderBroken(segment: Int)
        /// Segments with your time must not go back or overlap in your time.
        case yourTimeOrderBroken(segment: Int)
        /// Anchors must lie inside their segment on both timelines.
        case anchorOutsideSegment(segment: Int, anchor: Int)
        /// Anchors must strictly increase on both timelines (the map is monotone).
        case anchorsNotMonotone(segment: Int, anchor: Int)
    }

    public init(segments: [Segment]) throws {
        var modelEnd = -Double.infinity
        var yourEnd = -Double.infinity
        for (s, segment) in segments.enumerated() {
            if let model = segment.modelRange {
                guard model.start >= modelEnd else { throw Invalid.modelTimeOrderBroken(segment: s) }
                modelEnd = model.end
            }
            if let you = segment.yourRange {
                guard you.start >= yourEnd else { throw Invalid.yourTimeOrderBroken(segment: s) }
                yourEnd = you.end
            }
            if case .mapped(let model, let you, let anchors, _) = segment {
                var previous: Anchor?
                for (a, anchor) in anchors.enumerated() {
                    guard model.contains(anchor.model), you.contains(anchor.you) else {
                        throw Invalid.anchorOutsideSegment(segment: s, anchor: a)
                    }
                    if let previous, !(anchor.model > previous.model && anchor.you > previous.you) {
                        throw Invalid.anchorsNotMonotone(segment: s, anchor: a)
                    }
                    previous = anchor
                }
            }
        }
        self.segments = segments
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let segments = try container.decode([Segment].self, forKey: .segments)
        do {
            try self.init(segments: segments)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .segments, in: container, debugDescription: "Invalid PartialTimeMap: \(error)")
        }
    }
}
