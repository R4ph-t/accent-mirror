import SwiftUI

/// "STRESS AND RHYTHM" (§8): NATIVE above, YOU below, mirrored waveform bars per syllable on each speaker's own
/// timeline. 216 pt tall: 16 + 16 title + 8 + (56 row + 24 labels) + 4 + (56 + 24) + 12.
struct StripCard: View {
    @Environment(\.palette) private var palette
    var strip: StripPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("STRESS AND RHYTHM")
                    .typeRole(.mono)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                HStack(spacing: 6) {
                    LimeBarsGlyph(heights: LimeBarsGlyph.legendHeights, barWidth: 2, pitch: 3.5)
                    Text("Stressed")
                        .typeRole(.small)
                        .foregroundStyle(palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            .frame(height: 16)
            .padding(.bottom, 8)

            StripRow(label: "NATIVE") {
                BarsCanvas(clusters: strip.native, rowHeight: 56)
            } labels: {
                ClusterLabels(clusters: strip.native, slots: [])
            }
            .padding(.bottom, 4)

            StripRow(label: "YOU") { youRow } labels: { youLabels }
        }
        .padding(.horizontal, Metrics.outer)
        .padding(.top, Metrics.outer)
        .padding(.bottom, 12)
        .frame(height: 216, alignment: .top)
        .frame(maxWidth: .infinity)
        .surface(palette.surfaceCard, cornerRadius: Metrics.cardRadius)
    }

    @ViewBuilder private var youRow: some View {
        switch strip.you {
        case .placeholder:
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(palette.baseline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                Text(Copy.yourTakeAppearsHere)
                    .typeRole(.body)
                    .foregroundStyle(palette.textTertiary)
            }
        case .recording(let clusters, let playhead):
            RecordingRow(clusters: clusters, playhead: playhead)
        case .takeProblem(let clusters, let shape, let caption):
            TakeProblemRow(clusters: clusters, shape: shape, caption: caption)
        case .bars(let clusters, let slots, _):
            ZStack {
                BarsCanvas(clusters: clusters, rowHeight: 56)
                MissingSlots(slots: slots)
            }
        }
    }

    @ViewBuilder private var youLabels: some View {
        switch strip.you {
        case .bars(let clusters, let slots, let showsLabels) where showsLabels:
            ClusterLabels(clusters: clusters, slots: slots)
        default:
            Color.clear
        }
    }
}

/// Row label column (64), the plot column, then the 8 + 48 end-label column.
private struct StripRow<Plot: View, Labels: View>: View {
    @Environment(\.palette) private var palette
    var label: String
    @ViewBuilder var plot: Plot
    @ViewBuilder var labels: Labels

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .typeRole(.mono)
                .foregroundStyle(palette.textTertiary)
                .frame(width: Metrics.rowLabelWidth, height: 56, alignment: .leading)
            VStack(spacing: 0) {
                plot.frame(height: 56)
                labels.frame(height: 24)
            }
            Spacer().frame(width: Metrics.inner + Metrics.endLabelWidth)
        }
        .frame(height: 80)
    }
}

// MARK: - Bars

/// Deterministic per-bar jitter so the texture is identical on every render.
func barJitter(_ seed: Int, _ index: Int) -> Double {
    var x = UInt64(truncatingIfNeeded: seed &* 73_856_093 ^ index &* 19_349_663) &+ 0x9E37_79B9_7F4A_7C15
    x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
    x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
    x ^= x >> 31
    return Double(x % 10_000) / 10_000
}

/// Bar heights for one syllable cluster: its envelope scaled by measured prominence.
func clusterBars(_ cluster: StripCluster, width: CGFloat, maxHeight: CGFloat, pitch: CGFloat = 3,
                 minHeight: CGFloat = 1.5) -> [(x: CGFloat, height: CGFloat)] {
    let x0 = CGFloat(cluster.start) * width + 2
    let x1 = CGFloat(cluster.end) * width - 2
    guard x1 > x0 else { return [] }
    let count = Int((x1 - x0) / pitch) + 1
    return (0..<count).map { index in
        let u = (Double(index) + 0.5) / Double(count)
        let envelope = pow(sin(Double.pi * u), 0.8)
        let jitter = 0.55 + 0.45 * barJitter(cluster.seed, index)
        let height = max(minHeight, maxHeight * CGFloat(cluster.prominence * envelope * jitter))
        return (x0 + CGFloat(index) * pitch, height)
    }
}

struct BarsCanvas: View {
    @Environment(\.palette) private var palette
    var clusters: [StripCluster]
    var rowHeight: CGFloat
    /// Bars past this point on the timeline are not drawn (recording).
    var clipAt: Double = 1

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            for cluster in clusters where cluster.start < clipAt {
                for bar in clusterBars(cluster, width: size.width, maxHeight: rowHeight - 4)
                where bar.x < CGFloat(clipAt) * size.width {
                    let rect = CGRect(x: bar.x, y: midY - bar.height / 2, width: 1.5, height: bar.height)
                    let path = Path(roundedRect: rect, cornerRadius: 0.75)
                    switch cluster.fill {
                    case .stressed:
                        context.fill(path, with: .linearGradient(
                            Gradient(colors: [palette.lime2, palette.lime1, palette.lime2]),
                            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)
                        ))
                    case .neutral:
                        context.fill(path, with: .color(palette.stripBar))
                    case .yours:
                        context.fill(path, with: .color(palette.stripBarYou))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct RecordingRow: View {
    @Environment(\.palette) private var palette
    var clusters: [StripCluster]
    var playhead: Double

    var body: some View {
        GeometryReader { proxy in
            let x = CGFloat(playhead) * proxy.size.width
            ZStack(alignment: .topLeading) {
                BarsCanvas(clusters: clusters, rowHeight: 56, clipAt: playhead)
                Rectangle()
                    .fill(palette.baseline)
                    .frame(width: max(0, proxy.size.width - x), height: 1)
                    .offset(x: x, y: proxy.size.height / 2)
                // The 2 pt Lime playhead: one of the three places Lime appears while recording (A3).
                Rectangle()
                    .fill(palette.lime1)
                    .frame(width: 2, height: proxy.size.height + 4)
                    .offset(x: x - 1, y: -2)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Your take, recording")
    }
}

/// Your row for a take problem with audio (§7.1, mockup-error-final2): the take's syllables as strip.bar
/// clusters, flattened to a near-silent line (too quiet), cut flat at the top (clipped) or as heard (plain), with
/// the caption centred under it.
private struct TakeProblemRow: View {
    @Environment(\.palette) private var palette
    var clusters: [StripCluster]
    var shape: TakeProblemShape
    var caption: String?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let midY = size.height / 2
                for cluster in clusters {
                    for bar in bars(cluster, width: size.width, rowHeight: size.height) {
                        let rect = CGRect(x: bar.x, y: midY - bar.height / 2, width: 1.5, height: bar.height)
                        context.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(palette.stripBar))
                    }
                }
            }
            if let caption {
                Text(caption)
                    .typeRole(.small)
                    .foregroundStyle(palette.textSecondary)
                    // Just under the near-silent line, as in the mockup; under a full-height waveform it moves
                    // down into the label line so it never sits on the bars.
                    .position(x: proxy.size.width / 2, y: shape == .nearSilent ? proxy.size.height / 2 + 14 : proxy.size.height + 12)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(caption ?? "Your take")
    }

    private func bars(_ cluster: StripCluster, width: CGFloat, rowHeight: CGFloat) -> [(x: CGFloat, height: CGFloat)] {
        switch shape {
        case .nearSilent:
            // 2 to 4 pt: the syllables still read as groups and the loudest swell a little, but there is almost
            // nothing there (mockup-error-final2).
            let loudest = clusters.map(\.prominence).max() ?? 1
            var relative = cluster
            relative.prominence = loudest > 0 ? cluster.prominence / loudest : 0
            return clusterBars(relative, width: width, maxHeight: 2.5).map { ($0.x, 2 + $0.height * 0.8) }
        case .clipped:
            // Driven past the ceiling, so most bars stop at the same flat top.
            let ceiling = (rowHeight - 4) * 0.5
            var loud = cluster
            loud.prominence = 1
            return clusterBars(loud, width: width, maxHeight: (rowHeight - 4) * 1.6)
                .map { ($0.x, min($0.height, ceiling)) }
        case .plain:
            return clusterBars(cluster, width: width, maxHeight: rowHeight - 4)
        }
    }
}

private struct MissingSlots: View {
    @Environment(\.palette) private var palette
    var slots: [MissingSlot]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                // A 24 pt empty slot, 1 pt dashed hairline outline, radius 4 (§8.2).
                RoundedRectangle(cornerRadius: Metrics.markRadius, style: .continuous)
                    .strokeBorder(palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 24, height: 28)
                    .position(x: CGFloat(slot.position) * proxy.size.width, y: proxy.size.height / 2)
                    .help(Copy.missingTooltip)
            }
        }
    }
}

// MARK: - Labels

/// One row's labels: a syllable label centred under each cluster, and the struck-through expected word over each
/// missing slot. When they don't all fit with 4 pt between them, `LabelLayout` hides unstressed syllables first;
/// stressed syllables and the mistake marker always show. A hidden label keeps a tooltip over its syllable, and the
/// row's accessibility label reads every label (fixes round 5).
private struct ClusterLabels: View {
    @Environment(\.palette) private var palette
    var clusters: [StripCluster]
    var slots: [MissingSlot]

    private enum Content {
        case syllable(ClusterLabel, tooltip: String?)
        case missing(String)
    }

    private struct Entry {
        var content: Content
        var center: CGFloat
        /// Width of the syllable's own span: a hidden label's tooltip area never reaches past it.
        var span: CGFloat
        var width: CGFloat
        var priority: LabelLayout.Priority
        var spoken: String
        var tooltip: String
    }

    var body: some View {
        GeometryReader { proxy in
            let entries = entries(width: proxy.size.width)
            let shown = LabelLayout.visibility(entries.map {
                LabelLayout.Item(center: $0.center, width: $0.width, priority: $0.priority)
            })
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                if shown[index] {
                    label(entry).position(x: entry.center, y: proxy.size.height / 2)
                } else {
                    Color.clear
                        .frame(width: max(8, min(entry.width, entry.span)), height: proxy.size.height)
                        .contentShape(Rectangle())
                        .help(entry.tooltip)
                        .position(x: entry.center, y: proxy.size.height / 2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.labelLine(entries(width: 0).map(\.spoken)))
    }

    @ViewBuilder private func label(_ entry: Entry) -> some View {
        switch entry.content {
        case .syllable(let label, let tooltip):
            LabelView(label: label)
                .fixedSize()
                .help(tooltip ?? "")
        case .missing(let expected):
            // The expected word, struck through, in tertiary: only for missing words.
            Text(expected)
                .typeRole(.small)
                .strikethrough(true, color: palette.textTertiary)
                .foregroundStyle(palette.textTertiary)
                .fixedSize()
                .help(Copy.missingTooltip)
        }
    }

    /// Clusters and missing slots in timeline order, with their measured widths and priorities.
    private func entries(width: CGFloat) -> [Entry] {
        let syllables: [Entry] = clusters.compactMap { cluster in
            guard let label = cluster.label else { return nil }
            return Entry(
                content: .syllable(label, tooltip: cluster.tooltip),
                center: CGFloat((cluster.start + cluster.end) / 2) * width,
                span: CGFloat(cluster.end - cluster.start) * width,
                width: LabelView.width(label),
                priority: LabelLayout.syllablePriority(label.style, stressedBar: cluster.fill == .stressed),
                spoken: label.style == .mistake ? Copy.mistakeLabelAccessibility(label.text) : label.text,
                tooltip: Copy.hiddenLabelTooltip(label.text, note: cluster.tooltip)
            )
        }
        let missing: [Entry] = slots.map { slot in
            Entry(
                content: .missing(slot.expected),
                center: CGFloat(slot.position) * width,
                span: 24,
                width: TextMeasure.width(slot.expected, role: .small),
                priority: LabelLayout.missingWordPriority,
                spoken: Copy.hiddenLabelTooltip(slot.expected, note: Copy.missingTooltip),
                tooltip: Copy.hiddenLabelTooltip(slot.expected, note: Copy.missingTooltip)
            )
        }
        return (syllables + missing).sorted { $0.center < $1.center }
    }
}

private struct LabelView: View {
    @Environment(\.palette) private var palette
    var label: ClusterLabel

    var body: some View {
        switch label.style {
        case .caps:
            Text(label.text)
                .typeRole(.smallBold)
                .foregroundStyle(palette.textPrimary)
        case .lower:
            Text(label.text)
                .typeRole(.small)
                .foregroundStyle(palette.textSecondary)
        case .heard:
            Text(label.text)
                .typeRole(.small, italic: true)
                .foregroundStyle(palette.textSecondary)
        case .mistake:
            // Always three cues together: blue, a filled triangle, a 2 pt dotted underline 3 pt below (§4.3).
            HStack(spacing: 4) {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(label.text)
                    .typeRole(.smallBold)
                    .overlay(alignment: .bottom) {
                        DottedUnderline()
                            .frame(height: 2)
                            .offset(y: 5)
                    }
            }
            .foregroundStyle(palette.mistake)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.mistakeLabelAccessibility(label.text))
        }
    }

    /// The label's drawn width, for `LabelLayout`: the mistake marker adds its 8 pt triangle and 4 pt spacing.
    static func width(_ label: ClusterLabel) -> CGFloat {
        switch label.style {
        case .caps: TextMeasure.width(label.text, role: .smallBold)
        case .lower: TextMeasure.width(label.text, role: .small)
        case .heard: TextMeasure.width(label.text, role: .small, italic: true)
        case .mistake: TextMeasure.width(label.text, role: .smallBold) + mistakeGlyphWidth + 4
        }
    }

    /// The bold 8 pt `triangle.fill` symbol is about 9 pt wide.
    static let mistakeGlyphWidth: CGFloat = 9
}

private struct DottedUnderline: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                context.fill(Path(ellipseIn: CGRect(x: x, y: 0, width: 2, height: 2)), with: .foreground)
                x += 3.5
            }
        }
    }
}
