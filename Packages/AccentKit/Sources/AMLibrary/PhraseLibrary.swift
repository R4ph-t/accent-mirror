// The phrases the sidebar lists (spec 17): the bundled starter packs, then My Phrases. One `ReferenceSet` over both,
// so the analyzer and the take store read a phrase's natives the same way wherever it comes from.

import AMCore
import Foundation

public struct PhraseLibrary: ReferenceSet {
    public let starter: ReferenceLibrary?
    public let myPhrases: MyPhraseStore

    public init(starter: ReferenceLibrary?, myPhrases: MyPhraseStore) {
        self.starter = starter
        self.myPhrases = myPhrases
    }

    /// The starter packs, in the manifest's order.
    public var packs: [StarterManifest.Pack] { starter?.manifest.packs ?? [] }

    /// My Phrases, newest first.
    public func myPhraseList() -> [MyPhrase] { myPhrases.phrases() }

    private func set(for phrase: PhraseID) -> any ReferenceSet {
        if myPhrases.phrase(phrase) != nil { return myPhrases }
        if let starter { return starter }
        return myPhrases
    }

    public func identity(phrase: PhraseID, voice: RecordingID) -> ReferenceIdentity {
        set(for: phrase).identity(phrase: phrase, voice: voice)
    }

    public func natives(phrase: PhraseID) async throws(ReferenceSetError) -> [NativeRecording] {
        try await set(for: phrase).natives(phrase: phrase)
    }

    public func rebuild(_ recording: RecordingID, phrase: PhraseID) async throws(ReferenceSetError) {
        try await set(for: phrase).rebuild(recording, phrase: phrase)
    }
}
