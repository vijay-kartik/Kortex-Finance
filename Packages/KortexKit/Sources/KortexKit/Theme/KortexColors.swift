import SwiftUI

/// Kortex palette, the same values as the Android `design` module and the Figma "Primitives"
/// collection: void / panel / edge surfaces, ink and muted text, one synapse accent.
public extension Color {
    static let kVoid = Color(hex: 0x0B0E14)
    static let kPanel = Color(hex: 0x141A26)
    static let kEdge = Color(hex: 0x242E42)
    static let kInk = Color(hex: 0xE9EDF5)
    static let kMuted = Color(hex: 0x97A1B8)
    static let kSynapse = Color(hex: 0x7C8CFF)
    static let kSynapseDim = Color(hex: 0x232A52)
    static let kAmber = Color(hex: 0xEFB358)
    static let kAlarm = Color(hex: 0xFF7182)
    static let kGrowth = Color(hex: 0x4ADE80)
    static let kTeal = Color(hex: 0x5CC8D6)
    static let kLilac = Color(hex: 0xC792EA)
    static let kRose = Color(hex: 0xF28FB3)
    static let kMint = Color(hex: 0x8FD18F)
    static let kSky = Color(hex: 0x5EC2E8)

    /// Mac-only surfaces from the Mac Figma frames.
    static let kSidebar = Color(hex: 0x0F131C)
    static let kRaised = Color(hex: 0x1A2131)
    static let kSheet = Color(hex: 0x161C29)

    /// A category or account `colorToken` (Synapse, Teal, Amber, Growth, Lilac, Rose, Mint, Sky).
    static func token(_ name: String?) -> Color {
        switch name {
        case "Teal": .kTeal
        case "Amber": .kAmber
        case "Growth": .kGrowth
        case "Lilac": .kLilac
        case "Rose": .kRose
        case "Mint": .kMint
        case "Sky": .kSky
        case "Alarm": .kAlarm
        default: .kSynapse
        }
    }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
