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
        VStack(alignment: .leading, spacing: 20) {
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
                section(ThisTake.alignmentTitle) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(alignment)
                            .typeRole(.body)
                            .foregroundStyle(palette.textPrimary)
                        Text(ThisTake.alignmentNote)
                            .typeRole(.small)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(height: 32)
                }
            }
            if let recording = inspector.model {
                section(Copy.modelRecording) {
                    VStack(alignment: .leading, spacing: 4) {
                        if recording.voices.count > 1 {
                            // The voice pop-up (r6 E7, spec 15): rows in manifest order, "p225 · F" after each in
                            // the live app; disabled while recording (E8).
                            Menu {
                                ForEach(Array(recording.voices.enumerated()), id: \.offset) { index, voice in
                                    Button {
                                        actions.selectVoice(index)
                                    } label: {
                                        if actions.voiceTags.indices.contains(index) {
                                            Text("\(voice)   \(Text(actions.voiceTags[index]).font(TypeRole.mono.fontSized(12)))")
                                        } else {
                                            Text(voice)
                                        }
                                        if index == actions.selectedVoice { Image(systemName: "checkmark") }
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
                    .typeRole(.mono)
                    .foregroundStyle(palette.textTertiary)
                    .frame(height: 28)
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
