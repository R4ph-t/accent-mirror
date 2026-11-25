import SwiftUI

// Designer addendum v3.5 I2–I6 and v3.6 J3: the toolbar's Input button and the 300 pt Input popover it opens
// (also opened by "Input…" in the inspector and on card 1). The popover is a real macOS NSPopover (SwiftUI's
// `.popover`, system arrow), anchored to the control that opened it. Contents and the 300 pt width are unchanged
// from v3.5 I2.

/// The 28 pt mic ghost button immediately left of Details. Icon only, never hidden or reduced further (v3.6 J1).
struct InputButton: View {
    @Environment(\.palette) private var palette
    @Environment(\.shellActions) private var actions
    var isOpen: Bool

    static let width: CGFloat = 28

    var body: some View {
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: actions.toggleInput) { _ in
            Image(systemName: "mic")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isOpen ? palette.textPrimary : palette.textSecondary)
                .frame(width: Self.width, height: Metrics.controlHeight)
                .background {
                    if isOpen {
                        SurfaceBackground(color: palette.surfaceWell, cornerRadius: Metrics.controlRadius)
                    }
                }
        }
        .help(Copy.inputButton)
        .accessibilityLabel(Copy.inputButton)
        .inputPopover(source: .toolbar)
    }
}

/// The popover's width and inner padding (v3.5 I2); the system arrow sits outside this width (v3.6 J3).
enum InputPopoverMetrics {
    static let width: CGFloat = 300
    static let padding: CGFloat = 16
    static let radius: CGFloat = 10
}

/// Which control an open Input popover is anchored to (v3.6 J3).
enum InputPopoverSource: Equatable, Sendable {
    case toolbar, inspector, card
}

extension View {
    /// Presents the Input popover from this control when it is the active source (v3.6 J3).
    func inputPopover(source: InputPopoverSource) -> some View {
        modifier(InputPopoverAttachment(source: source))
    }
}

private struct InputPopoverAttachment: ViewModifier {
    var source: InputPopoverSource
    @Environment(\.palette) private var palette
    @Environment(\.shellActions) private var actions
    @Environment(\.inputMeter) private var inputMeter
    @Environment(LevelMeterModel.self) private var recordingMeter: LevelMeterModel?
    @Environment(\.inputPopoverState) private var state
    @Environment(\.inputPopoverSource) private var current
    @Environment(\.closeInputPopover) private var onClose

    func body(content: Content) -> some View {
        content.popover(
            isPresented: Binding(
                get: { state != nil && current == source },
                set: { if !$0 { onClose() } }
            ),
            arrowEdge: .bottom
        ) {
            if let state {
                InputPopoverView(state: state, systemChrome: true)
                    .environment(\.palette, palette)
                    .environment(\.shellActions, actions)
                    .environment(\.inputMeter, inputMeter)
                    .environment(recordingMeter)
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var inputPopoverState: InputPopoverState? = nil
    @Entry var inputPopoverSource: InputPopoverSource = .toolbar
    @Entry var closeInputPopover: @MainActor () -> Void = {}
}

struct InputPopoverView: View {
    @Environment(\.palette) private var palette
    @Environment(\.shellActions) private var actions
    var state: InputPopoverState
    /// True when the view sits inside a system NSPopover (v3.6 J3): the arrow and chrome are the system's; we
    /// fill the content with the card surface but drop the floating-card shadow and hairline.
    var systemChrome = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.input)
                .typeRole(.mono)
                .foregroundStyle(palette.textSecondary)
                .padding(.bottom, 12)
            Text(Copy.microphone)
                .typeRole(.small)
                .foregroundStyle(palette.textSecondary)
                .padding(.bottom, 6)
            deviceMenu
            Text(Copy.inputVolume)
                .typeRole(.small)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 16)
                .padding(.bottom, 8)
            VolumeSlider(value: state.sliderValue, isEnabled: state.sliderEnabled) { actions.setInputVolume($0) }
            if state.showsFixedNote {
                HStack(spacing: 8) {
                    Text(Copy.fixedLevel)
                        .typeRole(.small)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    FocusRingButton(cornerRadius: 4, action: actions.openSoundSettings) { _ in
                        Text(Copy.soundSettings)
                            .typeRole(.smallMedium)
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                .padding(.top, 8)
            }
            if state.showsMeter {
                InputMeter(fixed: state.level, isRecording: state.isRecording)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                Text(Copy.inputHint)
                    .typeRole(.small)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            } else if let notice = state.notice {
                noticeView(notice)
                    .padding(.top, 16)
            }
        }
        .padding(InputPopoverMetrics.padding)
        .frame(width: InputPopoverMetrics.width, alignment: .leading)
        .background {
            if systemChrome {
                palette.surfaceCard
            } else {
                RoundedRectangle(cornerRadius: InputPopoverMetrics.radius, style: .continuous)
                    .fill(palette.surfaceCard)
                    .shadow(color: .black.opacity(0.16), radius: 15, y: 10)
            }
        }
        .overlay {
            if !systemChrome {
                RoundedRectangle(cornerRadius: InputPopoverMetrics.radius, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.inputButton)
        .accessibilityAddTraits(.isModal)
    }

    private var selectedName: String {
        state.selected.flatMap { id in state.devices.first { $0.id == id }?.name } ?? Copy.systemDefault
    }

    private var deviceMenu: some View {
        Menu {
            Button {
                actions.selectInput(nil)
            } label: {
                Text(Copy.systemDefault)
                if state.selected == nil { Image(systemName: "checkmark") }
            }
            if !state.devices.isEmpty { Divider() }
            ForEach(state.devices, id: \.id) { device in
                Button {
                    actions.selectInput(device.id)
                } label: {
                    Text(device.name)
                    if state.selected == device.id { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedName)
                    .typeRole(.body)
                    .foregroundStyle(state.deviceMenuEnabled ? palette.textPrimary : palette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: Metrics.controlHeight)
            .surface(palette.surfaceWell, cornerRadius: Metrics.controlRadius)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(!state.deviceMenuEnabled)
        .help(state.isRecording ? Copy.microphoneDisabledTooltip : "")
        .accessibilityLabel("\(Copy.microphone), \(selectedName)")
        .accessibilityHint(state.isRecording ? Copy.microphoneDisabledTooltip : "")
    }

    private func noticeView(_ notice: InputPopoverState.Notice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.takeProblem(notice == .micDenied ? .micDenied : .noMicrophone))
                .typeRole(.small)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if notice == .micDenied, let button = Copy.takeProblemButton(.micDenied) {
                FocusRingButton(cornerRadius: Metrics.controlRadius, action: actions.openMicrophonePrivacy) { _ in
                    Text(button)
                        .typeRole(.bodyMedium)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: Metrics.controlHeight)
                        .surface(palette.surfaceWell, cornerRadius: Metrics.controlRadius)
                }
            }
        }
    }
}

/// The Mac input volume (I1): a 4 pt surface.well track with a text.primary fill and a 14 pt text.primary thumb, no
/// numeric readout, never Lime. Drag or click to set; ←/→ step by 5%. VoiceOver gets a standard slider.
struct VolumeSlider: View {
    @Environment(\.palette) private var palette
    var value: Double
    var isEnabled: Bool
    var onChange: @MainActor (Double) -> Void

    @FocusState private var focused: Bool
    static let thumb: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = CGFloat(min(1, max(0, value))) * width
            ZStack(alignment: .leading) {
                Capsule().fill(palette.surfaceWell).frame(height: 4)
                Capsule().fill(palette.textPrimary.opacity(isEnabled ? 0.55 : 0.2)).frame(width: x, height: 4)
                Circle()
                    .fill(isEnabled ? palette.textPrimary : palette.textTertiary)
                    .frame(width: Self.thumb, height: Self.thumb)
                    .shadow(color: .black.opacity(isEnabled ? 0.25 : 0), radius: 1, y: 1)
                    .overlay {
                        if focused {
                            Circle().strokeBorder(palette.textSecondary, lineWidth: 2).padding(-3)
                        }
                    }
                    .offset(x: min(max(0, x - Self.thumb / 2), width - Self.thumb))
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard isEnabled, width > 0 else { return }
                onChange(Double(min(1, max(0, drag.location.x / width))))
            })
        }
        .frame(height: 16)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-0.05) }
        .onKeyPress(.rightArrow) { step(0.05) }
        .help(isEnabled ? Copy.inputVolumeTooltip : "")
        .accessibilityRepresentation {
            Slider(value: Binding(get: { value }, set: { onChange($0) }), in: 0...1) {
                Text(Copy.inputVolume)
            }
            .disabled(!isEnabled)
        }
    }

    private func step(_ delta: Double) -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        onChange(min(1, max(0, value + delta)))
        return .handled
    }
}

/// The popover's meter (I2): E5's visuals at the full content width. While a take records it shows the take's level
/// (the recording meter); otherwise the popover's own mic check.
private struct InputMeter: View {
    @Environment(LevelMeterModel.self) private var recordingMeter: LevelMeterModel?
    @Environment(\.inputMeter) private var checkMeter
    var fixed: LevelReading?
    var isRecording: Bool

    private var reading: LevelReading {
        if let fixed { return fixed }
        let meter = isRecording ? recordingMeter : checkMeter
        guard let meter, let rms = meter.rmsDBFS else { return LevelReading(rmsDBFS: -60, peakDBFS: -60) }
        return LevelReading(rmsDBFS: rms, peakDBFS: meter.peakDBFS, tooLoud: meter.tooLoud)
    }

    var body: some View {
        LevelMeterBar(reading: reading, trackWidth: nil)
            .frame(height: 16)
    }
}

extension EnvironmentValues {
    /// The Input popover's mic-check meter (nil outside the live app).
    @Entry var inputMeter: LevelMeterModel?
}
