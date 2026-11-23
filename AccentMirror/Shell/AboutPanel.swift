import AppKit

/// The standard About panel, with the bundled font credits and their full SIL Open Font License texts.
/// The fonts are not relicensed: they stay under the OFL 1.1, unmodified.
@MainActor
enum AboutPanel {
    static func show() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits()])
    }

    static func credits() -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
        ]
        let heading: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
        ]
        let text = NSMutableAttributedString(
            string: "Accent Mirror is free software under the GPL-3.0.\n\n" +
                "Fonts: Geist, Geist Mono and Funnel Display are bundled unmodified under the SIL Open Font " +
                "License 1.1. They are not relicensed under the GPL.\n\n",
            attributes: body
        )
        for family in BundledFonts.families {
            text.append(NSAttributedString(string: family.name + "\n", attributes: heading))
            text.append(NSAttributedString(string: family.notice + "\n\n", attributes: body))
            if let licence = BundledFonts.licence(for: family) {
                text.append(NSAttributedString(string: licence + "\n\n", attributes: body))
            }
        }
        return text
    }
}
