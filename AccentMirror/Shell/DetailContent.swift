import SwiftUI

/// Spec 18 leaves the detail as an empty token surface that respects the card column (x 256 to 1184).
/// Spec 19 fills it from fixtures.
struct DetailContent: View {
    @Environment(\.palette) private var palette
    var model: ShellModel

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .surface(palette.surfaceCard, cornerRadius: Metrics.cardRadius)
    }
}

/// The Details inspector body. Spec 19 lists measure states and stress lines here.
struct InspectorContent: View {
    @Environment(\.palette) private var palette
    var model: ShellModel

    var body: some View {
        Text("DETAILS")
            .typeRole(.mono)
            .foregroundStyle(palette.textSecondary)
            .padding(Metrics.outer)
    }
}
