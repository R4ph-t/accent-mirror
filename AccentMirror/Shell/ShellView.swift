import SwiftUI

/// The window content: sidebar, detail (toolbar plus cards) and the trailing Details inspector.
struct ShellView: View {
    @Bindable var model: ShellModel
    @Environment(\.shellActions) private var actions

    var body: some View {
        ShellSplitView(
            sidebarVisible: model.sidebarVisible,
            inspectorVisible: model.inspectorVisible,
            sidebar: { SidebarPane(model: model) },
            detail: { DetailPane(model: model) },
            inspector: { InspectorPane(model: model) }
        )
        // The 960 × 680 minimum is the whole window, title bar included (spec 18; Addendum r4 C8). The app's
        // window takes its minimum from this frame (`.windowResizability(.contentMinSize)`), and SwiftUI measures
        // it below the 52 pt title bar, so the height leaves the title bar out: asking for 680 here held windows
        // at 732 pt (fixes round 5b).
        .frame(minWidth: Metrics.minimumWindow.width,
               minHeight: Metrics.minimumWindow.height - Metrics.toolbarHeight)
        .ignoresSafeArea()
        .background(WindowChromeConfigurator { model.window = $0 })
        .background(InspectorCollapseObserver(inspectorVisible: $model.inspectorVisible))
        .environment(\.inputPopoverState, model.inputPopover)
        .environment(\.inputPopoverSource, model.inputPopoverSource)
        .environment(\.closeInputPopover, {
            actions.closeInput()
            model.inputPopover = nil
        })
    }
}

/// The sidebar, reading the model in its own body so a fixture switch redraws it.
struct SidebarPane: View {
    var model: ShellModel

    var body: some View {
        // The id resets the sidebar's own expand state when Samples ▸ switches fixture.
        SidebarView(manifest: model.manifest, state: model.sidebar).id(model.fixtureName)
    }
}

/// Toolbar plus the card column.
struct DetailPane: View {
    @Environment(\.palette) private var palette
    var model: ShellModel

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(state: model.toolbar, isInputOpen: model.inputPopover != nil,
                        inspectorVisible: model.inspectorVisible,
                        toggleInspector: { model.toggleInspector() })
            if let banner = model.detail?.banner {
                // §13.2: 8 pt below the toolbar, 40 tall; the cards move down by 48.
                BannerView(banner: banner)
                    .padding(.top, Metrics.inner)
                    .padding(.bottom, Metrics.outer)
                    .padding(.horizontal, Metrics.outer)
            } else {
                Spacer().frame(height: Metrics.outer)
            }
            DetailContent(model: model)
                .padding(.horizontal, Metrics.outer)
                .padding(.bottom, Metrics.outer)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .surface(palette.surfaceBase)
        .ignoresSafeArea()
    }
}

/// The trailing Details inspector, closed by default.
struct InspectorPane: View {
    @Environment(\.palette) private var palette
    var model: ShellModel

    var body: some View {
        HStack(spacing: 0) {
            Hairline(axis: .vertical)
            InspectorContent(model: model)
                .padding(.top, Metrics.toolbarHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .surface(palette.surfaceBase)
        .ignoresSafeArea()
    }
}
