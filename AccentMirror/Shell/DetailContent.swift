import SwiftUI

/// The card column (x 256 to 1184): card 1, the strip card and the pitch card, which fills what is left.
/// With no fixture loaded it is the plain spec 18 surface.
struct DetailContent: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var model: ShellModel

    var body: some View {
        if let detail = model.detail {
            // r4 C8: on a short window the pitch plot shrinks first, down to `Metrics.pitchPlotMinHeight`; if the
            // cards still don't fit, the card column scrolls and the toolbar (outside it) stays put. Card 1 keeps
            // its size, and its rows may wrap.
            ViewThatFits(in: .vertical) {
                cards(detail)
                ScrollView(.vertical) {
                    cards(detail)
                }
                .scrollIndicators(.automatic)
            }
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .surface(palette.surfaceCard, cornerRadius: Metrics.cardRadius)
        }
    }
}

extension DetailContent {
    private func cards(_ detail: DetailPresentation) -> some View {
        VStack(spacing: Metrics.inner) {
            CardOneView(card: detail.card, playBoth: model.playBoth)
            // Spec 20: both charts are resolved from `ChartModel` at the chart clock's now. The timeline ticks while
            // something plays or a fade or ease runs (spec 21 wires the audio), and pauses otherwise.
            TimelineView(.animation(paused: model.playback == nil && !model.motionActive)) { _ in
                if let charts = model.charts(systemReduceMotion: reduceMotion) {
                    VStack(spacing: Metrics.inner) {
                        StripCard(chart: charts.strip, playModel: model.playModel, loop: model.loop(word:),
                                  hover: model.hover(word:))
                        PitchCard(chart: charts.pitch)
                    }
                }
            }
        }
        .onKeyPress(.escape) {
            guard model.playback != nil else { return .ignored }
            model.stopPlaying()
            return .handled
        }
    }
}

/// The Details inspector body (v3 §4, v3.1 V4): THIS TAKE (you and the native range, never marked), ALIGNMENT,
/// MODEL RECORDING, and the take's save state when it isn't saved.
struct InspectorContent: View {
    @Environment(\.palette) private var palette
    @Environment(\.shellActions) private var actions
    var model: ShellModel

    var body: some View {
        let inspector = model.detail?.inspector ?? .empty
        // 24 pt between sections, as in the v3.1b inspector mockup.
        VStack(alignment: .leading, spacing: 24) {
            Text("DETAILS")
                .typeRole(.mono)
                .foregroundStyle(palette.textSecondary)
            if inspector == .empty {
                Text("\u{2014}")
                    .typeRole(.small)
                    .foregroundStyle(palette.textSecondary)
            }
            if !inspector.measures.isEmpty {
                thisTake(inspector)
            }
            if let alignment = inspector.alignment {
                // v3.1b mockup: the value at the left, the note right-aligned, one 32 pt row over a hairline.
                section(ThisTake.alignmentTitle) {
                    VStack(spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(alignment)
                                .typeRole(.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer(minLength: 0)
                            Text(ThisTake.alignmentNote)
                                .typeRole(.small)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(height: 32)
                        Hairline()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let recording = inspector.model {
                section(Copy.modelRecording) {
                    VStack(alignment: .leading, spacing: 4) {
                        if recording.voices.count > 1 {
                            // The voice pop-up (r6 E7, spec 15): rows in manifest order, "p311 · M" after each;
                            // disabled while recording (E8).
                            let tags = actions.isLive ? actions.voiceTags : recording.tags
                            let selected = actions.isLive ? actions.selectedVoice : recording.selectedIndex
                            Menu {
                                ForEach(Array(recording.voices.enumerated()), id: \.offset) { index, voice in
                                    Button {
                                        actions.selectVoice(index)
                                    } label: {
                                        if tags.indices.contains(index) {
                                            Text("\(voice)   \(Text(tags[index]).font(TypeRole.mono.fontSized(12)))")
                                        } else {
                                            Text(voice)
                                        }
                                        if index == selected { Image(systemName: "checkmark") }
                                    }
                                }
                            } label: {
                                Text(recording.title)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                            .typeRole(.body)
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize()
                            .disabled(actions.voiceDisabled)
                            .help(actions.voiceDisabled ? Copy.voiceDisabledTooltip : "")
                            .accessibilityLabel("\(Copy.voice), \(recording.title)")
                            .overlay(alignment: .topLeading) {
                                if recording.isOpen {
                                    OpenVoiceMenu(rows: recording.voices, tags: tags, selected: selected)
                                        .offset(x: -VoiceMenuMetrics.sideInset, y: VoiceMenuMetrics.belowButton)
                                }
                            }
                            .zIndex(1)
                        } else {
                            Text(recording.title)
                                .typeRole(.body)
                                .foregroundStyle(palette.textPrimary)
                        }
                        Text(recording.attribution)
                            .typeRole(.small)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            if actions.isLive, !actions.inputs.isEmpty {
                // The Input pop-up (v1 §9): spec 14's devices, used for the next take and remembered. No level here
                // (E5: the meter lives in the recording row only).
                section(Copy.input) {
                    Picker(Copy.input, selection: Binding(
                        get: { actions.selectedInput ?? actions.inputs.first?.id ?? "" },
                        set: { actions.selectInput($0) }
                    )) {
                        ForEach(actions.inputs, id: \.id) { input in
                            Text(input.name).tag(input.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(actions.voiceDisabled)
                }
            }
            if let status = inspector.takeStatus {
                section("TAKE") {
                    Text(status)
                        .typeRole(.small)
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(Metrics.outer)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .typeRole(.mono)
                .foregroundStyle(palette.textSecondary)
            content()
        }
    }

    /// Three columns at 13 pt with 32 pt rows; every value drawn the same way, inside the native range or not.
    private func thisTake(_ inspector: InspectorPresentation) -> some View {
        section(ThisTake.title) {
            VStack(alignment: .leading, spacing: 0) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                    GridRow {
                        Text(ThisTake.headers.measure)
                        Text(ThisTake.headers.you).gridColumnAlignment(.trailing)
                        Text(ThisTake.headers.native).gridColumnAlignment(.trailing)
                    }
                    // The column headers are Geist Mono 11 / 500, 24 pt tall (v3.1b mockup).
                    .font(TypeRole.mono.fontSized(11))
                    .tracking(TypeRole.mono.tracking)
                    .foregroundStyle(palette.textTertiary)
                    .frame(height: 24)
                    ForEach(Array(inspector.measures.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.name)
                                .foregroundStyle(palette.textPrimary)
                                .help(row.nameTooltip ?? "")
                            Text(row.you)
                                .foregroundStyle(palette.textPrimary)
                                .help(row.youTooltip ?? "")
                            Text(row.native)
                                .foregroundStyle(palette.textSecondary)
                                .help(row.nativeTooltip ?? "")
                        }
                        .typeRole(.body)
                        .lineLimit(1)
                        .frame(height: 32)
                        .accessibilityElement(children: .combine)
                        Hairline()
                            .gridCellUnsizedAxes(.horizontal)
                    }
                }
                if let note = inspector.measuresNote {
                    Text(note)
                        .typeRole(.small)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }
        }
    }
}

enum VoiceMenuMetrics {
    /// The open menu spans the inspector less 8 pt each side, starting 8 pt left of the content edge.
    static let sideInset: CGFloat = 8
    static let width: CGFloat = Metrics.inspectorWidth - 2 * sideInset
    static let belowButton: CGFloat = 22
    static let rowHeight: CGFloat = 22
}

/// The Model Voice pop-up drawn open, for the `voice-popup-open` fixture (v3.2 W2, r6 E7): a menu panel on
/// surface.card with a hairline and a soft shadow; each row is "{region} ({accent})" in Geist 13 with the
/// "p311 · M" tag right-aligned in Geist Mono 12 tertiary, and the selected row checked. Manifest order.
private struct OpenVoiceMenu: View {
    @Environment(\.palette) private var palette
    var rows: [String]
    var tags: [String]
    var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 0) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(index == selected ? 1 : 0)
                        .frame(width: 12, alignment: .leading)
                        .padding(.trailing, 4)
                    Text(row)
                        .typeRole(.body)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    if tags.indices.contains(index) {
                        Text(tags[index])
                            .font(TypeRole.mono.fontSized(12))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(palette.textPrimary)
                .padding(.leading, 6)
                .padding(.trailing, 8)
                .frame(height: VoiceMenuMetrics.rowHeight)
            }
        }
        .padding(.vertical, 5)
        .frame(width: VoiceMenuMetrics.width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .fill(palette.surfaceCard)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 1)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.voice)
    }
}
