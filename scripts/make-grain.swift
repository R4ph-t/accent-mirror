// Generates the grain tile (spec 18, Addendum A8): a seamless 256 × 256 pt fractal-noise tile,
// exported at 256, 512 and 768 px for 1×, 2× and 3×. Run once by hand; the PNGs are committed and the
// app never generates grain at runtime. Not run by CI.
//
//   swift scripts/make-grain.swift AccentMirror/Assets.xcassets/Grain.imageset
//
// Perlin gradient noise, base frequency ~0.85 per pt (218 lattice cells per tile so it tiles), 2 octaves,
// a fixed seed, so re-running it writes the same pixels.
import AppKit

let tilePoints = 256
let baseCells = 218 // ≈ 0.85 × 256, an integer so the lattice wraps
let seed: UInt64 = 0x4143_4345_4E54 // "ACCENT"

struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct Octave {
    let cells: Int
    var gradients: [(Double, Double)]

    init(cells: Int, rng: inout SplitMix64) {
        self.cells = cells
        gradients = (0..<(cells * cells)).map { _ in
            let angle = Double(rng.next() % 1_000_000) / 1_000_000 * 2 * .pi
            return (cos(angle), sin(angle))
        }
    }

    func value(x: Double, y: Double) -> Double { // x, y in cells
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - Double(x0), fy = y - Double(y0)
        func grad(_ i: Int, _ j: Int, _ dx: Double, _ dy: Double) -> Double {
            let g = gradients[((j % cells + cells) % cells) * cells + ((i % cells + cells) % cells)]
            return g.0 * dx + g.1 * dy
        }
        func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
        let n00 = grad(x0, y0, fx, fy), n10 = grad(x0 + 1, y0, fx - 1, fy)
        let n01 = grad(x0, y0 + 1, fx, fy - 1), n11 = grad(x0 + 1, y0 + 1, fx - 1, fy - 1)
        let u = fade(fx), v = fade(fy)
        let a = n00 + u * (n10 - n00), b = n01 + u * (n11 - n01)
        return a + v * (b - a)
    }
}

var rng = SplitMix64(state: seed)
let octaves = [Octave(cells: baseCells, rng: &rng), Octave(cells: baseCells * 2, rng: &rng)]

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
for scale in 1...3 {
    let size = tilePoints * scale
    var pixels = [UInt8](repeating: 0, count: size * size)
    for py in 0..<size {
        for px in 0..<size {
            // Sample at the pixel centre, in points, so every scale shows the same grain.
            let x = (Double(px) + 0.5) / Double(scale), y = (Double(py) + 0.5) / Double(scale)
            var sum = 0.0, amplitude = 1.0, norm = 0.0
            for octave in octaves {
                let k = Double(octave.cells) / Double(tilePoints)
                sum += amplitude * octave.value(x: x * k, y: y * k)
                norm += amplitude
                amplitude *= 0.5
            }
            let v = max(0, min(1, 0.5 + 1.1 * sum / norm))
            pixels[py * size + px] = UInt8((v * 255).rounded())
        }
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                               colorSpaceName: .calibratedWhite, bytesPerRow: size, bitsPerPixel: 8)!
    pixels.withUnsafeBufferPointer { rep.bitmapData!.update(from: $0.baseAddress!, count: size * size) }
    let name = scale == 1 ? "grain.png" : "grain@\(scale)x.png"
    try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print("wrote \(name) (\(size) × \(size) px)")
}
