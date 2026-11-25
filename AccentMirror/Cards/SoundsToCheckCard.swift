import AMPipeline
import SwiftUI

/// Card 1 on an analysed take (Designer addendum v5 §1.1–1.2): `SOUNDS TO CHECK` with Play Both, up to three flagged
/// words (least confident first, confidence never drawn), `+N more…`, or the neutral zero-flags lines, then the
/// quiet line if any, and always the `Flags are hints, not a grade.` footer.
struct SoundsToCheckCard: View {
    @Environment(\.palette) private var palette
    var sounds: SoundsCard
    var quietLine: Sentence?
    var quietLineInput: Bool
    var playBoth: () -> Void
    /// A row click opens that word's popover in the PHRASE card.
    var openWord: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)
            switch sounds {
            case .flagged(let rows, let more):
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, hint in
                        SoundRow(hint: hint) { openWord(hint.wordIndex) }
                    }
                }
                if more > 0 {
                    Text(Copy.moreFlagged(more))
                        .typeRole(.small)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.leading, 15)
                        .frame(height: 16)
                        .padding(.top, 4)
                        .accessibilityLabel(Copy.moreFlaggedSpoken(more))
                }
            case .noneFlagged:
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                        Text(Copy.noSoundsToCheck)
                            .typeRole(.bodyMedium)
                            .foregroundStyle(palette.textPrimary)
                    }
                    .frame(height: 20)
                    Text(Copy.noSoundsNote)
                        .typeRole(.small)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.leading, 24)
                }
                .accessibilityElement(children: .combine)
            case .notChecked:
                Text(Copy.soundsNotChecked)
                    .typeRole(.body)
                    .foregroundStyle(palette.textSecondary)
                    .frame(height: 20)
            }
            if let quietLine {
                CardQuietLine(sentence: quietLine, showsInput: quietLineInput)
                    .padding(.top, 4)
            }
            Text(Copy.flagsAreHints)
                .typeRole(.small)
                .foregroundStyle(palette.textTertiary)
                .frame(height: 16)
                .padding(.top, 6)
        }
        .padding(.horizontal, Metrics.outer)
        .padding(.top, Metrics.outer)
        .padding(.bottom, Metrics.outer + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(palette.surfaceCard, cornerRadius: Metrics.cardRadius)
        .accessibilityElement(children: .contain)
    }

    /// `SOUNDS TO CHECK` at the left, Play Both at the right (its 28 pt button centred on the title line).
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(Copy.soundsToCheck)
                .typeRole(.mono)
                .foregroundStyle(palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            PlayBothButton(action: playBoth)
        }
        .frame(height: 16)
    }
}

/// One flagged word: diamond, word (min 92 pt), the expected sound, then "· sounded closer to …" (v5 §1.1).
private struct SoundRow: View {
    @Environment(\.palette) private var palette
    var hint: SoundHint
    var action: () -> Void

    var body: some View {
        FocusRingButton(cornerRadius: Metrics.markRadius, action: action) { hovered in
            HStack(spacing: 8) {
                FlagDiamond()
                Text(hint.word)
                    .typeRole(.bodySemibold)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .frame(minWidth: 92, alignment: .leading)
                Text(hint.expected.plain)
                    .typeRole(.body)
                    .foregroundStyle(palette.textPrimary)
                    .help(hint.ipaLine)
                Text("\u{00B7} \(hint.heardLine)")
                    .typeRole(.body)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .help(hint.ipaLine)
                Spacer(minLength: 0)
            }
            .frame(height: 26)
            .background {
                if hovered {
                    RoundedRectangle(cornerRadius: Metrics.markRadius, style: .continuous)
                        .fill(palette.highlightHover)
                        .padding(.horizontal, -4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.soundRowSpoken(word: hint.word, expected: hint.expected.plain, heard: hint.heardLine))
        .accessibilityValue(hint.spokenIPA)
        .accessibilityHint(Copy.soundRowHint)
        .accessibilityAddTraits(.isButton)
    }
}

/// The 7 pt Lime diamond that pairs with every flag (never colour alone).
struct FlagDiamond: View {
    @Environment(\.palette) private var palette
    var size: CGFloat = 7

    var body: some View {
        DiamondShape()
            .fill(palette.limeText)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// Card 1's Play Both ghost button (v3 §3.1, kept in v5's header): surface.well, 28 tall, radius 6, play glyph.
struct PlayBothButton: View {
    @Environment(\.palette) private var palette
    var action: () -> Void

    var body: some View {
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: action) { _ in
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
    }
}
