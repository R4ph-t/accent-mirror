import CoreText
import Foundation

/// The three OFL font families bundled with the app (spec 18). They load from the app bundle only:
/// no network, no system fallback. Each family's official `OFL.txt` sits next to its font files.
enum BundledFonts {
    static let geistRegular = "Geist-Regular"
    static let geistSemiBold = "Geist-SemiBold"
    static let geistBold = "Geist-Bold"
    static let geistMonoMedium = "GeistMono-Medium"
    static let funnelDisplaySemiBold = "FunnelDisplay-SemiBold"

    static let allPostScriptNames = [geistRegular, geistSemiBold, geistBold, geistMonoMedium, funnelDisplaySemiBold]

    /// Folder (a folder reference in project.yml) that keeps each family's files and licence together.
    static let folderName = "Fonts"

    struct Family {
        let name: String
        let folder: String
        let notice: String
    }

    static let families = [
        Family(
            name: "Geist and Geist Mono",
            folder: "Geist",
            notice: "Geist and Geist Mono, from the Geist font release v1.9.2 (github.com/vercel/geist-font)."
        ),
        Family(
            name: "Funnel Display",
            folder: "FunnelDisplay",
            notice: "Funnel Display, from the Funnel release 1.001 (github.com/Dicotype/Funnel)."
        ),
    ]

    static func fontsDirectory(in bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Registers every bundled font for this process. Safe to call more than once.
    @MainActor
    static func register(from bundle: Bundle = .main) {
        guard !registered, let directory = fontsDirectory(in: bundle) else { return }
        let urls = families.flatMap { family -> [URL] in
            let folder = directory.appendingPathComponent(family.folder, isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "ttf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        for url in urls {
            // Already-registered fonts report an error we can ignore; anything else shows up as a missing face.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        registered = true
    }

    @MainActor private static var registered = false

    /// The licence text for a family, read from the bundle.
    static func licence(for family: Family, in bundle: Bundle = .main) -> String? {
        guard let url = fontsDirectory(in: bundle)?
            .appendingPathComponent(family.folder, isDirectory: true)
            .appendingPathComponent("OFL.txt")
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
