import Foundation

/// Which labels on one line show when they don't all fit (fixes round 5): the syllable labels under a strip row and
/// the word labels under the pitch plot. Pure: positions and widths in, one flag per label out. UI-free on purpose,
/// so it is tested without a window.
///
/// Rules:
/// - Neighbouring labels that show keep at least `minimumGap` (4 pt) between their edges.
/// - `.always` labels (stressed syllables, the mistake marker, target words) always show, even if two of them
///   would touch.
/// - Otherwise `.high` labels (heard and missing words) are placed before `.low` ones (unstressed syllables,
///   non-target words), and within a priority left to right: a label shows
///   only if it keeps the gap to every label already showing.
/// - A label that is hidden still belongs to its row's tooltip and accessibility label (the views do that).
enum LabelLayout {
    static let minimumGap: Double = 4

    enum Priority: Int, Sendable, CaseIterable {
        /// Stressed syllables, the mistake marker, target words.
        case always
        /// Heard words and missing-word labels: hidden only after every `.low` label that would collide.
        case high
        /// Unstressed syllables and non-target words: hidden first.
        case low
    }

    struct Item: Equatable, Sendable {
        /// Horizontal centre of the label, in points.
        var center: Double
        var width: Double
        var priority: Priority
    }

    /// One flag per item, in the items' order: true if the label shows.
    static func visibility(_ items: [Item], gap: Double = minimumGap) -> [Bool] {
        var shown = items.map { $0.priority == .always }
        for priority in [Priority.high, .low] {
            let candidates = items.indices
                .filter { items[$0].priority == priority }
                .sorted { items[$0].center < items[$1].center }
            for index in candidates {
                let fits = items.indices.allSatisfy { other in
                    !shown[other] || !collide(items[index], items[other], gap: gap)
                }
                shown[index] = fits
            }
        }
        return shown
    }

    /// A strip syllable label's priority (Addendum r4 C6): stressed (bold caps or a measured-stressed bar) and the
    /// mistake marker always show; heard words (a substitution in quotes, "+ so") give way after unstressed
    /// syllables; unstressed syllables give way first.
    static func syllablePriority(_ style: ClusterLabel.Style, stressedBar: Bool) -> Priority {
        if stressedBar { return .always }
        switch style {
        case .caps, .mistake: return .always
        case .heard: return .high
        case .lower: return .low
        }
    }

    /// A missing word's struck-through label gives way after unstressed syllables, like a heard word.
    static let missingWordPriority = Priority.high

    /// A pitch word label: target words always show, the others give way first.
    static func wordPriority(isTarget: Bool) -> Priority { isTarget ? .always : .low }

    /// True if the two labels are closer than `gap` edge to edge (or overlap).
    static func collide(_ a: Item, _ b: Item, gap: Double = minimumGap) -> Bool {
        abs(a.center - b.center) < (a.width + b.width) / 2 + gap
    }
}
