import AMAlignment
import AMTimestampEval
import AVFoundation
import Foundation
import Speech

/// Apple SpeechAnalyzer as an optional comparator (CTO decision 2), off the v1 path.
/// It runs only when `AssetInventory` reports its assets already installed; this tool never asks for a download or
/// an install.
enum SpeechComparator {
    static let name = "Apple SpeechAnalyzer (SpeechTranscriber)"
    static let locale = Locale(identifier: "en_US")
    static let notPresent = "comparator not present"

    private static func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                          attributeOptions: [.audioTimeRange])
    }

    /// AssetInventory's status for the transcriber's assets, and whether that is `installed`.
    /// Read-only: nothing is requested, downloaded or installed.
    static func assetStatus() async -> (installed: Bool, description: String) {
        let status = await AssetInventory.status(forModules: [makeTranscriber()])
        return (status == .installed, "\(status)")
    }

    /// Word spans for one audio file, as `WordTimestamp`s (probability 1: SpeechTranscriber gives none here).
    static func words(forFileAt url: URL) async throws -> [WordTimestamp] {
        let transcriber = makeTranscriber()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task {
            var texts: [AttributedString] = []
            for try await result in transcriber.results where result.isFinal {
                texts.append(result.text)
            }
            return texts
        }
        let file = try AVAudioFile(forReading: url)
        if let end = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return words(from: try await collector.value)
    }

    /// Groups timed runs into whitespace-separated words, each spanning its runs' time ranges.
    static func words(from texts: [AttributedString]) -> [WordTimestamp] {
        var words: [WordTimestamp] = []
        var current: WordTimestamp?
        func flush() {
            if let word = current, !word.word.isEmpty { words.append(word) }
            current = nil
        }
        for text in texts {
            for run in text.runs {
                let piece = String(text[run.range].characters)
                guard let range = run.audioTimeRange else { continue }
                let start = range.start.seconds, end = range.end.seconds
                if piece.first?.isWhitespace == true { flush() }
                for (index, part) in piece.split(whereSeparator: \.isWhitespace).enumerated() {
                    if index > 0 { flush() }
                    if var word = current {
                        word.word += part
                        word.end = max(word.end, end)
                        current = word
                    } else {
                        current = WordTimestamp(word: String(part), start: start, end: end, probability: 1)
                    }
                }
                if piece.last?.isWhitespace == true { flush() }
            }
            flush()
        }
        return words
    }
}
