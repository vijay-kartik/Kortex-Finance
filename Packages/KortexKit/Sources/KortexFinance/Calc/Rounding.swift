/// `numerator ÷ denominator` rounded half away from zero, as kortex's calc/Rounding.kt.
func roundDiv(_ numerator: Int64, _ denominator: Int64) -> Int64 {
    precondition(denominator > 0, "denominator must be positive")
    return numerator >= 0
        ? (numerator + denominator / 2) / denominator
        : -((-numerator + denominator / 2) / denominator)
}

/// Whole percentages of `amounts` that add up to exactly 100 (largest remainder), so a split bar's
/// labels never read 99% or 101%. All zeros when the amounts sum to zero.
public func roundedPercents(_ amounts: [Int64]) -> [Int] {
    let total = amounts.reduce(0, +)
    guard total > 0 else { return amounts.map { _ in 0 } }
    let exact = amounts.map { Double($0) * 100 / Double(total) }
    var floors = exact.map { Int($0) }
    let short = 100 - floors.reduce(0, +)
    let byRemainder = exact.indices.sorted { exact[$0] - Double(floors[$0]) > exact[$1] - Double(floors[$1]) }
    for i in byRemainder.prefix(short) { floors[i] += 1 }
    return floors
}
