import CoreText
import SwiftUI

/// Type roles from spec 18 (Designer spec v2 §4.5). Views use these roles, never raw font names or sizes.
enum TypeRole {
    /// Phrase title in the toolbar: Funnel Display 16 / 600, tracking −0.1.
    case phraseTitle
    /// UI text, diff sentences, sidebar rows: Geist 13 / 400.
    case body
    /// Selected sidebar row: Geist 13 / 600.
    case bodySemibold
    /// Bold caps inside sentences (stressed syllables): Geist 13 / 700.
    case bodyBold
    /// Secondary text, subtitles, syllable labels: Geist 12 / 400.
    case small
    /// Stressed syllable labels: Geist 12 / 700 caps.
    case smallBold
    /// Section headers, card titles, row labels, take menu, axis labels: Geist Mono 12 / 500, caps, tracking 0.6.
    case mono

    var fontName: String {
        switch self {
        case .phraseTitle: BundledFonts.funnelDisplaySemiBold
        case .body, .small: BundledFonts.geistRegular
        case .bodySemibold: BundledFonts.geistSemiBold
        case .bodyBold, .smallBold: BundledFonts.geistBold
        case .mono: BundledFonts.geistMonoMedium
        }
    }

    var size: CGFloat {
        switch self {
        case .phraseTitle: 16
        case .body, .bodySemibold, .bodyBold: 13
        case .small, .smallBold, .mono: 12
        }
    }

    var tracking: CGFloat {
        switch self {
        case .phraseTitle: -0.1
        case .mono: 0.6
        default: 0
        }
    }

    var font: Font { .custom(fontName, fixedSize: size) }

    /// The bundled fonts have no italic face (spec 18 lists only upright weights), so italics are a
    /// slanted copy of the same face. See "Spec gaps" in the PR.
    var italicFont: Font {
        let slant = CGAffineTransform(a: 1, b: 0, c: tan(10 * .pi / 180), d: 1, tx: 0, ty: 0)
        var matrix = slant
        return Font(CTFontCreateWithName(fontName as CFString, size, &matrix))
    }
}

extension View {
    /// Applies a type role: font and tracking. Mono roles are also upper-cased by the caller's string.
    func typeRole(_ role: TypeRole, italic: Bool = false) -> some View {
        font(italic ? role.italicFont : role.font).tracking(role.tracking)
    }
}

extension Text {
    func typeRole(_ role: TypeRole, italic: Bool = false) -> Text {
        font(italic ? role.italicFont : role.font).tracking(role.tracking)
    }
}
