import AppKit
import Foundation
import KortexFinance
import Observation
import UniformTypeIdentifiers

/// Window-level state shared by the sidebar, the detail column and the Go menu.
@MainActor
@Observable
public final class AppModel {
    public var destination: Destination = .dashboard
    /// Which day, month or year Expenses shows, kept while switching screens.
    public var expensesPeriod = ExpensesPeriod.startingAt(.today())
    /// The selected entries on Expenses and Accounts. One alone is shown in the inspector.
    public var selectedEntryUids: Set<String> = []
    /// Nil shows the first account / card.
    public var selectedAccountUid: String?
    public var selectedCardUid: String?
    /// Selections on Recurring and Categories, shown in their inspectors.
    public var selectedRecurringUid: String?
    public var selectedCategoryUid: String?
    /// The month or year Reports shows (`.daily` isn't used there).
    public var reportPeriod = ExpensesPeriod.startingAt(.today())

    /// The sheet over the window, if any.
    public var sheet: Sheet?

    public init() {}

    /// File › Scan Receipt…: pick a photo or PDF in the open panel.
    public func chooseReceipt() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a receipt photo or PDF"
        if panel.runModal() == .OK, let url = panel.url { sheet = .receipt(url) }
    }

    /// File › Import Statement…: pick the statement PDF (or a photo of it). From an account's or card's
    /// own Import statement…, its entries go there; otherwise into the account it's for, or a new one.
    public func chooseStatement(into accountUid: String? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a bank or credit card statement"
        if panel.runModal() == .OK, let url = panel.url { sheet = .statement(url, into: accountUid) }
    }

    /// Opens an account or card from the sidebar.
    public func open(_ account: Account) {
        if account.kind.isCard {
            selectedCardUid = account.uid
            destination = .cards
        } else {
            selectedAccountUid = account.uid
            destination = .accounts
        }
    }
}

/// The sheets the window can show, one at a time.
public enum Sheet: Identifiable, Hashable {
    case newEntry(TransactionType)
    /// `asTransfer` opens an expense or income already switched to Transfer.
    case editEntry(String, asTransfer: Bool = false)
    case payBill(statementUid: String)
    case markPaid(recurringUid: String, dueOn: LocalDay)
    case recurring(String?)
    case category(String?, CategoryKind)
    case deleteCategory(String)
    case account(String?, AccountKind)
    /// A receipt image or PDF to read.
    case receipt(URL)
    /// An account statement to read with AI and review before adding its entries, to the account
    /// given or to the one it's for (else a new account).
    case statement(URL, into: String?)

    public var id: String { String(describing: self) }
}
