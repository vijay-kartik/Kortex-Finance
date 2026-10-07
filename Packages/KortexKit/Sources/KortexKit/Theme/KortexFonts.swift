import CoreText
import SwiftUI

/// Space Grotesk carries the words; JetBrains Mono carries amounts, labels and shortcuts.
/// Both are variable fonts bundled with the package and registered once at launch.
public enum KortexFonts {
    private static let files = ["SpaceGrotesk", "JetBrainsMono"]

    @MainActor private static var registered = false

    /// Call once before the first window draws.
    @MainActor public static func register() {
        guard !registered else { return }
        registered = true
        for name in files {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else {
                assertionFailure("Missing bundled font \(name)")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

public extension Font {
    static func grotesk(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Space Grotesk", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}

public extension View {
    /// The small spaced-out mono caps used for section labels ("TOTAL BALANCE", "OVERVIEW").
    func sectionLabelStyle(_ color: Color = .kMuted) -> some View {
        font(.mono(10)).tracking(1.2).foregroundStyle(color)
    }
}
