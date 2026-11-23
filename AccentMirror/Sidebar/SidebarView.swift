import SwiftUI

/// The sidebar (spec 18 §Sidebar, Addendum A1/A2). Measurements are from the final2 mockups.
struct SidebarView: View {
    @Environment(\.palette) private var palette
    var manifest: LibraryManifest
    var state: SidebarState

    @State private var expanded: Set<String>?

    private var expandedIDs: Set<String> { expanded ?? Set(state.expandedPackIDs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title-bar row: the traffic lights sit at x 12–68, the wordmark after them.
            Wordmark()
                .padding(.leading, 86)
                .frame(height: Metrics.toolbarHeight, alignment: .center)

            SearchWell()
                .padding(.horizontal, 16)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(manifest.packs) { pack in
                    PackSection(
                        pack: pack,
                        isExpanded: expandedIDs.contains(pack.id),
                        selectedPhraseID: state.selectedPhraseID,
                        toggle: { toggle(pack.id) }
                    )
                }
            }
            .padding(.top, 20)

            Spacer(minLength: 0)

            NewPhraseButton()
                .padding(.horizontal, 8)
                .padding(.bottom, 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .surface(palette.surfaceSidebar)
        .ignoresSafeArea()
    }

    private func toggle(_ id: String) {
        var set = expandedIDs
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        expanded = set
    }
}

private struct SearchWell: View {
    @Environment(\.palette) private var palette

    var body: some View {
        // Search behaviour is not specified yet; the well, magnifier and ⌘F hint are drawn as specified.
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text("Search")
                .typeRole(.body)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            Text("⌘F")
                .typeRole(.small)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 9)
        .frame(height: Metrics.controlHeight)
        .surface(palette.surfaceWell, cornerRadius: Metrics.controlRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Search")
    }
}

private struct PackSection: View {
    @Environment(\.palette) private var palette
    let pack: LibraryManifest.Pack
    let isExpanded: Bool
    let selectedPhraseID: String?
    let toggle: () -> Void

    var body: some View {
        if pack.isComingSoon {
            comingSoon
        } else if isExpanded {
            VStack(alignment: .leading, spacing: 0) {
                header(chevron: false)
                    .frame(height: 24, alignment: .top)
                ForEach(pack.phrases) { phrase in
                    PhraseRow(text: phrase.text, isSelected: phrase.id == selectedPhraseID)
                }
            }
            .padding(.bottom, 16)
        } else {
            header(chevron: true)
                .frame(height: Metrics.sidebarRowHeight)
        }
    }

    private func header(chevron: Bool, expandedChevron: Bool = false) -> some View {
        HeaderButton(action: toggle, isEnabled: chevron) {
            HStack(spacing: 0) {
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expandedChevron ? 90 : 0))
                        .frame(width: 16, alignment: .leading)
                }
                Text(pack.title.uppercased())
                    .typeRole(.mono)
                    .lineLimit(1)
            }
            .foregroundStyle(palette.textSecondary)
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A pack with zero phrases: collapsed with "Coming soon", never selectable, no badge, lock or upsell.
    /// Clicking it or pressing Return expands it to one non-selectable line.
    private var comingSoon: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(chevron: true, expandedChevron: isExpanded)
                .frame(height: 30)
            Text(isExpanded
                 ? "No phrases yet. Native recordings for noun and verb pairs are coming in a later update."
                 : "Coming soon")
                .typeRole(.small)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 32)
                .padding(.trailing, 16)
                .frame(minHeight: 17, alignment: .top)
                .padding(.bottom, isExpanded ? 12 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pack.title), coming soon, no phrases yet.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle() }
    }
}

/// A header that toggles its pack on click or Return and shows the 2 pt keyboard focus ring.
private struct HeaderButton<Label: View>: View {
    let action: () -> Void
    let isEnabled: Bool
    @ViewBuilder let label: Label

    var body: some View {
        // Expanded packs have no chevron and nothing to toggle; they are not dimmed.
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: isEnabled ? action : {}) { _ in label }
    }
}

private struct PhraseRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    let isSelected: Bool

    var body: some View {
        // Selecting a phrase loads it in a later spec; the row is focusable and hoverable now.
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: {}) { hovered in
            HStack(spacing: 0) {
                if isSelected {
                    LimeBarsGlyph()
                        .frame(width: 22, alignment: .leading)
                }
                Text(text)
                    .typeRole(isSelected ? .bodySemibold : .body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(
                        isSelected ? palette.limeSidebarText : (hovered ? palette.textPrimary : palette.textSecondary)
                    )
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, minHeight: Metrics.sidebarRowHeight, alignment: .leading)
            .background {
                // Hover is always lighter than selected: a faint neutral tint, never the glyph, lime or bold.
                if hovered && !isSelected {
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .fill(palette.rowHover)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        }
        .padding(.horizontal, 8)
        .help(text)
        .accessibilityLabel(isSelected ? "\(text), selected" : text)
    }
}

/// A plain button with hover tracking and the 2 pt keyboard focus ring (radius 6) from spec 18.
struct FocusRingButton<Label: View>: View {
    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool
    @State private var hovered = false
    let cornerRadius: CGFloat
    let action: () -> Void
    @ViewBuilder let label: (_ hovered: Bool) -> Label

    var body: some View {
        Button(action: action) {
            label(hovered).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(palette.textSecondary, lineWidth: 2)
            }
        }
    }
}

private struct NewPhraseButton: View {
    @Environment(\.palette) private var palette

    var body: some View {
        // Importing a clip is spec 21; the button is present and styled.
        FocusRingButton(cornerRadius: Metrics.controlRadius, action: {}) { _ in
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .light))
                    .frame(width: 15)
                Text("NEW PHRASE")
                    .typeRole(.mono)
            }
            .foregroundStyle(palette.textSecondary)
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, minHeight: Metrics.sidebarRowHeight, alignment: .leading)
        }
        .accessibilityLabel("New phrase")
    }
}
