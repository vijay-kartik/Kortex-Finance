import SwiftUI

/// Sidebar destinations. Overview maps 1:1 to the Android bottom bar; Plan holds the screens
/// that are pushed on mobile (Pending payments, Recurring, Categories, Reports).
public enum Destination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case dashboard, expenses, accounts, cards
    case pending, recurring, categories, reports

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .expenses: "Expenses"
        case .accounts: "Accounts"
        case .cards: "Cards"
        case .pending: "Pending payments"
        case .recurring: "Recurring"
        case .categories: "Categories"
        case .reports: "Reports"
        }
    }

    public var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .expenses: "chart.pie"
        case .accounts: "wallet.bifold"
        case .cards: "creditcard"
        case .pending: "clock"
        case .recurring: "arrow.2.squarepath"
        case .categories: "tag"
        case .reports: "chart.bar.doc.horizontal"
        }
    }

    /// ⌘1 – ⌘5, as listed in the Mac notes in Figma.
    public var shortcut: KeyEquivalent? {
        switch self {
        case .dashboard: "1"
        case .expenses: "2"
        case .accounts: "3"
        case .cards: "4"
        case .pending: "5"
        default: nil
        }
    }

    static let overview: [Destination] = [.dashboard, .expenses, .accounts, .cards]
    static let plan: [Destination] = [.pending, .recurring, .categories, .reports]
}
