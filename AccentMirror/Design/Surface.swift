import SwiftUI

/// Layout measurements from spec 18 (Designer spec v2 §3), in points, for the default 1200 × 800 window.
enum Metrics {
    static let defaultWindow = CGSize(width: 1200, height: 800)
    static let minimumWindow = CGSize(width: 960, height: 680)
    static let sidebarWidth: CGFloat = 240
    static let inspectorWidth: CGFloat = 280
    static let toolbarHeight: CGFloat = 52
    static let outer: CGFloat = 16
    static let inner: CGFloat = 8
    /// Row-label column (x 272 to 336 in the window) relative to the card's inner content edge.
    static let rowLabelWidth: CGFloat = 64
    /// End-label column (x 1120 to 1168): 48 wide, 8 after the plot column.
    static let endLabelWidth: CGFloat = 48
    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 6
    static let markRadius: CGFloat = 4
    static let controlHeight: CGFloat = 28
    static let sidebarRowHeight: CGFloat = 32
}

/// A solid token surface with the grain composited on it (under its text, never over it).
/// Hidden with Reduce Transparency and Increase Contrast via the palette.
struct SurfaceBackground: View {
    @Environment(\.palette) private var palette
    var color: Color
    var cornerRadius: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color)
            .overlay {
                if palette.showsGrain {
                    Image("Grain")
                        .resizable(resizingMode: .tile)
                        .opacity(palette.grainOpacity)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func surface(_ color: Color, cornerRadius: CGFloat = 0) -> some View {
        background(SurfaceBackground(color: color, cornerRadius: cornerRadius))
    }
}

/// A one-device-pixel hairline (1 pt with Increase Contrast).
struct Hairline: View {
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    var axis: Axis = .horizontal

    var body: some View {
        let weight = palette.hairlineIsThick ? 1 : 1 / max(displayScale, 1)
        Rectangle()
            .fill(palette.hairline)
            .frame(width: axis == .vertical ? weight : nil, height: axis == .horizontal ? weight : nil)
    }
}
