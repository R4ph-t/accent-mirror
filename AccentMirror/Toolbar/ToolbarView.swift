import SwiftUI

/// The 52 pt toolbar drawn on surface.base (spec 18 §Toolbar). From the right: the inspector toggle, the take
/// menu, You, Record, Model. Play and Record are visual only in this shell: no microphone, no audio.
struct ToolbarView: View {
    @Environment(\.palette) private var palette
    var state: ToolbarState
    var toggleInspector: () -> Void

    var body: some View {
        ToolbarLayout {
            titleBlock
            // The controls keep their full form while they fit next to a 160 pt title; on a narrow detail pane
            // they compact in steps (fixes round 5): Model and You drop their words, then the take menu
            // becomes its chevron, then Record keeps only its dot. Tooltips and VoiceOver keep every word.
            ViewThatFits(in: .horizontal) {
                controls(.full)
                controls(.iconPlayback)
                controls(.compactMenu)
                controls(.minimal)
            }
        }
        .padding(.leading, Metrics.outer)
        .frame(height: Metrics.toolbarHeight)
        .padding(.trailing, Metrics.outer)
    }

    enum Density: Int, Comparable {
        case full, iconPlayback, compactMenu, minimal
        static func < (a: Density, b: Density) -> Bool { a.rawValue < b.rawValue }
    }

    private func controls(_ density: Density) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                GhostButton(title: "Model", isEnabled: state.modelEnabled, showsTitle: density < .iconPlayback)
                RecordButton(state: state.record, showsTitle: density < .minimal)
                GhostButton(title: "You", isEnabled: state.youEnabled, showsTitle: density < .iconPlayback)
            }
            TakeMenu(label: state.takeMenu, note: state.takeMenuNote, savedTakes: state.savedTakes,
                     compact: density >= .compactMenu)
                .padding(.leading, density >= .compactMenu ? 8 : 17)
            InspectorToggle(action: toggleInspector)
                .padding(.leading, density >= .compactMenu ? 8 : 16)
        }
        // Controls keep their size; only the title block truncates.
        .fixedSize()
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(state.title)
                .typeRole(.phraseTitle)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            subtitle
        }
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
    /// False on a narrow toolbar: the play triangle only, the title in the tooltip and for VoiceOver.
    var showsTitle = true

    var body: some View {
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: {}) { _ in
            HStack(spacing: 9) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
                if showsTitle {
                    Text(title)
                        .typeRole(.body)
                }
            }
            .foregroundStyle(isEnabled ? palette.textPrimary : palette.textTertiary)
            .padding(.horizontal, 12)
            .frame(height: Metrics.controlHeight)
            .background {
                if isEnabled {
                    SurfaceBackground(color: palette.surfaceWell, cornerRadius: Metrics.controlRadius)
                }
            }
        }
        .disabled(!isEnabled)
        .help(showsTitle ? "" : "Play \(title)")
        .accessibilityLabel("Play \(title)")
    }
}

/// Record (104 wide, Lime button gradient, onLime text, filled dot) and its recording form, Stop with a filled
/// square in the same Lime.
struct RecordButton: View {
    @Environment(\.palette) private var palette
    var state: ToolbarState.RecordButton
    /// False on the narrowest toolbar: the dot (or Stop's square) only, 40 wide; the word stays in the tooltip and
    /// for VoiceOver.
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
        .help(showsTitle ? "" : (isStop ? "Stop" : "Record"))
        .accessibilityLabel(isStop ? "Stop recording" : "Record")
    }
}

/// "TAKE 03", "TAKES", or "LAST TRY · NOT SAVED" in Geist Mono with a chevron (spec 18, Addendum A7).
struct TakeMenu: View {
    @Environment(\.palette) private var palette
    var label: ToolbarState.TakeMenuLabel
    var note: String?
    var savedTakes: [Int]
    /// True on a narrow toolbar: the chevron only, the title in the tooltip and for VoiceOver.
    var compact = false

    private var title: String {
        switch label {
        case .takes: "TAKES"
        case .take(let number): Self.takeTitle(number)
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
        .help(compact ? (note.map { "\(title) \($0)" } ?? title) : "")
        .accessibilityLabel(note.map { "\(title), \($0)" } ?? title)
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

/// The toolbar row: the title block on the left, the controls on the right. The title block always keeps at least
/// `Metrics.toolbarTitleMinWidth` (160 pt): the controls are offered only what is left after it and a 16 pt gap, so
/// they pick their compact form instead of squeezing the title. Inside the block, the title and subtitle each
/// truncate to the block's width (fixes round 5).
struct ToolbarLayout: Layout {
    static let gap: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? Metrics.toolbarHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let title = subviews[0], controls = subviews[1]
        let room = max(0, bounds.width - Metrics.toolbarTitleMinWidth - Self.gap)
        let controlsProposal = ProposedViewSize(width: room, height: bounds.height)
        let controlsSize = controls.sizeThatFits(controlsProposal)
        controls.place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: controlsProposal)
        let titleWidth = max(Metrics.toolbarTitleMinWidth, bounds.width - controlsSize.width - Self.gap)
        title.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                    proposal: ProposedViewSize(width: titleWidth, height: bounds.height))
    }
}
