// Spec 27: `am-eval spike27 --stage prepare|negatives|train|evaluate|all [--write-report] [--jobs 3]`.
// Offline feasibility spike (GO / NO-GO). Caches, PSOLA audio and listen/ live outside the worktree (AM_EVAL_CACHE's
// parent: spike27/, listen/). Reads no held-out, L2 or speechocean762 data before the evaluate stage, and the
// training, τ, variant, arm and envelope code refuses them (Spike27Guard).

import AMCore
import AMEvaluation
import AMSpike27
import Foundation

func spikeLog(_ line: String) {
    print(line)
    fflush(stdout)
}

func spike27(_ args: Arguments, root: URL) async throws -> Int32 {
    let env = try SpikeEnvironment(args, root: root)
    let stage = args.value("stage") ?? "all"
    let stages = stage == "all" ? ["prepare", "negatives", "train", "evaluate"] : stage.split(separator: ",").map(String.init)
    var status: Int32 = 0
    for stage in stages {
        switch stage {
        case "prepare":
            let populations: [Population] = args.value("populations").map {
                $0.split(separator: ",").compactMap { Population(rawValue: String($0)) }
            } ?? [.tuningVCTK, .tts, .bundled, .heldOutVCTK, .speechocean762]
            for population in populations {
                let clips = try await SpikeData.clips(population, env: env, log: spikeLog)
                let words = clips.flatMap { $0.words.values.flatMap { $0 } }
                spikeLog("spike27 prepare: \(population.rawValue) \(clips.count) takes, \(words.count) timed words, "
                         + "\(words.count { $0.target != nil }) with a target")
            }
        case "negatives":
            try await spike27Negatives(env)
        case "train":
            try await spike27Train(env)
        case "evaluate":
            status = try await spike27Evaluate(env, args: args)
        default:
            throw CLIError.usage("spike27 --stage takes prepare, negatives, train, evaluate or all")
        }
    }
    return status
}
