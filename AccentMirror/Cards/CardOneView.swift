import SwiftUI

/// Card 1, always "YOUR TAKE" (v3 §3.1: 16 title + 16 + 4 + 40 per row + 4), with at most one quiet line.
struct CardOneView: View {
    @Environment(\.palette) private var palette
    var card: CardPresentation
    /// Play Both (⌥⌘L): the model, 0.4 s, then your take.
    var playBoth: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.title)
                .typeRole(.mono)
                .foregroundStyle(palette.textSecondary)
                .frame(height: 16)
                .padding(.bottom, 4)
            ForEach(Array(card.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Hairline()
                        .padding(.leading, 24)
                }
                CardRowView(row: row, playBoth: playBoth)
            }
            if let line = card.quietLine {
                InfoLine(sentence: line, showsInput: card.quietLineInput)
            }
        }
        .padding(.horizontal, Metrics.outer)
        .padding(.top, Metrics.outer)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(palette.surfaceCard, cornerRadius: Metrics.cardRadius)
    }
}

private struct CardRowView: View {
    @Environment(\.palette) private var palette
    @Environment(\.shellActions) private var actions
    var row: CardRow
    var playBoth: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch row.icon {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                case .overlay:
                    OverlayGlyph()
                case nil:
                    EmptyView()
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)

            SentenceText(sentence: row.sentence, role: .body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 8)
            switch row.trailing {
            case .none:
                EmptyView()
            case .playBoth:
                // The ghost button: surface.well, 28 tall, radius 6, play glyph (v3 §3.1).
                FocusRingButton(cornerRadius: Metrics.controlRadius, action: playBoth) { _ in
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text(Copy.playBoth)
                            .typeRole(.bodyMedium)
                    }
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: Metrics.controlHeight)
                    .surface(palette.surfaceWell, cornerRadius: Metrics.controlRadius)
                }
                .help(Copy.playBothTooltip)
                .accessibilityHint(Copy.playBothTooltip)
            case .levelMeter(let fixed):
                LevelMeterView(fixed: fixed)
            case .button(let title):
                CardButton(title: title, action: actions.cardButton)
            case .inputThenButton(let title):
                // v3.5 I4 tier A: Input… (opens the popover) and Try Again.
                HStack(spacing: 8) {
                    CardButton(title: Copy.inputEllipsis, action: { actions.openInput(.card) })
                        .inputPopover(source: .card)
                    CardButton(title: title, action: actions.cardButton)
                }
            }
        }
        .frame(height: 40)
        .accessibilityElement(children: .combine)
    }
}

/// r6 E5: a 96 × 6 track in surface.well, the Lime gradient fill from −60 to 0 dBFS on the frame's RMS, a 2 pt
/// text.primary peak tick held for 1 s. Too loud (a peak at −1 dBFS or more, held 1.5 s): a square end, a 4 × 10 stop
/// bar past the track, and `speaker.wave.3` with "Too loud" before it. No colour change. Nothing outside a take.
private struct LevelMeterView: View {
    @Environment(LevelMeterModel.self) private var meter: LevelMeterModel?
    /// A fixture's frozen frame; nil reads the live meter.
    var fixed: LevelReading?

    static let width: CGFloat = 96

    private var reading: LevelReading? {
        if let fixed { return fixed }
        guard let meter, let rms = meter.rmsDBFS else { return nil }
        return LevelReading(rmsDBFS: rms, peakDBFS: meter.peakDBFS, tooLoud: meter.tooLoud)
    }

    var body: some View {
        if let reading {
            LevelMeterBar(reading: reading, trackWidth: Self.width)
        }
    }
}

/// E5's drawing, shared by card 1's recording row (a 96 pt track) and the Input popover (the full content width,
/// v3.5 I2): "Too loud" and its glyph, the 6 pt track, the peak tick and the stop bar.
struct LevelMeterBar: View {
    @Environment(\.palette) private var palette
    var reading: LevelReading
    /// Nil: the track takes the width it's offered.
    var trackWidth: CGFloat?

    var body: some View {
        HStack(spacing: 8) {
            if reading.tooLoud {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.3")
                        .font(.system(size: 12, weight: .medium))
                    Text(Copy.tooLoud)
                        .typeRole(.smallMedium)
                }
                .foregroundStyle(palette.textPrimary)
                .fixedSize()
            }
            HStack(spacing: 2) {
                track
                    .frame(width: trackWidth, height: 6)
                    .frame(maxWidth: trackWidth == nil ? .infinity : nil)
                Rectangle()
                    .fill(palette.textPrimary)
                    .frame(width: 4, height: 10)
                    .opacity(reading.tooLoud ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(palette.surfaceWell)
                Group {
                    if reading.tooLoud {
                        UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3)
                            .frame(width: width)
                    } else {
                        RoundedRectangle(cornerRadius: 3).frame(width: width * Self.fraction(reading.rmsDBFS))
                    }
                }
                .foregroundStyle(palette.accentGradient)
                Rectangle()
                    .fill(palette.textPrimary)
                    .frame(width: 2)
                    .offset(x: max(0, width * Self.fraction(reading.peakDBFS) - 2))
            }
        }
    }

    static func fraction(_ dbfs: Double) -> CGFloat {
        CGFloat(min(1, max(0, (dbfs + 60) / 60)))
    }
}

/// Card 1's well button (Try Again, Input…): surface.well, 28 tall, radius 6.
private struct CardButton: View {
    @Environment(\.palette) private var palette
    var title: String
    var action: @MainActor () -> Void

    var body: some View {
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: action) { _ in
            Text(title)
                .typeRole(.bodyMedium)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 18)
                .frame(height: Metrics.controlHeight)
                .surface(palette.surfaceWell, cornerRadius: Metrics.controlRadius)
        }
    }
}

private struct InfoLine: View {
    @Environment(\.palette) private var palette
    @Environment(\.shellActions) private var actions
    var sentence: Sentence
    /// v3.5 I4 tier B: the clipped line ends with an Input… button that opens the popover.
    var showsInput = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .frame(width: 16)
                .accessibilityHidden(true)
            SentenceText(sentence: sentence, role: .small)
            if showsInput {
                Spacer(minLength: 8)
                FocusRingButton(cornerRadius: Metrics.controlRadius, action: { actions.openInput(.card) }) { _ in
                    Text(Copy.inputEllipsis)
                        .typeRole(.bodyMedium)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: Metrics.controlHeight)
                        .surface(palette.surfaceWell, cornerRadius: Metrics.controlRadius)
                }
                .inputPopover(source: .card)
            }
        }
        .foregroundStyle(palette.textSecondary)
        .frame(height: 28)
    }
}

/// The result row's 16 pt overlay icon: two waves in text.secondary, one soft (wide, faint) and one thin.
private struct OverlayGlyph: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { context, size in
            func wave(phase: CGFloat) -> Path {
                var path = Path()
                let midY = size.height / 2
                for step in 0...32 {
                    let x = CGFloat(step) / 32 * size.width
                    let y = midY + sin((x / size.width) * 2 * .pi + phase) * size.height * 0.2
                    if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                return path
            }
            let style = StrokeStyle(lineCap: .round)
            var soft = style; soft.lineWidth = 2.5
            var thin = style; thin.lineWidth = 1
            context.stroke(wave(phase: 0.5), with: .color(palette.textSecondary.opacity(0.4)), style: soft)
            context.stroke(wave(phase: 0), with: .color(palette.textSecondary), style: thin)
        }
        .frame(width: 16, height: 16)
    }
}

/// A sentence whose runs carry their own roles: heard words in italics.
struct SentenceText: View {
    @Environment(\.palette) private var palette
    var sentence: Sentence
    var role: TypeRole

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for segment in sentence {
            var run = AttributedString(segment.text)
            switch segment.role {
            case .plain:
                run.font = role.font
            case .heard:
                run.font = role.italicFont
            }
            result.append(run)
        }
        return result
    }
}

extension TypeRole {
    func fontSized(_ size: CGFloat) -> Font { .custom(fontName, fixedSize: size) }
}

/// The inline banner above the cards for app problems and the save notice (§13.2): 40 tall, radius 6,
/// surface.well with a 1 px hairline, ink only. Never blue, never Try Again, never inside card 1.
struct BannerView: View {
    @Environment(\.palette) private var palette
    @Environment(\.shellActions) private var actions
    var banner: BannerPresentation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.icon)
                .font(.system(size: 14))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(banner.sentence)
                .typeRole(.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 8)
            FocusRingButton(cornerRadius: Metrics.controlRadius, action: actions.bannerButton) { _ in
                Text(banner.button)
                    .typeRole(.bodySemibold)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: Metrics.controlHeight)
            }
            if banner.closable {
                FocusRingButton(cornerRadius: Metrics.controlRadius, action: actions.bannerClose) { _ in
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 24, height: Metrics.controlHeight)
                }
                .accessibilityLabel("Close")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 40)
        .surface(palette.surfaceWell, cornerRadius: Metrics.controlRadius)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 1)
        }
        .contextMenu {
            // Details (the stage and the error) live under Copy Details, not in the sentence.
            Button("Copy Details") { actions.copyDetails() }
        }
    }
}
