import AMPipeline
import SwiftUI

/// The word popover's content (Designer addendum v5 §3), inside a real NSPopover anchored below the word with the
/// system arrow: the word, each flagged sound with `Play this sound` (your take only), then Native / You / Play both
/// and the keyboard hint. 280 pt wide, 16 pt padding. IPA lives only in tooltips and VoiceOver.
struct WordPopoverView: View {
    @Environment(\.palette) private var palette
    var word: PhraseWord
    var model: ShellModel

    static let width: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(word.text)
                .typeRole(.popoverTitle)
                .foregroundStyle(palette.textPrimary)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            if !word.hints.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(word.hints.enumerated()), id: \.offset) { position, hint in
                        sound(hint, position: position)
                    }
                }
                Hairline()
                    .padding(.vertical, 12)
            }
            HStack(spacing: 8) {
                wordButton(Copy.native, action: .native, spoken: Copy.playNativeSpoken(word.text))
                wordButton(Copy.you, action: .you, spoken: Copy.playYouSpoken(word.text))
                wordButton(Copy.playBothWord, action: .both, spoken: Copy.playBothSpoken(word.text))
                    .layoutPriority(1)
            }
            Text(Copy.popoverFooter)
                .typeRole(.small)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 10)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
        .background(palette.surfaceCard)
    }

    private func sound(_ hint: SoundHint, position: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hint.expected.plain)
                    .typeRole(.bodyMedium)
                    .foregroundStyle(palette.textPrimary)
                Text(hint.heardLine)
                    .typeRole(.small)
                    .foregroundStyle(palette.textSecondary)
            }
            .help(hint.ipaLine)
            .accessibilityElement(children: .combine)
            .accessibilityValue(hint.ipaLine)
            PopoverButton(title: Copy.playThisSound, height: 26, role: .smallMedium, expands: false,
                          enabled: word.heardInTake && model.canPlayWord(word.index, .sound(position))) {
                model.playWord(word.index, .sound(position))
            }
            .accessibilityLabel(Copy.playThisSoundSpoken(expected: hint.expected.plain, word: word.text))
            .accessibilityValue(hint.ipaLine)
            .padding(.top, 10)
        }
    }

    private func wordButton(_ title: String, action: WordAction, spoken: String) -> some View {
        PopoverButton(title: title, height: Metrics.controlHeight, role: .bodyMedium, expands: true,
                      enabled: model.canPlayWord(word.index, action)) {
            model.playWord(word.index, action)
        }
        .accessibilityLabel(spoken)
    }
}

/// A surface.well popover button with a play glyph. Disabled (the word wasn't heard in your take): tertiary ink and
/// the "This word wasn't heard in your take" tooltip.
private struct PopoverButton: View {
    @Environment(\.palette) private var palette
    var title: String
    var height: CGFloat
    var role: TypeRole
    var expands: Bool
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: action) { _ in
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                Text(title)
                    .typeRole(role)
                    .lineLimit(1)
            }
            .foregroundStyle(enabled ? palette.textPrimary : palette.textTertiary)
            .padding(.horizontal, 10)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: height)
            .surface(palette.surfaceWell, cornerRadius: Metrics.controlRadius)
        }
        .disabled(!enabled)
        // A disabled control shows no tooltip of its own, so the tooltip sits on a wrapper.
        .padding(0)
        .contentShape(Rectangle())
        .help(enabled ? "" : Copy.wordNotHeard)
        .accessibilityHint(enabled ? "" : Copy.wordNotHeard)
    }
}
