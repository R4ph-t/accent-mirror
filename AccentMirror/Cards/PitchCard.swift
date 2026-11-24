import SwiftUI

/// "PITCH" (§9): model time on x, semitones re your median on y. Native band as a soft ribbon (at least 7 pt),
/// your line 2 pt, bridged frames lighter and thinner, breaks only where the fixture's segments break. The pitch
/// card takes whatever height is left.
struct PitchCard: View {
    @Environment(\.palette) private var palette
    var pitch: PitchPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PITCH")
                .typeRole(.mono)
                .foregroundStyle(palette.textSecondary)
                .frame(height: 16)
                .padding(.bottom, 8)
            GeometryReader { proxy in
                PitchPlot(pitch: pitch, size: proxy.size)
            }
            // The plot (top to baseline) never gets shorter than 120 pt (r4 C8); the word labels sit below it.
            .frame(minHeight: Metrics.pitchPlotMinHeight + PlotFrame.wordLabelHeight)
        }
        .padding(.horizontal, Metrics.outer)
        .padding(.top, Metrics.outer)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                SurfaceBackground(color: palette.surfaceCard, cornerRadius: Metrics.cardRadius)
                // Lime wash at the top: lime.2 at 7% (9% dark) fading to 0 at 70% height.
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(LinearGradient(
                        stops: [
                            .init(color: palette.lime2.opacity(palette.washOpacity), location: 0),
                            .init(color: palette.lime2.opacity(0), location: 0.7),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ))
            }
        }
    }
}

/// The native words under the baseline. When they don't all fit with 4 pt between them, `LabelLayout` hides
/// non-target words first; target words always show. A hidden word keeps a tooltip over its span, and the line's
/// accessibility label reads every word (fixes round 5).
private struct WordLabels: View {
    @Environment(\.palette) private var palette
    var words: [(text: String, start: Double, end: Double, isTarget: Bool)]
    var frame: PlotFrame

    var body: some View {
        let y = frame.baselineY + 13
        let widths = words.map { TextMeasure.width($0.text, role: .small) }
        let centers = words.map { frame.x(($0.start + $0.end) / 2) }
        let shown = LabelLayout.visibility(words.indices.map {
            LabelLayout.Item(center: centers[$0], width: widths[$0], priority: LabelLayout.wordPriority(isTarget: words[$0].isTarget))
        })
        ZStack(alignment: .topLeading) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                if shown[index] {
                    Text(word.text)
                        .typeRole(.small)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize()
                        .position(x: centers[index], y: y)
                } else {
                    Color.clear
                        .frame(width: max(8, min(widths[index], frame.x(word.end) - frame.x(word.start))), height: 20)
                        .contentShape(Rectangle())
                        .help(Copy.hiddenLabelTooltip(word.text, note: nil))
                        .position(x: centers[index], y: y)
                }
            }
        }
        .frame(width: frame.size.width, height: frame.size.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.labelLine(words.map(\.text)))
    }
}

/// Geometry of the plot area inside the card's content box.
private struct PlotFrame {
    let size: CGSize
    var plotX: CGFloat { Metrics.rowLabelWidth }
    var plotWidth: CGFloat { size.width - Metrics.rowLabelWidth - Metrics.inner - Metrics.endLabelWidth }
    /// Room under the baseline for the word labels.
    static let wordLabelHeight: CGFloat = 22
    /// The baseline sits 22 pt above the bottom: word labels go under it.
    var baselineY: CGFloat { size.height - Self.wordLabelHeight }
    var top: CGFloat { 0 }
    var midY: CGFloat { (top + baselineY) / 2 }
    var halfHeight: CGFloat { (baselineY - top) / 2 }

    func x(_ t: Double) -> CGFloat { plotX + CGFloat(t) * plotWidth }
    func y(_ st: Double, range: Double) -> CGFloat { midY - CGFloat(st / range) * halfHeight }
}

private struct PitchPlot: View {
    @Environment(\.palette) private var palette
    var pitch: PitchPresentation
    var size: CGSize

    var body: some View {
        let frame = PlotFrame(size: size)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                draw(in: &context, frame: frame)
            }
            .accessibilityHidden(true)

            Text("HIGH")
                .typeRole(.mono)
                .foregroundStyle(palette.textTertiary)
                .frame(width: Metrics.rowLabelWidth - 8, alignment: .trailing)
                .position(x: (Metrics.rowLabelWidth - 8) / 2, y: frame.top + 8)
            Text("LOW")
                .typeRole(.mono)
                .foregroundStyle(palette.textTertiary)
                .frame(width: Metrics.rowLabelWidth - 8, alignment: .trailing)
                .position(x: (Metrics.rowLabelWidth - 8) / 2, y: frame.baselineY - 9)

            WordLabels(words: pitch.words, frame: frame)

            let ends = endLabelPositions(frame: frame)
            if let y = ends.native {
                endLabel("NATIVE", color: palette.textSecondary, frame: frame, y: y)
            }
            if let y = ends.you {
                endLabel("YOU", color: palette.textPrimary, frame: frame, y: y)
            }
            if let message = pitch.message {
                // No backing, centred, its baseline 8 pt above the bottom of the plot (Designer answer 2, round 3).
                Text(message)
                    .typeRole(.small)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize()
                    .frame(
                        width: frame.plotWidth, height: frame.baselineY - frame.top - Metrics.noPitchBaselineInset,
                        alignment: Alignment(horizontal: .center, vertical: .lastTextBaseline)
                    )
                    .offset(x: frame.plotX, y: frame.top)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(pitch.you.isEmpty ? "Pitch, native only" : "Pitch, native band and your line")
    }

    /// Each end label sits at its line's last point; when the two would overlap they are pushed apart evenly,
    /// keeping their order.
    private func endLabelPositions(frame: PlotFrame) -> (native: CGFloat?, you: CGFloat?) {
        let range = pitch.rangeSemitones
        let native = pitch.band.last?.points.last.map { frame.y($0.st, range: range) }
        let you = pitch.you.last?.points.last.map { frame.y($0.st, range: range) }
        guard let n = native, let y = you, abs(n - y) < 16 else { return (native, you) }
        let mid = (n + y) / 2
        return n <= y ? (mid - 8, mid + 8) : (mid + 8, mid - 8)
    }

    /// End labels sit left-aligned in the end-label column (x 1120 to 1168).
    private func endLabel(_ text: String, color: Color, frame: PlotFrame, y: CGFloat) -> some View {
        Text(text)
            .typeRole(.mono)
            .foregroundStyle(color)
            .fixedSize()
            .frame(width: Metrics.endLabelWidth, alignment: .leading)
            .position(x: frame.plotX + frame.plotWidth + Metrics.inner + Metrics.endLabelWidth / 2, y: y)
    }

    private func draw(in context: inout GraphicsContext, frame: PlotFrame) {
        let range = pitch.rangeSemitones

        // The native recording's waveform as a faint texture behind (hidden with Increase Contrast).
        if palette.showsPitchTexture {
            for cluster in pitch.texture {
                let bars = clusterBars(cluster, width: frame.plotWidth, maxHeight: frame.halfHeight * 1.7, pitch: 3)
                for bar in bars {
                    let h = max(6, bar.height * 0.6 + frame.halfHeight * 0.35 * CGFloat(cluster.prominence))
                    context.fill(
                        Path(CGRect(x: frame.plotX + bar.x, y: frame.midY - h / 2, width: 1, height: h)),
                        with: .color(palette.pitchTexture)
                    )
                }
            }
        }

        // Baseline, with a short Lime segment under each stressed native syllable.
        context.fill(Path(CGRect(x: frame.plotX, y: frame.baselineY, width: frame.plotWidth, height: 1)), with: .color(palette.baseline))
        for span in pitch.stressedSpans {
            let rect = CGRect(x: frame.x(span.start), y: frame.baselineY - 1, width: frame.x(span.end) - frame.x(span.start), height: 3)
            context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .linearGradient(
                Gradient(colors: [palette.lime1, palette.lime2]),
                startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)
            ))
        }

        // Native band: P10 to P90 ribbon, at least 7 pt thick, round ends.
        for segment in pitch.band {
            let centre = smooth(segment.points.map { CGPoint(x: frame.x($0.t), y: frame.y($0.st, range: range)) })
            let halves = interpolate(segment.points.map { CGFloat($0.half / range) * frame.halfHeight }, count: centre.count)
            guard centre.count > 1 else { continue }
            var ribbon = Path()
            ribbon.move(to: CGPoint(x: centre[0].x, y: centre[0].y - halves[0]))
            for i in 1..<centre.count { ribbon.addLine(to: CGPoint(x: centre[i].x, y: centre[i].y - halves[i])) }
            for i in stride(from: centre.count - 1, through: 0, by: -1) {
                ribbon.addLine(to: CGPoint(x: centre[i].x, y: centre[i].y + halves[i]))
            }
            ribbon.closeSubpath()
            var line = Path()
            line.addLines(centre)
            let minimum = line.strokedPath(StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            context.fill(ribbon.union(minimum), with: .color(palette.pitchNative))
        }

        // Your line: 2 pt, round caps; frames bridged across unvoiced stretches at 45%, 1.5 pt.
        for segment in pitch.you {
            let points = segment.points
            let anchors = points.map { CGPoint(x: frame.x($0.t), y: frame.y($0.st, range: range)) }
            let samples = 10
            let curve = smooth(anchors, samplesPerSpan: samples)
            for span in 0..<(points.count - 1) {
                let voiced = (points[span].voiced ?? true) && (points[span + 1].voiced ?? true)
                var piece = Path()
                piece.addLines(Array(curve[(span * samples)...min(curve.count - 1, (span + 1) * samples)]))
                context.stroke(
                    piece,
                    with: .color(palette.pitchYou.opacity(voiced ? 1 : 0.45)),
                    style: StrokeStyle(lineWidth: voiced ? 2 : 1.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    /// Catmull-Rom through the anchors, `samplesPerSpan` points per span.
    private func smooth(_ anchors: [CGPoint], samplesPerSpan: Int = 10) -> [CGPoint] {
        guard anchors.count > 2 else { return anchors }
        var out: [CGPoint] = []
        for i in 0..<(anchors.count - 1) {
            let p0 = anchors[max(i - 1, 0)], p1 = anchors[i], p2 = anchors[i + 1], p3 = anchors[min(i + 2, anchors.count - 1)]
            for step in 0..<samplesPerSpan {
                let t = CGFloat(step) / CGFloat(samplesPerSpan)
                let t2 = t * t, t3 = t2 * t
                func axis(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                out.append(CGPoint(x: axis(p0.x, p1.x, p2.x, p3.x), y: axis(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        out.append(anchors[anchors.count - 1])
        return out
    }

    private func interpolate(_ values: [CGFloat], count: Int) -> [CGFloat] {
        guard values.count > 1, count > 1 else { return Array(repeating: values.first ?? 0, count: count) }
        return (0..<count).map { i in
            let position = CGFloat(i) / CGFloat(count - 1) * CGFloat(values.count - 1)
            let lower = Int(position), upper = min(lower + 1, values.count - 1)
            let f = position - CGFloat(lower)
            return values[lower] * (1 - f) + values[upper] * f
        }
    }
}
