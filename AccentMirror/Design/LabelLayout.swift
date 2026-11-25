import Foundation

/// Which labels on one line show when they don't all fit (fixes round 5): the syllable labels under a strip row and
/// the word labels under the pitch plot. Pure: positions and widths in, one flag per label out. UI-free on purpose,
/// so it is tested without a window.
///
/// Rules:
/// - Neighbouring labels that show keep at least `minimumGap` (4 pt) between their edges.
/// - `.always` labels (dictionary-stressed native syllables, target words) always show, even if two of them
///   would touch.
/// - Otherwise `.high` labels (heard and missing words) are placed before `.low` ones (unstressed syllables,
///   non-target words), and within a priority left to right: a label shows
///   only if it keeps the gap to every label already showing.
/// - A label that is hidden still belongs to its row's tooltip and accessibility label (the views do that).
enum LabelLayout {
    static let minimumGap: Double = 4

    enum Priority: Int, Sendable, CaseIterable {
        /// Dictionary-stressed native syllables (bold caps), target words.
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

    struct Placed: Equatable, Sendable {
        var center: Double
        var shown: Bool
    }

    /// Clamps labels inside `0...width`, nudges minor overlaps locally into adjacent free room (keeping `.always`
    /// labels anchored near their syllables), and then runs `visibility` so any remaining crowd hides by priority.
    static func place(_ items: [Item], within width: Double, gap: Double = minimumGap) -> [Placed] {
        guard !items.isEmpty else { return [] }
        guard width > 0 else {
            return zip(items, visibility(items, gap: gap)).map { Placed(center: $0.center, shown: $1) }
        }

        let order = items.indices.sorted { items[$0].center < items[$1].center }
        var clamped = items
        for index in items.indices {
            let lo = min(width / 2, items[index].width / 2)
            let hi = max(width / 2, width - items[index].width / 2)
            clamped[index].center = min(hi, max(lo, items[index].center))
        }

        let orderedWidths = order.map { clamped[$0].width }
        let totalRequired = orderedWidths.reduce(0, +) + Double(max(0, order.count - 1)) * gap
        var resolved = clamped

        if totalRequired <= width {
            let n = order.count
            var offset = [Double](repeating: 0, count: n)
            for k in 1..<n {
                offset[k] = offset[k - 1] + (orderedWidths[k - 1] + orderedWidths[k]) / 2 + gap
            }
            let minZ = orderedWidths[0] / 2
            let maxZ = (width - orderedWidths[n - 1] / 2) - offset[n - 1]

            struct Block {
                var sumWY: Double
                var sumW: Double
                var count: Int
                var mean: Double { sumWY / sumW }
            }
            var blocks: [Block] = []
            for k in 0..<n {
                let item = clamped[order[k]]
                let weight: Double = switch item.priority {
                case .always: 100
                case .high: 10
                case .low: 1
                }
                let y = min(maxZ, max(minZ, item.center - offset[k]))
                blocks.append(Block(sumWY: weight * y, sumW: weight, count: 1))
                while blocks.count >= 2 && blocks[blocks.count - 2].mean > blocks[blocks.count - 1].mean {
                    let tail = blocks.removeLast()
                    blocks[blocks.count - 1].sumWY += tail.sumWY
                    blocks[blocks.count - 1].sumW += tail.sumW
                    blocks[blocks.count - 1].count += tail.count
                }
            }
            var z: [Double] = []
            z.reserveCapacity(n)
            for block in blocks {
                let value = min(maxZ, max(minZ, block.mean))
                for _ in 0..<block.count { z.append(value) }
            }
            let candidates = (0..<n).map { z[$0] + offset[$0] }
            for (k, index) in order.enumerated() {
                resolved[index].center = candidates[k]
            }
        }

        let shown = visibility(resolved, gap: gap)
        return zip(resolved, shown).map { Placed(center: $0.center, shown: $1) }
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

    /// A strip syllable label's priority (Addendum r4 C6, v3.1): the dotted bold caps always show; heard words (a
    /// substitution in quotes, "+ so") give way after plain syllables; plain syllables (yours included) give way first.
    static func syllablePriority(_ style: ClusterLabel.Style) -> Priority {
        switch style {
        case .caps: .always
        case .heard: .high
        case .lower, .yours, .merged: .low
        }
    }

    /// A missing word's label gives way after unstressed syllables, like a heard word.
    static let missingWordPriority = Priority.high

    /// A pitch word label: target words always show, the others give way first.
    static func wordPriority(isTarget: Bool) -> Priority { isTarget ? .always : .low }

    /// True if the two labels are closer than `gap` edge to edge (or overlap).
    static func collide(_ a: Item, _ b: Item, gap: Double = minimumGap) -> Bool {
        abs(a.center - b.center) < (a.width + b.width) / 2 + gap - 1e-9
    }
}
