import SwiftUI

/// The card column (x 256 to 1184): card 1, the strip card and the pitch card, which fills what is left.
/// With no fixture loaded it is the plain spec 18 surface.
struct DetailContent: View {
    @Environment(\.palette) private var palette
    var model: ShellModel

    var body: some View {
        if let detail = model.detail {
            // r4 C8: on a short window the pitch plot shrinks first, down to `Metrics.pitchPlotMinHeight`; if the
            // cards still don't fit, the card column scrolls and the toolbar (outside it) stays put. Card 1 keeps
            // its size, and its rows may wrap.
            ViewThatFits(in: .vertical) {
                cards(detail)
                ScrollView(.vertical) {
                    cards(detail)
                }
                .scrollIndicators(.automatic)
            }
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .surface(palette.surfaceCard, cornerRadius: Metrics.cardRadius)
        }
    }
}

extension DetailContent {
    private func cards(_ detail: DetailPresentation) -> some View {
        VStack(spacing: Metrics.inner) {
            CardOneView(card: detail.card)
            StripCard(strip: detail.strip)
            PitchCard(pitch: detail.pitch)
        }
    }
}

/// The Details inspector body (§14): measure states, STRESS lines, noClearDifference reasons, quiet notes and
/// the take's save state when it isn't saved.
struct InspectorContent: View {
    @Environment(\.palette) private var palette
    var model: ShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("DETAILS")
                .typeRole(.mono)
                .foregroundStyle(palette.textSecondary)
            let sections = model.detail?.inspector ?? []
            if sections.isEmpty {
                Text("\u{2014}")
                    .typeRole(.small)
                    .foregroundStyle(palette.textSecondary)
            }
            ForEach(sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .typeRole(.mono)
                        .foregroundStyle(palette.textSecondary)
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .typeRole(.small)
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(Metrics.outer)
    }
}
