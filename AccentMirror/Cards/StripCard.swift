import SwiftUI

/// "STRESS AND RHYTHM" (§8, v3 §3.2, v3.1 V1–V3): NATIVE above, YOU below, mirrored waveform bars per syllable on
/// each speaker's own timeline, all in strip.bar. The native row's dictionary-stressed syllables get bold caps and a
/// Lime dot; your labels are plain. Timing connectors join each native syllable to yours. 216 pt tall:
/// 16 + 16 title + 8 + (56 row + 24 labels) + 4 + (56 + 24) + 12.
///
/// Spec 20 adds the motion on top, all from `StripChart`: the live recording row, the 1 pt playhead on each row's own
/// timeline, the outline on the syllable being played, the hover and loop boxes behind the labels, and the header's "Playing …" or
/// "Looping …" note.
struct StripCard: View {
    @Environment(\.palette) private var palette
    var chart: StripChart
    /// Clicking a missing word plays the model only.
    var playModel: () -> Void = {}
    /// Clicking a label loops that word (v3 §3.5) until Esc.
    var loop: (Int) -> Void = { _ in }
    /// The pointer entered (a word index) or left (nil) a label.
    var hover: (Int?) -> Void = { _ in }

    private var strip: StripPresentation { chart.strip }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("STRESS AND RHYTHM")
                    .typeRole(.mono)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                if let note = chart.header {
                    HeaderNote(note: note)
                        .padding(.trailing, 16)
                }
                HStack(spacing: 6) {
                    StressDot()
                    Text(Copy.dictionaryStress)
                        .typeRole(.small)
                        .foregroundStyle(palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            .frame(height: 16)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 0) {
                StripRow(label: "NATIVE") {
                    ZStack {
                        BarsCanvas(clusters: strip.native, rowHeight: 56)
                        SyllableOutline(cluster: chart.playing.native.flatMap {
                            strip.native.indices.contains($0) ? strip.native[$0] : nil
                        })
                        Playhead(progress: chart.playhead?.native)
                    }
                } labels: {
                    ClusterLabels(clusters: strip.native, slots: [], highlight: chart.highlight, playModel: playModel,
                                  loop: loop, hover: hover)
                }
                .padding(.bottom, StripGeometry.rowGap)

                StripRow(label: "YOU") { youRow } labels: { youLabels }
            }
            .overlay(alignment: .topLeading) {
                Connectors(connectors: strip.connectors)
            }
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
        case .recording(let envelope):
            LiveRecordingRow(envelope: envelope, modelSeconds: chart.modelSeconds)
        case .takeProblem(let clusters, let shape, let caption):
            TakeProblemRow(clusters: clusters, shape: shape, caption: caption)
        case .bars(let clusters, let slots, _):
            ZStack {
                BarsCanvas(clusters: clusters, rowHeight: 56)
                MissingSlots(slots: slots, playModel: playModel)
                SyllableOutline(cluster: chart.playing.you.flatMap { clusters.indices.contains($0) ? clusters[$0] : nil })
                Playhead(progress: chart.playhead?.you)
            }
        }
    }

    @ViewBuilder private var youLabels: some View {
        switch strip.you {
        case .bars(let clusters, let slots, let showsLabels) where showsLabels:
            ClusterLabels(clusters: clusters, slots: slots, highlight: chart.highlight, playModel: playModel, loop: loop,
                          hover: hover)
        default:
            Color.clear
        }
    }
}

/// "▶ Playing the model", "▶ Playing your take" (r6 E4) or the loop's "Looping …" label (E3), Geist 12 secondary.
private struct HeaderNote: View {
    @Environment(\.palette) private var palette
    var note: StripHeaderNote

    var body: some View {
        HStack(spacing: 6) {
            switch note {
            case .looping(let word):
                Image(systemName: "repeat")
                    .font(.system(size: 11))
                    .accessibilityHidden(true)
                Text(Copy.looping(word))
            case .playing(let side):
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .accessibilityHidden(true)
                Text(side == .model ? Copy.playingModel : Copy.playingYou)
            }
        }
        .typeRole(.small)
        .foregroundStyle(palette.textSecondary)
        .accessibilityElement(children: .combine)
    }
}

/// The syllable being played (r6 E4): a 1 pt text.secondary outline, radius 4, 3 pt outside its bars. It jumps with
/// the playhead, never animates.
private struct SyllableOutline: View {
    @Environment(\.palette) private var palette
    var cluster: StripCluster?

    var body: some View {
        Canvas { context, size in
            guard let cluster else { return }
            let bars = clusterBars(cluster, width: size.width, maxHeight: size.height - 4)
            guard let first = bars.first, let last = bars.last else { return }
            let tallest = bars.map(\.height).max() ?? 0
            let rect = CGRect(x: first.x - 3, y: size.height / 2 - tallest / 2 - 3,
                              width: last.x + CGFloat(EnvelopeBins.barWidth) - first.x + 6, height: tallest + 6)
            context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4),
                           with: .color(palette.textSecondary), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Vertical positions inside the two rows (v3.1 V2), from the top of the NATIVE row.
enum StripGeometry {
    static let rowHeight: CGFloat = 56
    static let labelRowHeight: CGFloat = 24
    static let rowGap: CGFloat = 4
    /// The 16 pt label box is centred in the 24 pt label row.
    static let labelTop: CGFloat = rowHeight + (labelRowHeight - 16) / 2
    /// The dot's centre is 19 pt below the label's top (3 pt under the 16 pt box).
    static let dotCentre: CGFloat = 19
    static let dotDiameter: CGFloat = 4
    /// A connector starts 17 pt below the label's top, or 23 (4 pt below the dot) under a dotted label.
    static let connectorStart: CGFloat = 17
    static let connectorStartUnderDot: CGFloat = 23
    /// …and ends just inside the top of your row.
    static let youRowTop: CGFloat = rowHeight + labelRowHeight + rowGap
    static let connectorEndInset: CGFloat = 6
}

/// The 4 pt Lime dictionary-stress dot (v3.1 V2), also the legend's glyph.
struct StressDot: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Circle()
            .fill(palette.lime1)
            .frame(width: StripGeometry.dotDiameter, height: StripGeometry.dotDiameter)
            .accessibilityHidden(true)
    }
}

/// 1 pt lines in text.tertiary at 50% (100% with Increase Contrast) from each native syllable to your matching one.
private struct Connectors: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast
    var connectors: [TimingConnector]

    var body: some View {
        GeometryReader { proxy in
            let plotWidth = proxy.size.width - Metrics.rowLabelWidth - Metrics.inner - Metrics.endLabelWidth
            Canvas { context, _ in
                var path = Path()
                for connector in connectors {
                    let start = StripGeometry.labelTop
                        + (connector.fromDot ? StripGeometry.connectorStartUnderDot : StripGeometry.connectorStart)
                    let end = StripGeometry.youRowTop + StripGeometry.connectorEndInset
                    path.move(to: CGPoint(x: Metrics.rowLabelWidth + CGFloat(connector.native) * plotWidth, y: start))
                    path.addLine(to: CGPoint(x: Metrics.rowLabelWidth + CGFloat(connector.you) * plotWidth, y: end))
                }
                context.stroke(path, with: .color(palette.textTertiary.opacity(contrast == .increased ? 1 : 0.5)),
                               lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The 1 pt playhead (§9), in text.primary (Lime is kept for recording, A3), on this row's own timeline: the row that
/// plays, and the other row where the time map reaches it. None across a gap.
private struct Playhead: View {
    @Environment(\.palette) private var palette
    var progress: Double?

    var body: some View {
        GeometryReader { proxy in
            if let progress {
                Rectangle()
                    .fill(palette.textPrimary)
                    .frame(width: 1, height: proxy.size.height + 4)
                    .offset(x: CGFloat(progress) * proxy.size.width - 0.5, y: -2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
func barJitter(_ seed: Int, _ index: Int) -> Double { barJitterValue(seed, index) }

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
                    // Every bar is strip.bar at the recording's own envelope: no Lime, no stress scaling (v3.1 V1).
                    context.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(palette.stripBar))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Keeps the live row's bins between frames, so each frame only folds in the samples that arrived since the last.
private final class EnvelopeBinCache {
    var bins = EnvelopeBins()

    func update(_ envelope: RecordingEnvelope, width: Double, modelSeconds: Double) -> EnvelopeBins {
        bins.update(envelope, plotWidth: width, modelSeconds: modelSeconds)
        return bins
    }
}

/// Your row while recording (§7, A3, r6 E9): `Canvas` bars in strip.bar from the envelope stream, growing left to
/// right up to the 2 pt Lime playhead. x = elapsed ÷ the model's duration × width; a take longer than the model
/// compresses to fit, with the playhead at the right edge.
private struct LiveRecordingRow: View {
    @Environment(\.palette) private var palette
    var envelope: RecordingEnvelope
    var modelSeconds: Double
    @State private var cache = EnvelopeBinCache()

    var body: some View {
        GeometryReader { proxy in
            let x = CGFloat(RecordingScale.playhead(elapsed: envelope.elapsed, modelSeconds: modelSeconds)) * proxy.size.width
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let bins = cache.update(envelope, width: Double(size.width), modelSeconds: modelSeconds)
                    let midY = size.height / 2
                    for (index, value) in bins.heights.enumerated() {
                        let height = max(1.5, CGFloat(value) * (size.height - 4))
                        let rect = CGRect(x: CGFloat(index) * CGFloat(EnvelopeBins.pitch), y: midY - height / 2,
                                          width: CGFloat(EnvelopeBins.barWidth), height: height)
                        context.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(palette.stripBar))
                    }
                }
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
    var playModel: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                // A 24 pt empty slot, 1 pt dashed hairline outline, radius 4 (§8.2).
                RoundedRectangle(cornerRadius: Metrics.markRadius, style: .continuous)
                    .strokeBorder(palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: playModel)
                    .position(x: CGFloat(slot.position) * proxy.size.width, y: proxy.size.height / 2)
                    .help(Copy.missingTooltip)
            }
        }
    }
}

// MARK: - Labels

/// One row's labels: a syllable label centred under each cluster (with the Lime dot under a dotted native label), and
/// the expected word, tertiary and never struck through, over each missing slot. When they don't all fit with 4 pt
/// between them, `LabelLayout` hides plain syllables first; dotted caps always show. A hidden label keeps a tooltip over its syllable, and the
/// row's accessibility label reads every label (fixes round 5).
private struct ClusterLabels: View {
    @Environment(\.palette) private var palette
    var clusters: [StripCluster]
    var slots: [MissingSlot]
    /// The hovered or looping word (r6 E3, v3.2 W5): its box sits behind its labels on this row.
    var highlight: ChartHighlight?
    var playModel: () -> Void
    var loop: (Int) -> Void
    var hover: (Int?) -> Void

    private enum Content {
        case syllable(ClusterLabel, tooltip: String?, word: Int?)
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
        var dot: Bool = false
    }

    var body: some View {
        GeometryReader { proxy in
            let entries = entries(width: proxy.size.width)
            let shown = LabelLayout.visibility(entries.map {
                LabelLayout.Item(center: $0.center, width: $0.width, priority: $0.priority)
            })
            highlightBox(entries: entries, shown: shown, height: proxy.size.height)
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
            // Lime dots always sit under the stressed native syllable's bar cluster, including merged-word fallbacks (v3.4 Y2.3).
            ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
                if cluster.dot {
                    StressDot().position(
                        x: CGFloat((cluster.start + cluster.end) / 2) * proxy.size.width,
                        y: (proxy.size.height - 16) / 2 + StripGeometry.dotCentre
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.labelLine(entries(width: 0).map(\.spoken)))
    }

    /// The hover or loop box (r6 E3, v3.2 W5): one rounded rectangle, radius 4, 4 pt outside the word's labels, in
    /// the neutral `highlight` token, behind them. Faded in by the chart clock (at once with Reduce Motion).
    @ViewBuilder private func highlightBox(entries: [Entry], shown: [Bool], height: CGFloat) -> some View {
        if let highlight {
            let labels: [(center: Double, width: Double)] = entries.indices.compactMap { index in
                guard case .syllable(_, _, let word) = entries[index].content, word == highlight.word else { return nil }
                let entry = entries[index]
                return (Double(entry.center), Double(shown[index] ? entry.width : min(entry.width, entry.span)))
            }
            if let box = HighlightGeometry.box(labels) {
                RoundedRectangle(cornerRadius: Metrics.markRadius, style: .continuous)
                    .fill(highlight.strength == .loop ? palette.highlightLoop : palette.highlightHover)
                    .opacity(highlight.opacity)
                    .frame(width: box.maxX - box.minX, height: box.height)
                    .position(x: (box.minX + box.maxX) / 2, y: height / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private func label(_ entry: Entry) -> some View {
        switch entry.content {
        case .syllable(let label, let tooltip, let word):
            LabelView(label: label)
                .fixedSize()
                .help(tooltip ?? "")
                .onTapGesture { if let word { loop(word) } }
                // Hovering a label boxes its word on both rows and the pitch plot (r6 E3), with the pointing hand.
                .onHover { inside in if let word { hover(inside ? word : nil) } }
                .pointerStyle(word == nil ? nil : .link)
        case .missing(let expected):
            // The expected word in tertiary, no strike-through (v3 §3.4). Clicking it plays the model only.
            Text(expected)
                .typeRole(.small)
                .foregroundStyle(palette.textTertiary)
                .fixedSize()
                .help(Copy.missingTooltip)
                .onTapGesture(perform: playModel)
        }
    }

    /// Clusters and missing slots in timeline order, with their measured widths and priorities.
    private func entries(width: CGFloat) -> [Entry] {
        let syllables: [Entry] = clusters.compactMap { cluster in
            guard let label = cluster.label else { return nil }
            let spanStart = cluster.labelSpan?.lowerBound ?? cluster.start
            let spanEnd = cluster.labelSpan?.upperBound ?? cluster.end
            let wordHasDot = cluster.labelSpan != nil && cluster.word != nil
                && clusters.contains { $0.word == cluster.word && $0.dot }
            return Entry(
                content: .syllable(label, tooltip: cluster.tooltip, word: cluster.word),
                center: CGFloat((spanStart + spanEnd) / 2) * width,
                span: CGFloat(spanEnd - spanStart) * width,
                width: LabelView.width(label),
                priority: LabelLayout.syllablePriority(label.style),
                spoken: (cluster.dot || wordHasDot) ? Copy.dictionaryStressLabel(label.text) : label.text,
                tooltip: Copy.hiddenLabelTooltip(label.text, note: cluster.tooltip),
                dot: cluster.dot
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
        case .yours, .merged:
            Text(label.text)
                .typeRole(.small)
                .foregroundStyle(palette.textTertiary)
        case .heard:
            Text(label.text)
                .typeRole(.small, italic: true)
                .foregroundStyle(palette.textSecondary)
        }
    }

    /// The label's drawn width, for `LabelLayout`.
    static func width(_ label: ClusterLabel) -> CGFloat {
        switch label.style {
        case .caps: TextMeasure.width(label.text, role: .smallBold)
        case .lower, .yours, .merged: TextMeasure.width(label.text, role: .small)
        case .heard: TextMeasure.width(label.text, role: .small, italic: true)
        }
    }
}
