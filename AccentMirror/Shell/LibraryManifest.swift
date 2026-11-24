import Foundation

/// Starter library manifest stub (spec 18). Spec 15 supplies the real manifest. A pack with zero phrases is
/// "coming soon" because it is empty, not because of its name.
struct LibraryManifest: Codable, Equatable, Sendable {
    struct Phrase: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var text: String
        /// The phrase's target words, when the starter manifest names them (spec v2). They add to the pitch
        /// plot's target words (stressed and named words), never replace them (Addendum r4 C6).
        var targets: [String]? = nil
    }

    struct Pack: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var phrases: [Phrase]
        var isComingSoon: Bool { phrases.isEmpty }
    }

    var packs: [Pack]
}

/// What the sidebar shows: the manifest, the selected phrase and which packs are open.
struct SidebarState: Codable, Equatable, Sendable {
    var selectedPhraseID: String?
    var expandedPackIDs: [String]
}

extension LibraryManifest {
    /// Static stub used until spec 15: the imported Photography clip under My Phrases, real VCTK shared-text
    /// starter phrases in the other packs, and an empty Noun and Verb Pairs pack.
    static let stub = LibraryManifest(packs: [
        Pack(id: "my-phrases", title: "My Phrases", phrases: [
            Phrase(id: "photography", text: "Photography is harder than it looks."),
            Phrase(id: "walkthrough", text: "Let me walk you through the details of the plan."),
        ]),
        Pack(id: "stress-shifts", title: "Stress Shifts", phrases: [
            Phrase(id: "complicated-ideas", text: "Many complicated ideas about the rainbow have been formed."),
            Phrase(id: "tried-to-explain", text: "Others have tried to explain the phenomenon physically."),
            Phrase(id: "accepted-miracle", text: "Some have accepted it as a miracle without physical explanation."),
        ]),
        Pack(id: "noun-verb-pairs", title: "Noun and Verb Pairs", phrases: []),
        Pack(id: "compound-nouns", title: "Compound Nouns", phrases: [
            Phrase(id: "sunlight-raindrops", text: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow."),
        ]),
        Pack(id: "weak-forms", title: "Weak Forms", phrases: [
            Phrase(id: "call-stella", text: "Please call Stella."),
        ]),
    ])
}

extension SidebarState {
    static let stub = SidebarState(selectedPhraseID: "photography", expandedPackIDs: ["my-phrases", "stress-shifts"])
}
