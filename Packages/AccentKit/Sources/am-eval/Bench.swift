// Spec 12's latency bench (first v2 §10): L_stop, L_speech and the L2 recompute for 3, 15 and 20 s takes, 10 runs
// each, with the real WhisperKit model warm, on this Mac. Local only (it runs ASR); never CI. The takes are the
// committed smoke set's VCTK clips (CC BY 4.0) joined end to end: p245 is you, p288 the selected voice, p360 the
// voice switched to.

import AMAlignment
import AMCore
import AMEvaluation
import AMLibrary
import AMPipeline
import Foundation

func bench(_ args: Arguments, root: URL) async throws -> Int32 {
    let runs = Int(args.value("runs") ?? "10") ?? 10
    let modelDir = args.value("model-dir").map(URL.init(fileURLWithPath:))
        ?? ProcessInfo.processInfo.environment["MODELS_CACHE"].map { URL(fileURLWithPath: $0).appendingPathComponent(Paths.whisperModel) }
        ?? root.appendingPathComponent(".cache/models/\(Paths.whisperModel)")
    let manifest = try ModelManifest(contentsOf: root.appendingPathComponent("Resources/Models/\(Paths.whisperModel)/manifest.json"))
    let host = SpeechModelHost.whisperKit(folder: modelDir, manifest: manifest)
    let loadStart = ContinuousClock.now
    do {
        _ = try await host.timestamper()
    } catch {
        print("bench: model unavailable (\(error.failure)) at \(modelDir.path): run scripts/fetch-models.sh")
        return 1
    }
    print("bench: \(manifest.asrModelID) loaded, verified and warmed up in \(ms(ContinuousClock.now - loadStart))")
    print("bench: \(ProcessInfo.processInfo.hostName.isEmpty ? "this Mac" : "this Mac"), \(ProcessInfo.processInfo.operatingSystemVersionString), \(ProcessInfo.processInfo.activeProcessorCount) cores; budgets are for an M1 with the model warm")

    let selector = try PronunciationSelector.bundled()
    let dictionary = try PronouncingDictionary.bundled()
    let smoke = root.appendingPathComponent(Paths.smoke)
    let inputs = try JSONDecoder().decode(
        PlacementFixtureFile.self, from: Data(contentsOf: root.appendingPathComponent("\(Paths.smokeDetector)/inputs.json")))
    let items = Dictionary(uniqueKeysWithValues: inputs.items.map { ($0.item, $0) })
    let gap = [Float](repeating: 0, count: Int(0.25 * TakeAudio.sampleRate))

    /// `speaker`'s readings of `prompts`, joined with 250 ms of silence and padded with trailing silence to `seconds`,
    /// and the joined transcript.
    func joined(_ speaker: String, _ prompts: [String], seconds: Double) throws -> (samples: [Float], text: String) {
        var samples: [Float] = []
        var words: [String] = []
        for prompt in prompts {
            let item = try items["vctk-\(speaker)_\(prompt)"].orThrow("no smoke clip vctk-\(speaker)_\(prompt)")
            let (audio, rate) = try AudioFiles.readMono(smoke.appendingPathComponent(item.audio))
            samples += (samples.isEmpty ? [] : gap) + (try AudioFiles.resample(audio, from: rate, to: TakeAudio.sampleRate))
            words += item.words.map(\.text)
        }
        let target = Int(seconds * TakeAudio.sampleRate)
        if samples.count < target { samples += [Float](repeating: 0, count: target - samples.count) }
        return (samples, words.joined(separator: " "))
    }
    let lengths: [(label: String, seconds: Double, prompts: [String], budget: Double)] = [
        ("3 s", 3, ["002"], 2.0),
        ("15 s", 15, ["018", "002", "018"], 3.0),
        ("20 s", 20, ["018", "002", "018", "002"], 3.5),
    ]
    var rows: [String] = []
    var failures = 0
    for length in lengths {
        let you = try joined("p245", length.prompts, seconds: length.seconds)
        let phraseWords = try starterPhraseWords(you.text, selector: selector, dictionary: dictionary).map {
            PlacementTake.Word(
                index: WordIndex($0.index), text: $0.text, pronunciation: try Pronunciation(arpabet: $0.phones),
                accepted: $0.accepted.map(Set.init))
        }
        let phrase = PhraseInput(id: PhraseID("bench-\(length.label)"), words: phraseWords)
        let take = TakeAudio(samples: you.samples, clipID: "bench-you-\(length.label)")
        // The reference side, analysed once (spec 15 ships these precomputed).
        let builder = Analyzer(speech: host, configuration: try .shipped())
        var natives: [NativeRecording] = []
        for speaker in ["p288", "p360"] {
            let audio = TakeAudio(
                samples: try joined(speaker, length.prompts, seconds: length.seconds).samples, clipID: "bench-\(speaker)")
            let record = try await builder.analyseNative(take: audio, phrase: phrase)
            let present = DerivedCoding.native(in: record)?.l1.analysis.segmentation.words.filter { $0.kind == .present }.count ?? 0
            print("bench \(length.label): reference \(speaker) has \(present) of \(phrase.words.count) phrase words present (all are needed to serve as the model)")
            natives.append(NativeRecording(
                id: RecordingID(speaker), voice: speaker, audioSHA256: audio.sha256, analysis: record))
        }
        let reference = EvalReferenceSet(natives: [phrase.id: natives])

        var stops: [Double] = []
        var recomputes: [Double] = []
        var stageTimes: [Stage: [Double]] = [:]
        var outcomes: [String: Int] = [:]
        for _ in 0..<runs {
            // A fresh analyzer each run (empty caches), the same warm model.
            let analyzer = Analyzer(speech: host, configuration: try .shipped())
            let start = ContinuousClock.now
            let run = await analyzer.run(take: take, phrase: phrase, reference: reference, voice: RecordingID("p288"))
            stops.append((ContinuousClock.now - start).inSeconds)
            outcomes[outcomeName(run.response.outcome), default: 0] += 1
            for (stage, seconds) in run.timings { stageTimes[stage, default: []].append(seconds) }
            let switchStart = ContinuousClock.now
            _ = await analyzer.run(take: take, phrase: phrase, reference: reference, voice: RecordingID("p360"))
            recomputes.append((ContinuousClock.now - switchStart).inSeconds)
        }
        let duration = String(format: "%.1f", take.duration)
        let limiting = stageTimes.max { median($0.value) < median($1.value) }
        let stagesLine = Stage.allCases.compactMap { stage in
            stageTimes[stage].map { "\(stage.rawValue) \(ms(median($0)))" }
        }.joined(separator: ", ")
        let stopPass = median(stops) <= length.budget && stops.max()! <= length.budget
        if !stopPass { failures += 1 }
        print("bench \(length.label) (\(duration) s take, \(runs) runs, outcomes \(outcomes.map { "\($0.key) \($0.value)" }.sorted().joined(separator: ", "))):")
        print("  L_stop: median \(seconds(median(stops))), max \(seconds(stops.max()!)) (budget ≤ \(seconds(length.budget))): \(stopPass ? "PASS" : "FAIL")")
        print("  L_speech (auto-endpoint): endpoint wait 1.20 s + L_stop = median \(seconds(1.2 + median(stops))), max \(seconds(1.2 + stops.max()!))")
        print("  endpoint wait: 1.20 s (spec 05's end-of-speech silence, reported on its own line)")
        print("  limiting stage: \(limiting.map { "\($0.key.rawValue) (median \(ms(median($0.value))))" } ?? "–")")
        print("  stages (median): \(stagesLine)")
        var recomputeLine = "  L2 recompute (voice switch): median \(ms(median(recomputes))), max \(ms(recomputes.max()!))"
        if length.label != "20 s" {
            let pass = median(recomputes) <= 0.150
            if !pass { failures += 1 }
            recomputeLine += " (budget ≤ 150 ms median): \(pass ? "PASS" : "FAIL")"
        } else {
            recomputeLine += " (reported; the budget is for 3 s and 15 s)"
        }
        print(recomputeLine)
        rows.append("| \(length.label) (\(duration) s) | \(seconds(median(stops))) / \(seconds(stops.max()!)) | ≤ \(seconds(length.budget)) | \(stopPass ? "PASS" : "FAIL") | \(seconds(1.2 + median(stops))) / \(seconds(1.2 + stops.max()!)) | \(ms(median(recomputes))) / \(ms(recomputes.max()!)) | \(limiting.map { "\($0.key.rawValue) \(ms(median($0.value)))" } ?? "–") |")

        if length.label == "20 s" {
            // Cancel 100 ms into a request (inside ASR): the answer within about 300 ms, the model still loaded.
            var cancels: [Double] = []
            for _ in 0..<runs {
                let analyzer = Analyzer(speech: host, configuration: try .shipped())
                let task = Task(priority: .high) {
                    let response = await analyzer.analyse(
                        take: take, phrase: phrase, reference: reference, voice: RecordingID("p288"))
                    return (response, ContinuousClock.now)
                }
                try await Task.sleep(for: .milliseconds(100))
                let cancelled = ContinuousClock.now
                task.cancel()
                let (response, returned) = await task.value
                if response.outcome == .cancelled { cancels.append((returned - cancelled).inSeconds) }
            }
            let loaded = await host.isLoaded
            let pass = !cancels.isEmpty && cancels.max()! <= 0.300 && loaded
            if !pass { failures += 1 }
            print("bench cancel 100 ms into a 20 s request: \(cancels.count) of \(runs) cancelled, answered after median \(ms(median(cancels))), max \(ms(cancels.max() ?? 0)) (≤ 300 ms); model still loaded: \(loaded), loads \(await host.loadAttempts): \(pass ? "PASS" : "FAIL")")
        }
    }
    print("")
    print("| Take | L_stop median / max | Budget | Result | L_speech median / max | L2 recompute median / max | Limiting stage |")
    print("|---|---|---|---|---|---|---|")
    for row in rows { print(row) }
    print("bench: speculative ASR not built (spec default); L2 budget ≤ 150 ms median on 3 s and 15 s takes")
    return failures == 0 ? 0 : 1
}

private func outcomeName(_ outcome: AnalysisOutcome) -> String {
    switch outcome {
    case .analysed(let result):
        switch result.verdict {
        case .feedback: "feedback"
        case .close: "close"
        case .noClearDifference: "noClearDifference"
        case .inconclusive: "inconclusive"
        }
    case .takeProblem(let problem): "takeProblem(\(problem.rawValue))"
    case .failed(let error): "failed(\(error))"
    case .cancelled: "cancelled"
    }
}

private func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted.count.isMultiple(of: 2) ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
}

private func ms(_ value: Double) -> String { String(format: "%.0f ms", value * 1000) }
private func ms(_ value: Duration) -> String { ms(value.inSeconds) }
private func seconds(_ value: Double) -> String { String(format: "%.2f s", value) }

extension Duration {
    var inSeconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

extension Optional {
    func orThrow(_ message: String) throws -> Wrapped {
        guard let self else { throw CLIError.failed(message) }
        return self
    }
}
