// Fails if a UI-shell screenshot is the wrong size, is missing its light/dark twin, or is near-uniform
// (a blank or failed frame). Local only: `make screenshots` runs it; CI does not.
//
//   swift scripts/check-screenshots.swift screenshots/ui-shell
import AppKit

let expected = (width: 2400, height: 1600)
let minDistinctColours = 200 // sampled on a grid; a real frame has thousands
let minLuminanceSpread = 12.0 // standard deviation of luminance, 0–255

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "screenshots/ui-shell")
let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
    .filter { $0.hasSuffix("@2x.png") }.sorted()
var failures: [String] = []
if files.isEmpty { failures.append("no screenshots in \(dir.path)") }

var names = Set<String>()
for file in files {
    let base = file.replacingOccurrences(of: "@2x.png", with: "")
    guard base.hasSuffix("-light") || base.hasSuffix("-dark") else {
        failures.append("\(file): not named <fixture>-{light,dark}@2x.png"); continue
    }
    names.insert(String(base.dropLast(base.hasSuffix("-light") ? 6 : 5)))
    guard let rep = NSBitmapImageRep(data: (try? Data(contentsOf: dir.appendingPathComponent(file))) ?? Data()) else {
        failures.append("\(file): unreadable"); continue
    }
    if rep.pixelsWide != expected.width || rep.pixelsHigh != expected.height {
        failures.append("\(file): \(rep.pixelsWide) × \(rep.pixelsHigh), expected \(expected.width) × \(expected.height)")
        continue
    }
    var colours = Set<UInt32>()
    var sum = 0.0, sumSquares = 0.0, count = 0.0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 8) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            let r = c.redComponent * 255, g = c.greenComponent * 255, b = c.blueComponent * 255
            colours.insert(UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b))
            let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
            sum += l; sumSquares += l * l; count += 1
        }
    }
    let mean = sum / count
    let spread = max(0, sumSquares / count - mean * mean).squareRoot()
    if colours.count < minDistinctColours || spread < minLuminanceSpread {
        failures.append("\(file): near-uniform (\(colours.count) colours, luminance spread \(String(format: "%.1f", spread)))")
    }
}
for name in names.sorted() {
    for theme in ["light", "dark"] where !files.contains("\(name)-\(theme)@2x.png") {
        failures.append("\(name): missing \(theme)")
    }
}

if failures.isEmpty {
    print("check-screenshots: OK, \(files.count) frames (\(names.count) fixtures × light/dark), all \(expected.width) × \(expected.height) and not blank.")
} else {
    failures.forEach { FileHandle.standardError.write(Data("check-screenshots: \($0)\n".utf8)) }
    exit(1)
}
