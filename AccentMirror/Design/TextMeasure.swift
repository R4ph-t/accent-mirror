import AppKit

/// Width of a single line of text in a type role, as SwiftUI draws it: the role's bundled face, size and tracking.
/// Label layout uses it to decide which labels fit (see `LabelLayout`).
@MainActor
enum TextMeasure {
    private static var cache: [String: CGFloat] = [:]

    static func width(_ text: String, role: TypeRole, italic: Bool = false) -> CGFloat {
        let fontName = italic ? role.italicFontName : role.fontName
        let key = "\(fontName)|\(role.size)|\(role.tracking)|\(text)"
        if let cached = cache[key] { return cached }
        let font = NSFont(name: fontName, size: role.size) ?? .systemFont(ofSize: role.size)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .kern: role.tracking])
        let width = ceil(attributed.size().width)
        cache[key] = width
        return width
    }
}
