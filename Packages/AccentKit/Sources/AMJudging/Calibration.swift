// The per-phone logistic calibration head from the judging spike (`calibrate.py`), exported once by
// `tools/export_judge_calibration.py` into `Resources/calibration.json`. Fitted on speechocean762 train (CC BY 4.0).
// P(error) = sigmoid(b + w·x), x = [g, one-hot(phone), g·one-hot(phone)], g = max(GOP, −20).

import Foundation

struct Calibration: Sendable, Hashable, Decodable {
    let gopClip: Double
    let phones: [String]
    let intercept: Double
    let coefficients: [Double]

    /// The bundled head. A missing or malformed resource is a build error, not a runtime condition.
    static let bundled: Calibration = {
        guard let url = Bundle.module.url(forResource: "calibration", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url),
              let calibration = try? JSONDecoder().decode(Calibration.self, from: data),
              calibration.coefficients.count == 1 + 2 * calibration.phones.count
        else { preconditionFailure("AMJudging: Resources/calibration.json is missing or malformed") }
        return calibration
    }()

    /// P(error) for a unit whose (first member's) stress-stripped phone is `phone`. Nil for a phone the head doesn't
    /// know (never for CMUdict's 39).
    func errorProbability(gop: Double, phone: String) -> Double? {
        guard let k = phones.firstIndex(of: phone) else { return nil }
        let g = max(gop, gopClip)
        let n = phones.count
        let z = intercept + coefficients[0] * g + coefficients[1 + k] + coefficients[1 + n + k] * g
        return 1 / (1 + exp(-z))
    }
}
