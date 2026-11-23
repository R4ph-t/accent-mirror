import Foundation
import Testing
import AMEvaluation

@Suite("Statistics") struct StatisticsTests {
    func rounded(_ x: Double) -> Double { (x * 10_000).rounded() / 10_000 }

    @Test("Wilson 108/134 is [0.7309, 0.8640], printed as descriptive") func wilsonKnownValue() {
        let interval = Statistics.wilson(successes: 108, n: 134)
        #expect(rounded(interval.lower) == 0.7309)
        #expect(rounded(interval.upper) == 0.8640)
        #expect(interval.label == "descriptive (ignores clustering)")
    }

    @Test("Wilson 107/134 has lower bound 0.7227") func wilsonLowerBound() {
        #expect(rounded(Statistics.wilson(successes: 107, n: 134).lower) == 0.7227)
    }

    @Test("McNemar exact: b = 10, c = 2 gives two-sided p = 0.0386") func mcnemarKnownValue() {
        #expect(rounded(Statistics.mcnemarExact(b: 10, c: 2)) == 0.0386)
        #expect(Statistics.mcnemarExact(b: 2, c: 10) == Statistics.mcnemarExact(b: 10, c: 2))
        #expect(Statistics.mcnemarExact(b: 0, c: 0) == 1)
        #expect(Statistics.mcnemarExact(b: 5, c: 5) == 1)
    }

    static let units: [BootstrapUnit] = (0..<12).flatMap { s in
        (0..<10).map { p in
            BootstrapUnit(speaker: "s\(s)", phrase: "p\(p)", value: (s + p) % 4 == 0 ? 0 : 1, paired: (s * p) % 3 == 0 ? 1 : 0)
        }
    }

    @Test("The bootstraps reproduce from the seed and bracket the point estimate", arguments: [
        ClusteredBootstrap.Clustering.speakers, .speakersAndPhrases,
    ]) func bootstrapIsSeeded(clustering: ClusteredBootstrap.Clustering) {
        let a = ClusteredBootstrap.meanInterval(units: Self.units, clustering: clustering, resamples: 500, seed: 7)
        let b = ClusteredBootstrap.meanInterval(units: Self.units, clustering: clustering, resamples: 500, seed: 7)
        let c = ClusteredBootstrap.meanInterval(units: Self.units, clustering: clustering, resamples: 500, seed: 8)
        #expect(a == b)
        #expect(a != c)
        let mean = Self.units.map(\.value).reduce(0, +) / Double(Self.units.count)
        #expect(a.lower < mean && mean < a.upper)
        #expect(a.label.contains("500 resamples"))
    }

    @Test("Resampling phrases too widens the interval") func twoWayIsWider() {
        let speakers = ClusteredBootstrap.meanInterval(units: Self.units, clustering: .speakers, resamples: 2000, seed: 1)
        let twoWay = ClusteredBootstrap.meanInterval(units: Self.units, clustering: .speakersAndPhrases, resamples: 2000, seed: 1)
        #expect(twoWay.upper - twoWay.lower > speakers.upper - speakers.lower)
        #expect(twoWay.label.starts(with: "two-way clustered bootstrap"))
    }

    @Test("The paired difference interval is centred on D − B") func pairedDifference() {
        let interval = ClusteredBootstrap.pairedDifferenceInterval(units: Self.units, clustering: .speakers, resamples: 1000, seed: 3)
        let d = Self.units.map(\.value).reduce(0, +) / Double(Self.units.count)
        let b = Self.units.map(\.paired).reduce(0, +) / Double(Self.units.count)
        #expect(interval.lower < d - b && d - b < interval.upper)
    }

    @Test("SplitMix64 is fixed: the first outputs for seed 0 never change") func generatorIsFixed() {
        var generator = SeededGenerator(seed: 0)
        #expect(generator.next() == 0xE220_A839_7B1D_CDAF)
        #expect(generator.next() == 0x6E78_9E6A_A1B9_65F4)
    }
}
