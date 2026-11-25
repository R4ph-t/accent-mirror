import SwiftUI

/// v5 §4: the Rhythm and pitch row, a 44 pt card collapsed by default. Expanded, the v3.4 syllable strip and the
/// pitch card show below it as they were, with no marks, no `%` and no verdict copy.
struct RhythmPitchDisclosure: View {
    @Environment(\.palette) private var palette
    var expanded: Bool
    var toggle: () -> Void

    static let height: CGFloat = 44

    var body: some View {
        FocusRingButton(cornerRadius: Metrics.cardRadius, action: toggle) { _ in
            HStack(spacing: 8) {
                Text(Copy.rhythmAndPitch)
                    .typeRole(.bodyMedium)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Text(expanded ? Copy.hide : Copy.show)
                        .typeRole(.body)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 12)
                }
                .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, Metrics.outer)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .surface(palette.surfaceCard, cornerRadius: Metrics.cardRadius)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.rhythmAndPitch)
        .accessibilityValue(expanded ? Copy.expanded : Copy.collapsed)
        .accessibilityHint(expanded ? Copy.hideRhythmAndPitch : Copy.showRhythmAndPitch)
        .accessibilityAddTraits(.isButton)
    }
}
