import Foundation

/// What the search fields on Expenses, Accounts and Cards look for. Every word of the query has to be
/// found, ignoring case and accents, in the entry's merchant, note, category, account names or last 4
/// digits, or bank reference; a word that reads as an amount also finds entries of exactly that amount.
public struct EntrySearch: Sendable {
    /// The query as typed, without surrounding spaces.
    public let text: String
    private let words: [String]
    /// Every word as an amount, when it reads as one ("1249", "1,249.00").
    private let amounts: [Int64?]
    /// The whole query as an amount, so "₹ 1,249" finds ₹1,249 though "₹" alone matches nothing.
    private let wholeAmount: Int64?

    public init(_ query: String) {
        text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = query.split(whereSeparator: \.isWhitespace).map(String.init)
        words = parts.map(Self.fold)
        amounts = parts.map(Money.parseMinor)
        wholeAmount = Money.parseMinor(query)
    }

    /// Nothing but spaces: show everything as if there were no search.
    public var isEmpty: Bool { words.isEmpty }

    public static func matches(_ tx: Transaction, query: String, data: FinanceData) -> Bool {
        EntrySearch(query).matches(tx, data: data)
    }

    public func matches(_ tx: Transaction, data: FinanceData) -> Bool {
        if words.isEmpty || wholeAmount == tx.amountMinor { return true }
        let text = Self.searchText(tx, data)
        return words.indices.allSatisfy { i in amounts[i] == tx.amountMinor || text.contains { $0.contains(words[i]) } }
    }

    /// The entry's searchable text, folded.
    private static func searchText(_ tx: Transaction, _ data: FinanceData) -> [String] {
        var fields = [tx.merchant, tx.note, tx.sourceRef, tx.categoryUid.flatMap { data.categories[$0]?.name }]
        for uid in [tx.accountUid, tx.toAccountUid] {
            guard let account = uid.flatMap({ data.accounts[$0] }) else { continue }
            fields += [account.name, account.last4]
        }
        return fields.compactMap { $0.map(fold) }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
