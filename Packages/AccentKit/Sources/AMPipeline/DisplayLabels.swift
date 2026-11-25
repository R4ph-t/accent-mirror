// Re-exports display-syllable types and word folding for the app target (which links only AMPipeline).

import AMAlignment

public typealias Hyphenator = AMAlignment.Hyphenator
public typealias DisplaySyllableTable = AMAlignment.DisplaySyllableTable
public typealias DisplaySyllableResolver = AMAlignment.DisplaySyllableResolver

public enum DisplayWord {
    public static func fold(_ text: some StringProtocol) -> String {
        WordText.fold(text)
    }
}
