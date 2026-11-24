import AppKit
import SwiftUI

/// The 52 pt toolbar drawn on surface.base (spec 18 §Toolbar). From the right: the inspector toggle, the take
/// menu, You, Record, Model. Play and Record are visual only in this shell: no microphone, no audio.
struct ToolbarView: View {
    @Environment(\.palette) private var palette
    var state: ToolbarState
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
                GhostButton(title: "Model", isEnabled: state.modelEnabled, showsTriangle: level < .wordsOnly)
                RecordButton(state: state.record, showsTitle: level < .recordDot)
                GhostButton(title: "You", isEnabled: state.youEnabled, showsTriangle: level < .wordsOnly)
            }
            TakeMenu(label: state.takeMenu, note: state.takeMenuNote, savedTakes: state.savedTakes,
                     compact: level >= .menuChevron)
                .padding(.leading, ToolbarCompaction.ControlWidths.takeMenuGap)
            InspectorToggle(action: toggleInspector)
                .padding(.leading, ToolbarCompaction.ControlWidths.toggleGap)
        }
        // Controls keep their size; only the title block truncates.
        .fixedSize()
    }

    /// Each control's drawn width in its full and compact forms, from the same faces, sizes and paddings the
    /// buttons use.
    static func controlWidths(for state: ToolbarState) -> ToolbarCompaction.ControlWidths {
        func ghost(_ title: String, triangle: Bool) -> Double {
            let text = Double(TextMeasure.width(title, role: .body))
            return triangle
                ? GhostButton.sidePadding + Double(GhostButton.playGlyphWidth) + GhostButton.glyphSpacing + text + GhostButton.sidePadding
                : 2 * GhostButton.wordsOnlySidePadding + text
        }
        return ToolbarCompaction.ControlWidths(
            model: ghost("Model", triangle: true), modelWordsOnly: ghost("Model", triangle: false),
            you: ghost("You", triangle: true), youWordsOnly: ghost("You", triangle: false),
            takeMenu: Double(TakeMenu.fullWidth(label: state.takeMenu, note: state.takeMenuNote))
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
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: {}) { _ in
            HStack(spacing: Self.glyphSpacing) {
                if showsTriangle {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                }
                Text(title)
                    .typeRole(.body)
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
    /// False on a narrow toolbar (r4 C7 step 2): the dot (or Stop's square while recording) in the Lime button,
    /// 40 wide; "Record (Space)" in the tooltip and for VoiceOver.
    var showsTitle = true

    var body: some View {
        let isStop = state == .stop
        let isEnabled = state != .record(enabled: false)
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: {}) { _ in
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
    var label: ToolbarState.TakeMenuLabel
    var note: String?
    var savedTakes: [Int]
    /// True on a narrow toolbar (r4 C7 step 1): the chevron only, "Takes" or "Take 03" in the tooltip and for
    /// VoiceOver.
    var compact = false

    /// The full form's width: the title (and note) in Geist Mono, 8 pt, the 10 pt chevron; at least 70.
    @MainActor static func fullWidth(label: ToolbarState.TakeMenuLabel, note: String?) -> CGFloat {
        let title = TextMeasure.width(Self.title(label), role: .mono)
        let noteWidth = note.map { 8 + TextMeasure.width($0, role: .mono) } ?? 0
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?.size.width ?? 10
        return max(70, title + noteWidth + 8 + chevron)
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
        "TAKE " + (number < 10 ? "0\(number)" : "\(number)")
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
                    Button(Self.takeTitle(number).capitalized) {}
                }
            }
        } label: {
            if compact {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 28, height: Metrics.controlHeight)
                    .contentShape(Rectangle())
            } else {
                HStack(spacing: 8) {
                    Text(title)
                        .typeRole(.mono)
                        .foregroundStyle(palette.textSecondary)
                    if let note {
                        Text(note)
                            .typeRole(.mono)
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(minWidth: 70)
                .fixedSize()
                .contentShape(Rectangle())
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(compact ? Copy.takeMenuShortLabel(label) : "")
        .accessibilityLabel(compact ? Copy.takeMenuShortLabel(label) : (note.map { "\(title), \($0)" } ?? title))
    }
}

private struct InspectorToggle: View {
    @Environment(\.palette) private var palette
    var action: () -> Void

    var body: some View {
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: action) { _ in
            Image(systemName: "sidebar.right")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 28, height: Metrics.controlHeight)
        }
        .help("Show or hide Details")
        .accessibilityLabel("Details")
    }
}
