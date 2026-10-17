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
    /// Why the last action without a sheet of its own was refused, for the window's alert.
    public var refusal: Refusal?

    public init() {}

    /// Commits a change from an action with no sheet to show its error (a hover button, a right-click
    /// menu, a confirmation), so a refusal (say, for data changed on the phone) shows in `refusal`.
    /// Returns whether the change was made.
    @discardableResult
    public func apply(_ result: Result<Change, FinanceError>, to finance: any FinanceStore, failing title: String) -> Bool {
        guard let failure = finance.apply(result) else { return true }
        refusal = Refusal(title: title, message: failure.message)
        return false
    }

    /// One-click Mark paid. When the payment's account is gone (deleted here or on the phone), opens
    /// Mark as paid… to pick another; when its category is, says to edit the payment.
    public func markPaid(_ recurringUid: String, dueOn: LocalDay, finance: any FinanceStore) {
        let result = RecurringRules.markPaid(recurringUid, dueOn: dueOn, in: finance.data)
        let name = finance.data.recurring[recurringUid]?.name ?? "the payment"
        switch result {
        case .failure(.unknownAccount):
            sheet = .markPaid(recurringUid: recurringUid, dueOn: dueOn)
        case .failure(.wrongCategoryKind):
            refusal = Refusal(title: "Couldn't mark \(name) as paid",
                              message: "Its category is no longer an expense category; it may have been deleted on another device. Edit the recurring payment to pick another.")
        default:
            apply(result, to: finance, failing: "Couldn't mark \(name) as paid")
        }
    }

    /// Closes `sheet` if it's still the one showing, so a late close from a sheet that's already
    /// gone can't dismiss the one opened since.
    public func dismiss(_ sheet: Sheet) {
        if self.sheet == sheet { self.sheet = nil }
    }

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

/// A change the rules refused, as the window's alert shows it.
public struct Refusal: Equatable, Sendable {
    public var title: String
    public var message: String
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
