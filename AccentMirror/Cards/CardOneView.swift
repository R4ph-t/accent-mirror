import SwiftUI

/// Card 1, "WHAT TO CHANGE" or "YOUR TAKE" (§3: 16 title + 16 + 4 + 40 per row + 4; §10 rows).
struct CardOneView: View {
    @Environment(\.palette) private var palette
    var card: CardPresentation

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
                        .padding(.trailing, row.trailing == .play ? 36 : 0)
                }
                CardRowView(row: row)
            }
            ForEach(Array(card.infoLines.enumerated()), id: \.offset) { _, line in
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

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = row.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(row.iconIsMistake ? palette.mistake : palette.textSecondary)
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
            case .play:
                // Plays the model then you for that word; visual only in this shell.
                FocusRingButton(cornerRadius: Metrics.controlRadius, action: {}) { _ in
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                        .surface(palette.surfaceWell, cornerRadius: Metrics.controlRadius)
                }
                .accessibilityLabel("Play the model, then you")
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

/// A sentence whose runs carry their own roles: stressed caps in lime.text, the wrong syllable in mistake
/// blue, heard words in italics.
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
            case .stressed:
                run.font = TypeRole.bodyBold.fontSized(role.size)
                run.foregroundColor = palette.limeText
            case .mistake:
                run.font = TypeRole.bodyBold.fontSized(role.size)
                run.foregroundColor = palette.mistake
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
