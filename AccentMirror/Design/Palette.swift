import SwiftUI

/// The single token table for Accent Mirror (spec 18, Designer spec v2 §4 with Addendum r2).
/// Views read colours from here and never hard-code hex or rgba values.
struct Palette: Equatable, Sendable {
    // Surfaces and ink
    var surfaceBase: Color
    var surfaceCard: Color
    var surfaceSidebar: Color
    var surfaceWell: Color
    var hairline: Color
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color
    var stripBar: Color
    /// Your unstressed bars in a result: clearly darker than the native row's strip.bar, so your row reads as a
    /// full waveform (Designer review of PR #4, fix 3).
    var stripBarYou: Color
    var pitchNative: Color
    var pitchYou: Color
    var pitchTexture: Color
    var baseline: Color
    var rowHover: Color

    // Lime and mistakes
    var lime1: Color
    var lime2: Color
    var limeText: Color
    var limeSidebarText: Color
    var buttonA: Color
    var buttonB: Color
    var onLime: Color
    var washOpacity: Double
    var mistake: Color

    // Grain and hairline weight
    var grainOpacity: Double
    var showsGrain: Bool
    var showsPitchTexture: Bool
    /// Hairline weight in points: one device pixel normally, 1 pt with Increase Contrast.
    var hairlineIsThick: Bool

    enum Scheme: Sendable { case light, dark }

    static func resolve(_ scheme: Scheme, increaseContrast: Bool, reduceTransparency: Bool) -> Palette {
        var p = scheme == .light ? light : dark
        if increaseContrast {
            // Spec 18: tertiary becomes secondary, secondary steps darker (light) or brighter (dark),
            // hairlines get 1 pt and one step darker (the next ink step, `baseline`), texture and grain hidden.
            p.textTertiary = p.textSecondary
            p.textSecondary = scheme == .light ? Color(hex: 0x5F5A52) : Color(hex: 0xC2BCB2)
            p.hairline = p.baseline
            p.hairlineIsThick = true
            p.showsGrain = false
            p.showsPitchTexture = false
        }
        if reduceTransparency {
            p.showsGrain = false
        }
        return p
    }

    static let light = Palette(
        surfaceBase: Color(hex: 0xEFECE6),
        surfaceCard: Color(hex: 0xFAF8F4),
        surfaceSidebar: Color(hex: 0xE6E2DA),
        surfaceWell: Color(hex: 0xE2DDD4),
        hairline: Color(hex: 0xDCD6CB),
        textPrimary: Color(hex: 0x1C1A17),
        textSecondary: Color(hex: 0x69645C), // Addendum A2
        textTertiary: Color(hex: 0x9C968B),
        stripBar: Color(rgb: 70, 64, 56, 0.24),
        stripBarYou: Color(rgb: 28, 26, 23, 0.50), // Designer: rgba(28,26,23,0.50)
        pitchNative: Color(rgb: 120, 113, 102, 0.38),
        pitchYou: Color(hex: 0x1C1A17),
        pitchTexture: Color(rgb: 70, 64, 56, 0.055),
        baseline: Color(hex: 0xD3CDC1),
        rowHover: Color(rgb: 60, 50, 35, 0.03),
        lime1: Color(hex: 0x23891C),
        lime2: Color(hex: 0x86C400),
        limeText: Color(hex: 0x2F7A0E),
        limeSidebarText: Color(hex: 0x2A6E0C), // Addendum A1
        buttonA: Color(hex: 0x7ED321),
        buttonB: Color(hex: 0xC2EA2E),
        onLime: Color(hex: 0x122405),
        washOpacity: 0.07,
        mistake: Color(hex: 0x2457E6),
        grainOpacity: 0.045,
        showsGrain: true,
        showsPitchTexture: true,
        hairlineIsThick: false
    )

    static let dark = Palette(
        surfaceBase: Color(hex: 0x171615),
        surfaceCard: Color(hex: 0x211F1D),
        surfaceSidebar: Color(hex: 0x121110),
        surfaceWell: Color(hex: 0x2A2825),
        hairline: Color(hex: 0x2F2D2A),
        textPrimary: Color(hex: 0xF2EFE9),
        textSecondary: Color(hex: 0xA39D93),
        textTertiary: Color(hex: 0x6E6961),
        stripBar: Color(rgb: 240, 235, 225, 0.20),
        // Sampled from mockup-result-dark-final2@2x.png, your row's grey bars (see the PR).
        stripBarYou: Color(rgb: 242, 239, 233, 0.60),
        pitchNative: Color(rgb: 165, 158, 147, 0.40),
        pitchYou: Color(hex: 0xF7F4EE),
        pitchTexture: Color(rgb: 240, 235, 225, 0.045),
        baseline: Color(hex: 0x34322E),
        rowHover: Color(rgb: 255, 255, 255, 0.025),
        lime1: Color(hex: 0xC8F03C),
        lime2: Color(hex: 0x5BE3A6),
        limeText: Color(hex: 0xC6EE4A),
        limeSidebarText: Color(hex: 0xC6EE4A),
        buttonA: Color(hex: 0xC8F03C),
        buttonB: Color(hex: 0x5BE3A6),
        onLime: Color(hex: 0x10200A),
        washOpacity: 0.09,
        mistake: Color(hex: 0x86A8FF),
        grainOpacity: 0.05,
        showsGrain: true,
        showsPitchTexture: true,
        hairlineIsThick: false
    )

    // MARK: Gradients (§4.2)

    /// Horizontal accent gradient, lime.1 to lime.2.
    var accentGradient: LinearGradient {
        LinearGradient(colors: [lime1, lime2], startPoint: .leading, endPoint: .trailing)
    }

    /// Vertical stressed-bar gradient: lime.2 at the tips, lime.1 at the centre line.
    var barGradient: LinearGradient {
        LinearGradient(colors: [lime2, lime1, lime2], startPoint: .top, endPoint: .bottom)
    }

    /// Diagonal Record / Stop button gradient.
    var buttonGradient: LinearGradient {
        LinearGradient(colors: [buttonA, buttonB], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Hex helpers (token table only)

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    fileprivate init(rgb r: Double, _ g: Double, _ b: Double, _ a: Double) {
        self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry var palette: Palette = .light
}

/// Resolves the palette from the system appearance and accessibility settings and injects it.
/// Every SwiftUI root in the app (each split pane is its own hosting tree) is wrapped in this.
struct ThemeRoot<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content

    var body: some View {
        content.environment(
            \.palette,
            Palette.resolve(
                colorScheme == .dark ? .dark : .light,
                increaseContrast: contrast == .increased,
                reduceTransparency: reduceTransparency
            )
        )
    }
}
