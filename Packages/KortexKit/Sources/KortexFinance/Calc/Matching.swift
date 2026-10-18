/// Telling which entry another record of the same money is: a statement row, or a transfer's other side.
public enum Matching {
    /// How many days apart two records of the same money may be: banks and cards post a few days late.
    public static let windowDays = 3

    /// The entry for `amountMinor` within `windowDays` of `day` that `fit` accepts, the lowest rank
    /// first, then the closest, ties by uid. `fit` gives the rank, or nil when the entry doesn't fit.
    static func closest(to day: LocalDay, amountMinor: Int64, in txs: some Sequence<Transaction>,
                        fit: (Transaction) -> Int?) -> Transaction? {
        txs.compactMap { tx -> (rank: Int, gap: Int, tx: Transaction)? in
            let gap = abs(day.days(to: tx.occurredOn))
            guard tx.amountMinor == amountMinor, gap <= windowDays, let rank = fit(tx) else { return nil }
            return (rank, gap, tx)
        }.min { ($0.rank, $0.gap, $0.tx.uid) < ($1.rank, $1.gap, $1.tx.uid) }?.tx
    }

    /// The closest entry for `amountMinor` within `windowDays` of `day` that `fits`, ties by uid.
    static func closest(to day: LocalDay, amountMinor: Int64, in txs: some Sequence<Transaction>,
                        where fits: (Transaction) -> Bool) -> Transaction? {
        closest(to: day, amountMinor: amountMinor, in: txs) { fits($0) ? 0 : nil }
    }
}
