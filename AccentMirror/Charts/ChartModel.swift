import Foundation

// Spec 20's `ChartModel`: one value per card (strip, pitch) holding the geometry on the model axis plus every motion
// input, resolved at one clock time. Fixtures (`-UIFixture`) and, later, spec 21 both fill `ChartInputs`; the views
// only draw what `ChartModel.make` returns.

/// What drives the charts besides the static presentation.
struct ChartInputs: Sendable {
    /// What plays and where; nil when nothing plays (or during Play Both's pause).
    var playback: PlaybackPosition?
    /// Your time to model time and back, for the playhead on the other row and the pitch plot.
    var timeMap: (any ChartTimeMap)?
    /// The word whose label the pointer is over (phrase word index), and when the hover began.
    var hoveredWord: Int?
    var hoverStart = 0.0
    /// The word a label click is looping, its name for the header, and when the loop began.
    var loopingWord: Int?
    var loopingLabel: String?
    var loopStart = 0.0
    /// The ghosts drawn before the last change (⇧⌘G, or a newly saved take) and that change's fade.
    var ghostsBefore: [EarlierTakeLine] = []
    var ghostTransition: ChartTransition?
    /// Hovering a take in the open take menu: that take is the only ghost.
    var menuPreview: [EarlierTakeLine]?
    /// The drawing before a voice switch and the 150 ms ease onto the new voice; nil once it is done.
    var voiceFrom: (strip: StripPresentation, pitch: PitchPresentation)?
    var voiceTransition: ChartTransition?
    /// The live row's model duration, for the recording time scale.
    var modelSeconds = 2.0

    /// True while something on the charts still moves at `now`.
    func isMoving(at now: Double) -> Bool {
        playback != nil
            || (hoveredWord != nil && now < hoverStart + ChartMotion.highlightFade)
            || (loopingWord != nil && now < loopStart + ChartMotion.highlightFade)
            || ghostTransition?.isRunning(at: now) == true
            || voiceTransition?.isRunning(at: now) == true
    }
}

/// The hover or loop box: one word, at the hover or the stronger loop fill, faded in by `opacity`.
struct ChartHighlight: Equatable, Sendable {
    enum Strength: Equatable, Sendable { case hover, loop }
    var word: Int
    var strength: Strength
    var opacity: Double
}

/// The strip card's header note, at the right: the loop label wins over "Playing …".
enum StripHeaderNote: Equatable, Sendable {
    case playing(PlaybackSchedule.Side)
    case looping(String)
}

struct StripChart: Sendable {
    var strip: StripPresentation
    var playhead: PlayheadPlacement?
    /// The syllable being played on each row (indices into `strip.native` and your clusters).
    var playing: (native: Int?, you: Int?) = (nil, nil)
    var header: StripHeaderNote?
    var highlight: ChartHighlight?
    var modelSeconds: Double
}

struct PitchChart: Sendable {
    var pitch: PitchPresentation
    /// The playhead on model time, 0…1.
    var playhead: Double?
    /// The hover or loop column over the word's model time.
    var highlight: ChartHighlight?
}

enum ChartModel {
    /// Resolves both cards at clock time `now`.
    static func make(_ detail: DetailPresentation, inputs: ChartInputs, now: Double, reduceMotion: Bool)
        -> (strip: StripChart, pitch: PitchChart) {
        var strip = detail.strip
        var pitch = detail.pitch

        if let from = inputs.voiceFrom {
            let p = inputs.voiceTransition?.progress(at: now, reduceMotion: reduceMotion) ?? 0
            strip = VoiceBlend.strip(from.strip, strip, p)
            pitch = VoiceBlend.pitch(from.pitch, pitch, p)
        }

        if let preview = inputs.menuPreview {
            pitch.earlier = preview
        } else if let transition = inputs.ghostTransition {
            pitch.earlier = GhostBlend.blend(from: inputs.ghostsBefore, to: pitch.earlier,
                                             progress: transition.progress(at: now, reduceMotion: reduceMotion))
        }

        let placement = inputs.playback.map { PlayheadPlacement.place($0, map: inputs.timeMap) }
        var playing: (native: Int?, you: Int?) = (nil, nil)
        if let playback = inputs.playback {
            playing = PlayingSyllable.outline(playback, native: strip.native, you: strip.yourClusters, pairs: strip.pairs)
        }

        var header: StripHeaderNote?
        if let label = inputs.loopingLabel {
            header = .looping(label)
        } else if let side = inputs.playback?.side {
            header = .playing(side)
        }

        var highlight: ChartHighlight?
        if let word = inputs.loopingWord {
            highlight = ChartHighlight(word: word, strength: .loop, opacity: fade(since: inputs.loopStart, now, reduceMotion))
        } else if let word = inputs.hoveredWord {
            highlight = ChartHighlight(word: word, strength: .hover, opacity: fade(since: inputs.hoverStart, now, reduceMotion))
        }

        return (
            StripChart(strip: strip, playhead: placement, playing: playing, header: header, highlight: highlight,
                       modelSeconds: inputs.modelSeconds),
            PitchChart(pitch: pitch, playhead: placement?.pitch, highlight: highlight)
        )
    }

    /// The boxes fade in over 120 ms; with Reduce Motion they appear at once.
    static func fade(since start: Double, _ now: Double, _ reduceMotion: Bool) -> Double {
        ChartTransition(start: start, duration: ChartMotion.highlightFade).progress(at: now, reduceMotion: reduceMotion)
    }
}

extension StripPresentation {
    /// Your row's syllables when it shows bars, else none.
    var yourClusters: [StripCluster] {
        switch you {
        case .bars(let clusters, _, _): clusters
        default: []
        }
    }
}
