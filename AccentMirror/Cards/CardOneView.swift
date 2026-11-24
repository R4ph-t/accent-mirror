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
                InfoLine(sentence: line)
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
                            .typeRole(.body)
                    }
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: Metrics.controlHeight)
                    .surface(palette.surfaceWell, cornerRadius: Metrics.controlRadius)
                }
                .help(Copy.playBothTooltip)
                .accessibilityHint(Copy.playBothTooltip)
            case .button(let title):
                FocusRingButton(cornerRadius: Metrics.controlRadius, action: {}) { _ in
                    Text(title)
                        .typeRole(.body)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 18)
                        .frame(height: Metrics.controlHeight)
                        .surface(palette.surfaceWell, cornerRadius: Metrics.controlRadius)
                }
            }
        }
        .frame(height: 40)
        .accessibilityElement(children: .combine)
    }
}

private struct InfoLine: View {
    @Environment(\.palette) private var palette
    var sentence: Sentence

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .frame(width: 16)
                .accessibilityHidden(true)
            SentenceText(sentence: sentence, role: .small)
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
            FocusRingButton(cornerRadius: Metrics.controlRadius, action: {}) { _ in
                Text(banner.button)
                    .typeRole(.bodySemibold)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: Metrics.controlHeight)
            }
            if banner.closable {
                FocusRingButton(cornerRadius: Metrics.controlRadius, action: {}) { _ in
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
            Button("Copy Details") {}
        }
    }
}
