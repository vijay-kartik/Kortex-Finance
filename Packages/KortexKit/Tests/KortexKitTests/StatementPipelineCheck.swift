import Foundation
import Testing
@testable import KortexAI
@testable import KortexFinance
@testable import KortexKit

/// Runs the real pipeline (render → AI Gateway → merge → balance checks) on a statement you point it
/// at, printing only counts and check results: no names, numbers or descriptions. Skipped unless
/// both variables are set:
///
///     AI_GATEWAY_API_KEY=… KORTEX_STATEMENT=/path/to/statement.pdf \
///       xcrun swift test --package-path Packages/KortexKit --filter StatementPipelineCheck
struct StatementPipelineCheck {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KORTEX_STATEMENT"] != nil
                   && ProcessInfo.processInfo.environment["AI_GATEWAY_API_KEY"] != nil),
          .timeLimit(.minutes(5)))
    func readsAStatement() async throws {
        let env = ProcessInfo.processInfo.environment
        let file = URL(fileURLWithPath: env["KORTEX_STATEMENT"]!)
        let model = env["KORTEX_MODEL"].flatMap(AIModel.init(rawValue:)) ?? .default
        let gateway = try AIGateway(key: env["AI_GATEWAY_API_KEY"])
        let pages = try StatementReader.render(file)
        let categories = BuiltInCategories.all
        var parts: [ExtractedStatement] = []
        for start in stride(from: 0, to: pages.count, by: StatementReader.pagesPerChunk) {
            let chunk = Array(start..<min(start + StatementReader.pagesPerChunk, pages.count))
            let started = Date()
            let part = try await gateway.structured(
                ExtractedStatement.self, model: model, system: StatementReader.instructions,
                prompt: "These are pages \(chunk.first! + 1)–\(chunk.last! + 1) of a \(pages.count)-page statement. Include only transactions printed on these pages.\n"
                    + categories.map { "\($0.uid): \($0.name)" }.joined(separator: "\n"),
                images: chunk.map { AIGateway.Image(data: pages[$0], mimeType: "image/jpeg") },
                schemaName: "bank_statement", schema: StatementReader.schema
            )
            print("chunk pages \(chunk.first! + 1)-\(chunk.last! + 1): \(part.accounts.count) account(s) in \(Int(Date().timeIntervalSince(started)))s")
            parts.append(part)
        }
        let statement = StatementReader.merge(parts)
        print("model \(model.rawValue) · \(pages.count) page(s) · \(statement.accounts.count) account(s)")
        for account in statement.accounts {
            let s = StatementImportRules.prepare(account, in: FinanceData(), today: .today())
            let flagged = s.rows.filter { $0.issue != nil }
            let corrected = flagged.filter { $0.issue!.contains("corrected") }.count
            print("""
            - \(account.kind.rawValue): last4 \(s.account.last4 == nil ? "missing" : "present"), \(s.rows.count) rows, \
            \(s.rows.filter { $0.printedBalanceMinor != nil }.count) with printed balance, \(corrected) direction-corrected, \
            \(flagged.count - corrected) other flags, opening \(account.openingBalance == nil ? "inferred" : "read"), \
            closing \(s.closingMinor == nil ? "missing" : "read"), reconciles: \(s.reconciles.map(String.init) ?? "n/a"), \
            categorised \(s.rows.filter { $0.categoryUid != nil }.count)/\(s.rows.count)
            """)
        }
        #expect(!statement.accounts.isEmpty)
    }
}
