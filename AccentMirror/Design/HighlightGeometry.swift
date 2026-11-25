import Foundation

/// The hover or loop box on a strip row (r6 E3, v3.2 W5). Pure, so it is tested without a window.
enum HighlightGeometry {
    /// The box's outset around the word's labels, and the label line's height (the box fills the 24 pt label row).
    static let outset: Double = 4
    static let labelHeight: Double = 16

    /// One rounded rectangle 4 pt outside the union of one word's syllable labels on a row (`center`, `width`: a
    /// hidden label counts with what's left of it, its syllable's span). nil when the word has no label on the row.
    static func box(_ labels: [(center: Double, width: Double)]) -> (minX: Double, maxX: Double, height: Double)? {
        guard let minX = labels.map({ $0.center - $0.width / 2 }).min(),
              let maxX = labels.map({ $0.center + $0.width / 2 }).max()
        else { return nil }
        return (minX - outset, maxX + outset, labelHeight + 2 * outset)
    }
}
