import SwiftUI

/// The window content: sidebar, detail (toolbar plus cards) and the trailing Details inspector.
struct ShellView: View {
    @Bindable var model: ShellModel

    var body: some View {
        ShellSplitView(
            sidebarVisible: model.sidebarVisible,
            inspectorVisible: model.inspectorVisible,
            sidebar: { SidebarView(manifest: model.manifest, state: model.sidebar) },
            detail: { DetailPane(model: model) },
            inspector: { InspectorPane(model: model) }
        )
        .ignoresSafeArea()
        .frame(minWidth: Metrics.minimumWindow.width, minHeight: Metrics.minimumWindow.height)
        .background(WindowChromeConfigurator())
    }
}

/// Toolbar plus the card column.
struct DetailPane: View {
    @Environment(\.palette) private var palette
    var model: ShellModel

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(state: model.toolbar, toggleInspector: { model.inspectorVisible.toggle() })
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
