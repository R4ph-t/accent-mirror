import SwiftUI

/// Type roles from spec 18 (Designer spec v2 §4.5). Views use these roles, never raw font names or sizes.
enum TypeRole {
    /// Phrase title in the toolbar: Funnel Display 16 / 600, tracking −0.1.
    case phraseTitle
    /// UI text, diff sentences, sidebar rows: Geist 13 / 400.
    case body
    /// Ghost buttons (Model, You, Play Both, card 1's button): Geist 13 / 500 (v3.2 W3).
    case bodyMedium
    /// Selected sidebar row: Geist 13 / 600.
    case bodySemibold
    /// Bold caps inside sentences (stressed syllables): Geist 13 / 700.
    case bodyBold
    /// Secondary text, subtitles, syllable labels: Geist 12 / 400.
    case small
    /// "Too loud" beside the level meter: Geist 12 / 500 (v3.2 W2, W3).
    case smallMedium
    /// Stressed syllable labels: Geist 12 / 700 caps.
    case smallBold
    /// Section headers, card titles, row labels, take menu, axis labels: Geist Mono 12 / 500, caps, tracking 0.6.
    case mono
    /// v5 §2: a PHRASE card word, Geist 18 / 400 (26 pt line).
    case phraseWord
    /// v5 §2: a flagged PHRASE card word, Geist 18 / 500.
    case phraseWordFlagged
    /// v5 §3: the word popover's header, Geist 15 / 600.
    case popoverTitle

    var fontName: String {
        switch self {
        case .phraseTitle: BundledFonts.funnelDisplaySemiBold
        case .body, .small, .phraseWord: BundledFonts.geistRegular
        case .bodyMedium, .smallMedium, .phraseWordFlagged: BundledFonts.geistMedium
        case .bodySemibold, .popoverTitle: BundledFonts.geistSemiBold
        case .bodyBold, .smallBold: BundledFonts.geistBold
        case .mono: BundledFonts.geistMonoMedium
        }
    }

    var size: CGFloat {
        switch self {
        case .phraseTitle: 16
        case .body, .bodyMedium, .bodySemibold, .bodyBold: 13
        case .small, .smallMedium, .smallBold, .mono: 12
        case .phraseWord, .phraseWordFlagged: 18
        case .popoverTitle: 15
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

    /// The real italic of the same weight, from the bundled Geist italic. Funnel Display and Geist Mono have no
    /// bundled italic and no role uses one, so the phrase title and mono labels stay upright.
    var italicFontName: String {
        switch self {
        case .phraseTitle: BundledFonts.funnelDisplaySemiBold
        case .body, .small, .phraseWord: BundledFonts.geistItalic
        // No role sets a medium run in italics; the Regular italic keeps it in Geist if one ever does.
        case .bodyMedium, .smallMedium, .phraseWordFlagged: BundledFonts.geistItalic
        case .bodySemibold, .popoverTitle: BundledFonts.geistSemiBoldItalic
        case .bodyBold, .smallBold: BundledFonts.geistBoldItalic
        case .mono: BundledFonts.geistMonoMedium
        }
    }

    var italicFont: Font { .custom(italicFontName, fixedSize: size) }
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
