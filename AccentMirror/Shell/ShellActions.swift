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
    /// The Input pop-up: the devices and the one used for the next take.
    var inputs: [(id: String, name: String)] = []
    var selectedInput: String?
    var selectInput: @MainActor (String) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var shellActions = ShellActions()
}
