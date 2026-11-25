import SwiftUI

/// What the shell's controls do (spec 21). Fixture mode and the screenshot runner keep the default: every control is
/// drawn and does nothing, exactly as specs 18–20 drew it. The live app (`AppModel`) puts its own in the environment.
struct ShellActions {
    /// True outside fixture mode: hides "+ NEW PHRASE" until clip import ships (E6, Designer's call).
    var isLive = false
    var record: @MainActor () -> Void = {}
    var playModel: @MainActor () -> Void = {}
    var playYou: @MainActor () -> Void = {}
    var selectPhrase: @MainActor (String) -> Void = { _ in }
    var selectTake: @MainActor (Int) -> Void = { _ in }
    /// Card 1's row button: Try Again, or Open System Settings… for micDenied.
    var cardButton: @MainActor () -> Void = {}
    var bannerButton: @MainActor () -> Void = {}
    var bannerClose: @MainActor () -> Void = {}
    var copyDetails: @MainActor () -> Void = {}
    /// The Model Voice pop-up (r6 E7): each row's "p225 · F" tag, the selected row, and whether recording disables it.
    var voiceTags: [String] = []
    var selectedVoice: Int?
    var voiceDisabled = false
    var selectVoice: @MainActor (Int) -> Void = { _ in }
    /// The Input popover (v3.5): the chosen input (nil: System Default), opening and closing it, the Mac input volume
    /// and the two settings panes it links to. The device used for the next take is remembered.
    var inputName: String?
    var selectInput: @MainActor (String?) -> Void = { _ in }
    var openInput: @MainActor () -> Void = {}
    var toggleInput: @MainActor () -> Void = {}
    var closeInput: @MainActor () -> Void = {}
    var setInputVolume: @MainActor (Double) -> Void = { _ in }
    var openSoundSettings: @MainActor () -> Void = {}
    var openMicrophonePrivacy: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    @Entry var shellActions = ShellActions()
}
