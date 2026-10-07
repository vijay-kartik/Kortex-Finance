import Foundation

// Finance records as the Android app writes them to `users/{uid}/fin*` (kortex: sync/finance/FinanceDocs.kt).
// Enum raw values are the Kotlin enum names, so documents round-trip unchanged.

public enum AccountKind: String, Sendable, CaseIterable {
    case bank = "BANK"
    case cash = "CASH"
    case wallet = "WALLET"
    case creditCard = "CREDIT_CARD"
    case debitCard = "DEBIT_CARD"

    public var isCard: Bool { self == .creditCard || self == .debitCard }

    /// Bank, cash and wallets make up the total balance. Cards never do.
    public var countsInTotal: Bool { self == .bank || self == .cash || self == .wallet }
}

public enum BankType: String, Sendable, CaseIterable {
    case savings = "SAVINGS"
    case current = "CURRENT"
}

public enum CategoryKind: String, Sendable, CaseIterable {
    case expense = "EXPENSE"
    case income = "INCOME"
}

public enum TransactionType: String, Sendable, CaseIterable {
    /// An account's or card's starting balance, written once when it's added.
    case opening = "OPENING"
    case expense = "EXPENSE"
    case income = "INCOME"
    /// Between two of your own accounts. Never income or spending.
    case transfer = "TRANSFER"
    /// Paying a credit card's bill from an account. Never spending: the purchases already were.
    case cardPayment = "CARD_PAYMENT"
}

public enum TransactionSource: String, Sendable, CaseIterable {
    case manual = "MANUAL", sms = "SMS", receipt = "RECEIPT", recurring = "RECURRING", agent = "AGENT", api = "API"
    /// Imported from an account statement on the Mac. Android doesn't know this value yet and reads
    /// such entries as MANUAL, which is harmless.
    case statement = "STATEMENT"
}

public enum RecurringKind: String, Sendable, CaseIterable {
    case subscription = "SUBSCRIPTION"
    case fixed = "FIXED"
}

public enum Frequency: String, Sendable, CaseIterable {
    case weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY"
}

public enum StatementSource: String, Sendable, CaseIterable {
    case auto = "AUTO", sms = "SMS", manual = "MANUAL"
}

/// A bank account, cash, wallet or card. There is no balance field: it's always the sum of the
/// account's transactions, starting with its opening entry.
public struct Account: Sendable, Hashable, Identifiable {
    public let uid: String
    public var kind: AccountKind
    public var name: String
    public var institution: String?
    public var last4: String?
    /// The full number is kept, encrypted, in finSecrets.
    public var hasSecret: Bool
    public var bankType: BankType?
    public var ifsc: String?
    /// A debit card's bank account: its spends move money there.
    public var linkedAccountUid: String?
    public var network: String?
    /// MM/YY.
    public var expiry: String?
    public var holder: String?
    public var creditLimitMinor: Int64?
    public var statementDay: Int?
    public var dueDay: Int?
    public var colorToken: String?
    public var archived: Bool
    public var createdAtMillis: Int64
    public var updatedAtMillis: Int64

    public var id: String { uid }
}

public struct ReceiptItem: Sendable, Hashable {
    public var name: String
    public var quantity: Int
    public var amountMinor: Int64

    public init(name: String, quantity: Int, amountMinor: Int64) {
        self.name = name
        self.quantity = quantity
        self.amountMinor = amountMinor
    }
}

public struct Receipt: Sendable, Hashable {
    public var itemCount: Int
    public var items: [ReceiptItem]
    public var taxMinor: Int64?
    /// The photo stays on the device that scanned it; this is that device's path.
    public var photoDevicePath: String?
    public var photoMimeType: String?

    public init(itemCount: Int, items: [ReceiptItem], taxMinor: Int64?, photoDevicePath: String?, photoMimeType: String?) {
        self.itemCount = itemCount
        self.items = items
        self.taxMinor = taxMinor
        self.photoDevicePath = photoDevicePath
        self.photoMimeType = photoMimeType
    }
}

/// Every change to a balance is one of these. `amountMinor` is always positive; `type` says which way
/// the money moved.
public struct Transaction: Sendable, Hashable, Identifiable {
    public let uid: String
    public var type: TransactionType
    public var amountMinor: Int64
    public var currency: String
    public var occurredAtMillis: Int64
    /// `yyyy-MM-dd`, the day in the saving device's zone. Day and month totals group by it.
    public var occurredOn: LocalDay
    public var accountUid: String
    public var toAccountUid: String?
    /// Nil is Uncategorised.
    public var categoryUid: String?
    public var merchant: String?
    public var payeeKey: String?
    public var note: String?
    public var source: TransactionSource
    public var sourceRef: String?
    public var recurringUid: String?
    public var dueOn: LocalDay?
    public var statementUid: String?
    public var receipt: Receipt?
    public var createdAtMillis: Int64
    public var updatedAtMillis: Int64

    public var id: String { uid }
}

/// Category colours name a theme colour: Synapse, Teal, Amber, Growth, Lilac, Rose, Mint, Sky.
public struct Category: Sendable, Hashable, Identifiable {
    public let uid: String
    public var name: String
    public var kind: CategoryKind
    public var colorToken: String
    /// Can't be renamed, recoloured or deleted.
    public var builtIn: Bool
    public var sortOrder: Int
    public var createdAtMillis: Int64 = 0
    public var updatedAtMillis: Int64 = 0

    public var id: String { uid }
}

/// The four categories every account starts with. Their uids are fixed and they are never synced,
/// so each device supplies them itself.
public enum BuiltInCategories {
    public static let food = Category(uid: "food", name: "Food", kind: .expense, colorToken: "Synapse", builtIn: true, sortOrder: 0)
    public static let travel = Category(uid: "travel", name: "Travel", kind: .expense, colorToken: "Teal", builtIn: true, sortOrder: 1)
    public static let utilities = Category(uid: "utilities", name: "Utilities", kind: .expense, colorToken: "Amber", builtIn: true, sortOrder: 2)
    public static let salary = Category(uid: "salary", name: "Salary", kind: .income, colorToken: "Growth", builtIn: true, sortOrder: 0)

    public static let all: [Category] = [food, travel, utilities, salary]
}

/// A subscription or fixed expense. `nextDueOn` is the first occurrence not yet paid or skipped.
public struct Recurring: Sendable, Hashable, Identifiable {
    public let uid: String
    public var name: String
    public var kind: RecurringKind
    public var amountMinor: Int64
    public var currency: String
    public var frequency: Frequency
    public var interval: Int
    /// Day of month (1–31) for monthly and yearly; ISO day of week (1 = Monday) for weekly.
    public var anchorDay: Int
    public var nextDueOn: LocalDay
    public var accountUid: String
    public var categoryUid: String?
    /// Days before each due date to remind: 0 on the day, -1 for none.
    public var remindDaysBefore: Int
    public var autoMarkPaid: Bool
    public var paused: Bool
    public var createdAtMillis: Int64
    public var updatedAtMillis: Int64

    public var id: String { uid }
}

public struct CardStatement: Sendable, Hashable, Identifiable {
    public let uid: String
    public var cardUid: String
    public var periodStart: LocalDay
    public var statementOn: LocalDay
    public var dueOn: LocalDay
    public var totalDueMinor: Int64
    public var minDueMinor: Int64
    public var source: StatementSource
    public var createdAtMillis: Int64
    public var updatedAtMillis: Int64

    public var id: String { uid }
}

/// What a payee is called and which category it gets, learnt from the user's corrections.
public struct Merchant: Sendable, Hashable, Identifiable {
    public let uid: String
    public var payeeKey: String
    public var displayName: String
    public var categoryUid: String?
    public var updatedAtMillis: Int64

    public var id: String { uid }
}

public extension Transaction {
    /// A refund, reversal or cashback on a credit card (`FinanceIds.cardCredit`), not a bill payment.
    var isCardCredit: Bool { type == .cardPayment && accountUid == FinanceIds.cardCredit }
}
