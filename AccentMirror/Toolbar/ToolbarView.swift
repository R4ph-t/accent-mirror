import AppKit
import SwiftUI

/// The 52 pt toolbar drawn on surface.base (spec 18 §Toolbar). From the right: the inspector toggle, Input (v3.5),
/// the take menu, You, Record, Model. Play and Record are visual only in this shell: no microphone, no audio.
struct ToolbarView: View {
    @Environment(\.palette) private var palette
    @Environment(\.shellActions) private var actions
    var state: ToolbarState
    /// The Input popover is open: its button is drawn pressed.
    var isInputOpen = false
    /// The Details inspector is open: the toggle's tooltip and VoiceOver say "Hide Details" or "Show Details".
    var inspectorVisible = false
    var toggleInspector: () -> Void
    /// The toolbar's width inside its side padding, measured; it picks the compaction level (r4 C7).
    @State private var available: CGFloat = Metrics.defaultWindow.width - Metrics.sidebarWidth - 2 * Metrics.outer

    var body: some View {
        let decision = ToolbarCompaction.decide(
            available: Double(available),
            controls: Self.controlWidths(for: state)
        )
        HStack(spacing: 0) {
            titleBlock
                .layoutPriority(-1)
            Spacer(minLength: ToolbarCompaction.titleGap)
            controls(decision.level)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
        .padding(.leading, Metrics.outer)
        .frame(height: Metrics.toolbarHeight)
        .padding(.trailing, Metrics.outer)
    }

    /// The controls at one compaction level. The gaps never change (r4 C7: report rather than cramp them).
    private func controls(_ level: ToolbarCompaction.Level) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: ToolbarCompaction.ControlWidths.playbackSpacing) {
                GhostButton(title: "Model", isEnabled: state.modelEnabled, showsTriangle: level < .wordsOnly,
                            action: actions.playModel)
                RecordButton(state: state.record, showsTitle: true, action: actions.record)
                GhostButton(title: "You", isEnabled: state.youEnabled, showsTriangle: level < .wordsOnly,
                            action: actions.playYou)
            }
            TakeMenu(label: state.takeMenu, note: state.takeMenuNote, savedTakes: state.savedTakes,
                     form: level >= .takeCount ? .count : .full)
                .padding(.leading, ToolbarCompaction.ControlWidths.takeMenuGap)
            // v3.6 J1: Input, immediately left of Details; it stays a 28 pt icon at every level.
            InputButton(isOpen: isInputOpen)
                .padding(.leading, ToolbarCompaction.ControlWidths.toggleGap)
            InspectorToggle(isOpen: inspectorVisible, iconOnly: level >= .detailsIcon, action: toggleInspector)
                .padding(.leading, ToolbarCompaction.ControlWidths.inputGap)
        }
        // Controls keep their size; only the title block truncates.
        .fixedSize()
    }

    /// Each control's drawn width in its full and compact forms, from the same faces, sizes and paddings the
    /// buttons use.
    static func controlWidths(for state: ToolbarState) -> ToolbarCompaction.ControlWidths {
        func ghost(_ title: String, triangle: Bool) -> Double {
            let text = Double(TextMeasure.width(title, role: .bodyMedium))
            return triangle
                ? GhostButton.sidePadding + Double(GhostButton.playGlyphWidth) + GhostButton.glyphSpacing + text + GhostButton.sidePadding
                : 2 * GhostButton.wordsOnlySidePadding + text
        }
        return ToolbarCompaction.ControlWidths(
            model: ghost("Model", triangle: true), modelWordsOnly: ghost("Model", triangle: false),
            you: ghost("You", triangle: true), youWordsOnly: ghost("You", triangle: false),
            takeMenu: Double(TakeMenu.fullWidth(label: state.takeMenu, note: state.takeMenuNote)),
            takeMenuCount: Double(TakeMenu.countWidth(label: state.takeMenu)),
            inspectorToggleFull: Double(InspectorToggle.fullWidth)
        )
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(state.title)
                .typeRole(.phraseTitle)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            subtitle
        }
        // The title truncates before any control compacts (r5 D1): the full title in the tooltip, and VoiceOver
        // reads it whole.
        .help(state.title)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var subtitle: some View {
        switch state.subtitle {
        case .source(let text):
            Text(text)
                .typeRole(.small)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        case .recording(let elapsed):
            // Never colour alone: the word RECORDING and the running time carry the state.
            HStack(spacing: 7) {
                Circle().fill(palette.limeText).frame(width: 7, height: 7)
                Text("RECORDING \(elapsed)")
                    .typeRole(.mono)
            }
            .foregroundStyle(palette.limeText)
            .frame(height: 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recording, \(elapsed)")
        }
    }
}

/// Model and You: surface.well ghost buttons with a play triangle, 28 tall, radius 6. Disabled is no fill and
/// tertiary text, never colour alone.
struct GhostButton: View {
    @Environment(\.palette) private var palette
    var title: String
    var isEnabled: Bool
    /// False on the narrowest toolbar (r4 C7 step 3): the word only, with 8 pt side padding. Model and You never
    /// become icon-only.
    var showsTriangle = true
    var action: @MainActor () -> Void = {}

    static let sidePadding: Double = 12
    static let wordsOnlySidePadding: Double = 8
    static let glyphSpacing: Double = 9
    /// The 11 pt `play.fill` symbol's width.
    @MainActor static var playGlyphWidth: CGFloat {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        return NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?.size.width ?? 11
    }

    var body: some View {
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: action) { _ in
            HStack(spacing: Self.glyphSpacing) {
                if showsTriangle {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                }
                Text(title)
                    .typeRole(.bodyMedium)
            }
            .foregroundStyle(isEnabled ? palette.textPrimary : palette.textTertiary)
            .padding(.horizontal, showsTriangle ? Self.sidePadding : Self.wordsOnlySidePadding)
            .frame(height: Metrics.controlHeight)
            .background {
                if isEnabled {
                    SurfaceBackground(color: palette.surfaceWell, cornerRadius: Metrics.controlRadius)
                }
            }
        }
        .disabled(!isEnabled)
        .accessibilityLabel("Play \(title)")
    }
}

/// Record (104 wide, Lime button gradient, onLime text, filled dot) and its recording form, Stop with a filled
/// square in the same Lime.
struct RecordButton: View {
    @Environment(\.palette) private var palette
    var state: ToolbarState.RecordButton
    /// Always true (v3.7 K2): Record keeps its label; it never becomes a bare Lime dot.
    var showsTitle = true
    var action: @MainActor () -> Void = {}

    var body: some View {
        let isStop = state == .stop
        let isEnabled = state != .record(enabled: false)
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: action) { _ in
            HStack(spacing: 9) {
                if isStop {
                    RoundedRectangle(cornerRadius: 2).frame(width: 10, height: 10)
                } else {
                    Circle().frame(width: 10, height: 10)
                }
                if showsTitle {
                    Text(isStop ? "Stop" : "Record")
                        .typeRole(.body)
                }
            }
            .foregroundStyle(isEnabled ? palette.onLime : palette.textTertiary)
            .frame(width: showsTitle ? 104 : 40, height: Metrics.controlHeight)
            .background {
                if isEnabled {
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .fill(palette.buttonGradient)
                        .overlay(alignment: .top) {
                            // White highlight on the top half at 22% (§4.2).
                            UnevenRoundedRectangle(
                                topLeadingRadius: Metrics.controlRadius, topTrailingRadius: Metrics.controlRadius,
                                style: .continuous
                            )
                            .fill(.white.opacity(0.22))
                            .frame(height: Metrics.controlHeight / 2)
                        }
                }
            }
        }
        .disabled(!isEnabled)
        .help(showsTitle ? "" : Copy.recordButtonShortLabel(stop: isStop))
        .accessibilityLabel(showsTitle ? (isStop ? "Stop recording" : "Record") : Copy.recordButtonShortLabel(stop: isStop))
    }
}

/// "TAKE 03", "TAKES", or "LAST TRY · NOT SAVED" in Geist Mono with a chevron (spec 18, Addendum A7).
struct TakeMenu: View {
    @Environment(\.palette) private var palette
    @Environment(\.shellActions) private var actions
    var label: ToolbarState.TakeMenuLabel
    var note: String?
    var savedTakes: [Int]
    enum Form {
        /// "TAKE 03" (or "TAKES" / "LAST TRY · NOT SAVED") plus the chevron.
        case full
        /// The count plus the chevron ("03" ▾). VoiceOver: "Take 3" (v3.6 J2).
        case count
    }

    var form = Form.full

    /// The full form's width: the title (and note) in Geist Mono, 8 pt, the 10 pt chevron; at least 70.
    @MainActor static func fullWidth(label: ToolbarState.TakeMenuLabel, note: String?) -> CGFloat {
        let title = TextMeasure.width(Self.title(label), role: .mono)
        let noteWidth = note.map { 8 + TextMeasure.width($0, role: .mono) } ?? 0
        return max(70, title + noteWidth + 8 + chevronWidth)
    }

    /// The count form's width: "03" (or the full short title when it isn't a numbered take) plus the chevron.
    @MainActor static func countWidth(label: ToolbarState.TakeMenuLabel) -> CGFloat {
        TextMeasure.width(countTitle(label), role: .mono) + 8 + chevronWidth
    }

    @MainActor private static var chevronWidth: CGFloat {
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        return NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?.size.width ?? 10
    }

    private var title: String { Self.title(label) }

    static func title(_ label: ToolbarState.TakeMenuLabel) -> String {
        switch label {
        case .takes: "TAKES"
        case .take(let number): takeTitle(number)
        case .lastTryNotSaved: "LAST TRY · NOT SAVED"
        }
    }

    static func takeTitle(_ number: Int) -> String {
        "TAKE " + padded(number)
    }

    /// The visible count form: "03", or the full short title when the menu isn't on a numbered take.
    static func countTitle(_ label: ToolbarState.TakeMenuLabel) -> String {
        switch label {
        case .take(let number): padded(number)
        case .takes, .lastTryNotSaved: title(label)
        }
    }

    static func padded(_ number: Int) -> String {
        number < 10 ? "0\(number)" : "\(number)"
    }

    var body: some View {
        Menu {
            if label == .lastTryNotSaved {
                // The unsaved last try is a non-selectable label at the top of the menu.
                Text("Last try · not saved")
                Divider()
            }
            if savedTakes.isEmpty {
                Text("No takes yet")
            } else {
                ForEach(savedTakes, id: \.self) { number in
                    Button(Self.takeTitle(number).capitalized) { actions.selectTake(number) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(form == .count ? Self.countTitle(label) : title)
                    .typeRole(.mono)
                    .foregroundStyle(palette.textSecondary)
                if form == .full, let note {
                    Text(note)
                        .typeRole(.mono)
                        .foregroundStyle(palette.textTertiary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(minWidth: form == .full ? 70 : 0)
            .fixedSize()
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(form == .count ? Copy.takeMenuCountLabel(label) : "")
        .accessibilityLabel(form == .count ? Copy.takeMenuCountLabel(label) : (note.map { "\(title), \($0)" } ?? title))
    }
}

private struct InspectorToggle: View {
    @Environment(\.palette) private var palette
    var isOpen: Bool
    /// v3.6 J2: after the title has reached 154 pt, Details becomes this 28 pt `sidebar.trailing` icon.
    var iconOnly: Bool
    var action: () -> Void

    static let iconWidth: CGFloat = 28
    static let sidePadding: CGFloat = 8

    /// The labeled form's width: "Details" in Geist Medium with 8 pt side padding.
    @MainActor static var fullWidth: CGFloat {
        2 * sidePadding + TextMeasure.width(Copy.details, role: .bodyMedium)
    }

    var body: some View {
        let name = isOpen ? Copy.hideDetails : Copy.showDetails
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: action) { _ in
            Group {
                if iconOnly {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 15, weight: .regular))
                        .frame(width: Self.iconWidth, height: Metrics.controlHeight)
                } else {
                    Text(Copy.details)
                        .typeRole(.bodyMedium)
                        .padding(.horizontal, Self.sidePadding)
                        .frame(height: Metrics.controlHeight)
                }
            }
            .foregroundStyle(palette.textSecondary)
        }
        .help(name)
        .accessibilityLabel(name)
    }
}
