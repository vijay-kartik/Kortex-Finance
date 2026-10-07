/// The finance collections under `users/{uid}`, by their Firestore names.
public enum FinCollection: String, Sendable, CaseIterable {
    case categories = "finCategories"
    case accounts = "finAccounts"
    case statements = "finStatements"
    case recurring = "finRecurring"
    case merchants = "finMerchants"
    case transactions = "finTransactions"
    case secrets = "finSecrets"
}

/// One document write: a record to save in full, or a delete marker.
public enum RecordWrite: Sendable {
    case account(Account)
    case transaction(Transaction)
    case category(Category)
    case recurring(Recurring)
    case statement(CardStatement)
    case merchant(Merchant)
    /// An account's full number, sealed. Written alongside the account, which carries `hasSecret`.
    case secret(accountUid: String, SealedSecret, atMillis: Int64)
    /// Android merges `deleted: true` over a record's document rather than removing it.
    case delete(FinCollection, uid: String, atMillis: Int64)
}

/// Everything one user action writes, committed as one Firestore batch so the phone never syncs
/// half of it.
public struct Change: Sendable {
    public var writes: [RecordWrite]

    public init(_ writes: [RecordWrite]) { self.writes = writes }
}

/// Why a change was refused, worded for the sheet that asked for it.
public enum FinanceError: Error, Equatable, Sendable {
    case invalidAmount
    case unknownAccount
    /// Transfers and card payments need another account; card payments a credit card.
    case invalidTarget
    case wrongCategoryKind
    /// Income into a credit card would be a refund, which v1 doesn't handle.
    case refundNotSupported
    case alreadySaved
    case blankName
    case nameTaken
    case builtIn
    case notFound
    case invalidLast4
    case invalidDay
    case invalidReminder
    case unknownLinkedAccount
    case cardPaymentNeedsCard
    case transferNeedsAccount
    /// A full number that isn't 8 to 19 digits, or doesn't end in the last 4 given.
    case invalidNumber
    /// A full number was given but there's no data key to seal it with.
    case noFinanceKey

    public var message: String {
        switch self {
        case .invalidAmount: "Enter an amount above zero."
        case .unknownAccount: "Pick an account or card."
        case .invalidTarget: "Pick a different account to move the money to."
        case .wrongCategoryKind: "That category is for the other kind of entry."
        case .refundNotSupported: "Kortex can't record money coming into a credit card yet."
        case .alreadySaved: "This was already recorded."
        case .blankName: "Enter a name."
        case .nameTaken: "There's already a category with that name."
        case .builtIn: "Built-in categories can't be changed."
        case .notFound: "It's no longer there; it may have been deleted on another device."
        case .invalidLast4: "Last 4 digits must be exactly four digits."
        case .invalidDay: "Days must be between 1 and 31."
        case .invalidReminder: "Reminders can be up to 7 days before."
        case .unknownLinkedAccount: "Link the debit card to one of your bank accounts."
        case .cardPaymentNeedsCard: "Pick the card each bill payment went to, or leave those rows out."
        case .transferNeedsAccount: "Pick your other account for each transfer, or leave those rows out."
        case .invalidNumber: "Check the number: 8 to 19 digits, ending in the last 4."
        case .noFinanceKey: "Kortex couldn't get the key that encrypts full numbers. See Settings › Account Numbers."
        }
    }
}
