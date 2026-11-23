import SwiftUI

/// The square-cut mark: four columns, ink above the centre line and their secondary reflection below,
/// with one Lime bar crossing both. Measured from the final2 mockups (13 × 15 pt).
struct AppMark: View {
    @Environment(\.palette) private var palette

    // (x, width, top height, bottom height) in points; the centre gap is 1 pt.
    private static let columns: [(x: CGFloat, w: CGFloat, top: CGFloat, bottom: CGFloat)] = [
        (0, 2.25, 4, 2.75),
        (7.25, 2.25, 5, 3.5),
        (10.75, 2.25, 3.25, 1.75),
    ]

    var body: some View {
        Canvas { context, size in
            let centre: CGFloat = 8
            for column in Self.columns {
                context.fill(
                    Path(CGRect(x: column.x, y: centre - column.top, width: column.w, height: column.top)),
                    with: .color(palette.textPrimary)
                )
                context.fill(
                    Path(CGRect(x: column.x, y: centre + 1, width: column.w, height: column.bottom)),
                    with: .color(palette.textSecondary)
                )
            }
            context.fill(
                Path(CGRect(x: 3.5, y: 0, width: 2.5, height: size.height)),
                with: .linearGradient(
                    Gradient(colors: [palette.lime1, palette.lime2]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
        }
        .frame(width: 13, height: 15)
        .accessibilityHidden(true)
    }
}

/// Wordmark: the mark plus "ACCENT MIRROR" in Geist Mono.
struct Wordmark: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 5) {
            AppMark()
            Text("ACCENT MIRROR")
                .typeRole(.mono)
                .foregroundStyle(palette.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Accent Mirror")
    }
}

/// Mirrored bars drawn with the vertical Lime bar gradient. Used by the selected sidebar row (Addendum A1:
/// six bars 1.6 pt wide on a 3 pt pitch, heights 4, 9, 13, 7, 11, 5) and by the "Stressed" legend.
struct LimeBarsGlyph: View {
    @Environment(\.palette) private var palette
    var heights: [CGFloat] = [4, 9, 13, 7, 11, 5]
    var barWidth: CGFloat = 1.6
    var pitch: CGFloat = 3

    static let legendHeights: [CGFloat] = [7, 11, 9]

    var body: some View {
        let height = heights.max() ?? 0
        Canvas { context, size in
            let midY = size.height / 2
            for (index, h) in heights.enumerated() {
                let rect = CGRect(x: CGFloat(index) * pitch, y: midY - h / 2, width: barWidth, height: h)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .linearGradient(
                        Gradient(colors: [palette.lime2, palette.lime1, palette.lime2]),
                        startPoint: CGPoint(x: 0, y: rect.minY),
                        endPoint: CGPoint(x: 0, y: rect.maxY)
                    )
                )
            }
        }
        .frame(width: CGFloat(heights.count - 1) * pitch + barWidth, height: height)
        .accessibilityHidden(true)
    }
}
