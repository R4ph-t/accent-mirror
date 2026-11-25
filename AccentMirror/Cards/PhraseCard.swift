import SwiftUI

/// The PHRASE card (Designer addendum v5 §2): the phrase as the main surface, Geist 18 words wrapping with an 8 pt row
/// gap and 4 pt chip gap. Whole words only: a flagged word gets the Lime diamond, a 2 pt dotted Lime underline and
/// weight 500 (never colour alone); a word not in the dictionary is text.secondary and not clickable. Clicking a
/// checkable word opens its Native vs You popover, a real NSPopover with the system arrow.
struct PhraseCard: View {
    @Environment(\.palette) private var palette
    var phrase: PhrasePresentation
    var model: ShellModel
    /// The mockup's 196 pt card while the disclosure is collapsed; its content height once the charts show below.
    var fillsHeight: Bool

    static let minHeight: CGFloat = 196

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Text(Copy.phrase)
                    .typeRole(.mono)
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                legend
            }
            .frame(height: 16)
            WordFlow(horizontalSpacing: 4, verticalSpacing: 8) {
                ForEach(phrase.words, id: \.index) { word in
                    PhraseWordView(word: word, model: model)
                }
            }
            // The chips' 7 pt padding sits outside the text column, so words line up with the card title.
            .padding(.horizontal, -7)
            .padding(.top, 18)
        }
        .padding(Metrics.outer)
        .frame(maxWidth: .infinity, minHeight: fillsHeight ? Self.minHeight : nil, alignment: .topLeading)
        .surface(palette.surfaceCard, cornerRadius: Metrics.cardRadius)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var legend: some View {
        HStack(spacing: 14) {
            switch phrase.legend {
            case .none:
                EmptyView()
            case .hint:
                hint
            case .flags:
                HStack(spacing: 5) {
                    FlagDiamond()
                    Text(Copy.checkThisSound)
                        .typeRole(.small)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.bottom, 1)
                        .flagUnderline(palette.limeText, below: 1)
                }
                hint
            case .notInDictionary:
                Text(Copy.greyWordNote)
                    .typeRole(.small)
                    .foregroundStyle(palette.textSecondary)
                hint
            }
        }
        .lineLimit(1)
    }

    private var hint: some View {
        Text(Copy.clickAnyWord)
            .typeRole(.small)
            .foregroundStyle(palette.textTertiary)
    }
}

/// One word token: `padding 4 × 7`, radius 6, a 1 pt border that is transparent by default so states never shift
/// the layout (v5 §2 interactive states).
private struct PhraseWordView: View {
    @Environment(\.palette) private var palette
    var word: PhraseWord
    var model: ShellModel
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        if word.isInteractive {
            Button { model.openWord(word.index) } label: { label }
                .buttonStyle(WordChipStyle(
                    palette: palette, hovered: hovered, active: model.wordPopover == word.index,
                    playing: model.playingPhraseWord == word.index))
                .focused($focused)
                .focusEffectDisabled()
                .onHover { hovered = $0 }
                .pointerStyle(.link)
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: Metrics.controlRadius + 2, style: .continuous)
                            .strokeBorder(palette.limeText, lineWidth: 2)
                            .padding(-2)
                    }
                }
                .popover(isPresented: Binding(
                    get: { model.wordPopover == word.index },
                    set: { open in if !open, model.wordPopover == word.index { model.closeWordPopover() } }
                ), arrowEdge: .bottom) {
                    WordPopoverView(word: word, model: model)
                        .environment(\.palette, palette)
                }
                .accessibilityLabel(word.kind == .flagged ? word.text + Copy.checkSoundSuffix : word.text)
                .accessibilityValue(word.hints.map { "\($0.expected.plain), \($0.heardLine)" }.joined(separator: "; "))
                .accessibilityHint(Copy.wordHint)
        } else {
            label
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .strokeBorder(Color.clear, lineWidth: 1)
                }
                .help(word.kind == .notInDictionary ? Copy.notInDictionary : "")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(word.text)
                .accessibilityValue(word.kind == .notInDictionary ? Copy.notInDictionary : "")
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            if word.kind == .flagged {
                FlagDiamond()
            }
            Text(word.text)
                .typeRole(word.kind == .flagged ? .phraseWordFlagged : .phraseWord)
                .foregroundStyle(word.kind == .notInDictionary ? palette.textSecondary
                                 : model.playingPhraseWord == word.index ? palette.limeText : palette.textPrimary)
                .flagUnderline(word.kind == .flagged ? palette.limeText : nil, below: 2)
                .frame(height: 26)
        }
    }
}

/// Hover `highlight.hover`, pressed `surface.well`, open `surface.well` with a hairline, playing a 1 pt Lime border
/// over a faint Lime wash.
private struct WordChipStyle: ButtonStyle {
    var palette: Palette
    var hovered: Bool
    var active: Bool
    var playing: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
            .contentShape(Rectangle())
    }

    private func fill(pressed: Bool) -> Color {
        if pressed || active { return palette.surfaceWell }
        if playing { return palette.limeText.opacity(palette.washOpacity) }
        return hovered ? palette.highlightHover : .clear
    }

    private var border: Color {
        if playing { return palette.limeText }
        return active ? palette.hairline : .clear
    }
}

extension View {
    /// v5 §2's flag mark: a 2 pt dotted rule in `color`, its top `below` points under the text's last baseline. Nil
    /// draws nothing. The only underline in the app; never on part of a word.
    func flagUnderline(_ color: Color?, below: CGFloat) -> some View {
        overlay(alignment: Alignment(horizontal: .center, vertical: .lastTextBaseline)) {
            if let color {
                DottedRule()
                    .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [2, 2]))
                    .frame(height: 2)
                    .alignmentGuide(.lastTextBaseline) { _ in -below }
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct DottedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Words left to right, wrapping onto new rows; rows align on the chips' tops.
struct WordFlow: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + verticalSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + horizontalSpacing + size.width
            if !current.indices.isEmpty, needed > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + horizontalSpacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
