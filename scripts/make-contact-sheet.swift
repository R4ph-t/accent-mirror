// Builds a contact sheet of UI-shell screenshots: every fixture for one theme, downscaled, in a labelled grid.
// Local only, for review (spec 19).
//
//   swift scripts/make-contact-sheet.swift screenshots/ui-shell light docs/screenshots/ui-shell/contact-sheet-light.png
import AppKit

let args = CommandLine.arguments
guard args.count == 4 else {
    print("usage: make-contact-sheet.swift <dir> <light|dark> <out.png>"); exit(2)
}
let dir = URL(fileURLWithPath: args[1]), theme = args[2], out = URL(fileURLWithPath: args[3])
let suffix = "-\(theme)@2x.png"
let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
    .filter { $0.hasSuffix(suffix) }.sorted()
guard !names.isEmpty else { print("no \(theme) screenshots in \(dir.path)"); exit(1) }

let env = ProcessInfo.processInfo.environment
let columns = Int(env["SHEET_COLUMNS"] ?? "") ?? 5
let tileWidth = Double(env["SHEET_TILE_WIDTH"] ?? "") ?? 480
let tile = CGSize(width: tileWidth, height: tileWidth * 2 / 3), caption: CGFloat = 30, gap: CGFloat = 16
let rows = (names.count + columns - 1) / columns
let size = CGSize(width: CGFloat(columns) * (tile.width + gap) + gap,
                  height: CGFloat(rows) * (tile.height + caption + gap) + gap)
let dark = theme == "dark"
let background = dark ? NSColor(srgbRed: 0.07, green: 0.067, blue: 0.063, alpha: 1) : NSColor(srgbRed: 0.937, green: 0.925, blue: 0.902, alpha: 1)
let ink = dark ? NSColor(srgbRed: 0.95, green: 0.94, blue: 0.91, alpha: 1) : NSColor(srgbRed: 0.11, green: 0.10, blue: 0.09, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
background.setFill()
NSRect(origin: .zero, size: size).fill()
let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
for (index, file) in names.enumerated() {
    let column = index % columns, row = index / columns
    let x = gap + CGFloat(column) * (tile.width + gap)
    let top = gap + CGFloat(row) * (tile.height + caption + gap)
    let y = size.height - top - tile.height
    if let image = NSImage(contentsOf: dir.appendingPathComponent(file)) {
        image.draw(in: NSRect(x: x, y: y, width: tile.width, height: tile.height))
    }
    let label = String(file.dropLast(suffix.count)) as NSString
    label.draw(at: NSPoint(x: x, y: y - caption + 7), withAttributes: [.font: font, .foregroundColor: ink])
}
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path) (\(names.count) fixtures, \(Int(size.width)) × \(Int(size.height)) px)")
