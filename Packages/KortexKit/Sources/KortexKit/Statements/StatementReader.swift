import AppKit
import KortexAI
import KortexFinance
import PDFKit

/// The statement extraction pipeline: pages rendered on this Mac, read by the model through Vercel
/// AI Gateway into a fixed JSON shape, chunk by chunk, then merged into one statement. Checking
/// the rows against the printed balances happens afterwards, in `StatementImportRules.prepare`.
enum StatementReader {
    /// Pages per request: few enough that each reply stays well inside the output limit.
    static let pagesPerChunk = 4

    enum Progress: Equatable {
        case rendering
        case reading(done: Int, of: Int)
    }

    static func read(_ file: URL, categories: [SpendCategory], model: AIModel,
                     progress: @escaping @MainActor (Progress) -> Void) async throws -> ExtractedStatement {
        let gateway = try AIGateway()
        await progress(.rendering)
        let pages = try await Task.detached(priority: .userInitiated) { try render(file) }.value
        let chunks = stride(from: 0, to: pages.count, by: pagesPerChunk).map { Array($0..<min($0 + pagesPerChunk, pages.count)) }
        await progress(.reading(done: 0, of: chunks.count))

        let categoryList = categories.map { "\($0.uid): \($0.name) (\($0.kind == .income ? "income" : "expense"))" }.joined(separator: "\n")
        let results = try await withThrowingTaskGroup(of: (Int, ExtractedStatement).self) { group in
            for (i, chunk) in chunks.enumerated() {
                group.addTask {
                    let prompt = """
                    These are pages \(chunk.first! + 1)–\(chunk.last! + 1) of a \(pages.count)-page bank or credit card statement.
                    Extract it as the schema describes. Include only transactions printed on these pages.
                    Your categories (use the id, or null when none fits):
                    \(categoryList)
                    """
                    let read = try await gateway.structured(
                        ExtractedStatement.self, model: model, system: instructions, prompt: prompt,
                        images: chunk.map { AIGateway.Image(data: pages[$0], mimeType: "image/jpeg") },
                        schemaName: "bank_statement", schema: schema
                    )
                    return (i, read)
                }
            }
            var done: [(Int, ExtractedStatement)] = []
            for try await result in group {
                done.append(result)
                await progress(.reading(done: done.count, of: chunks.count))
            }
            return done.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return merge(results)
    }

    /// Joins chunk replies: the same account (by kind and last 4) across chunks becomes one, its
    /// transactions in page order, its details from whichever chunk printed them.
    static func merge(_ parts: [ExtractedStatement]) -> ExtractedStatement {
        var accounts: [ExtractedAccount] = []
        for part in parts {
            for account in part.accounts {
                let index = accounts.lastIndex { existing in
                    existing.kind == account.kind && (account.numberLast4 == nil || existing.numberLast4 == nil || existing.numberLast4 == account.numberLast4)
                }
                guard let index else { accounts.append(account); continue }
                var merged = accounts[index]
                merged.institution = merged.institution ?? account.institution
                merged.productName = merged.productName ?? account.productName
                merged.numberLast4 = merged.numberLast4 ?? account.numberLast4
                merged.ifsc = merged.ifsc ?? account.ifsc
                merged.holder = merged.holder ?? account.holder
                merged.periodStart = merged.periodStart ?? account.periodStart
                merged.periodEnd = account.periodEnd ?? merged.periodEnd
                merged.statementDate = merged.statementDate ?? account.statementDate
                merged.openingBalance = merged.openingBalance ?? account.openingBalance
                merged.openingBalanceIsDebit = merged.openingBalanceIsDebit ?? account.openingBalanceIsDebit
                if account.closingBalance != nil {
                    merged.closingBalance = account.closingBalance
                    merged.closingBalanceIsDebit = account.closingBalanceIsDebit
                }
                merged.creditLimit = merged.creditLimit ?? account.creditLimit
                merged.totalDue = merged.totalDue ?? account.totalDue
                merged.minimumDue = merged.minimumDue ?? account.minimumDue
                merged.paymentDueDate = merged.paymentDueDate ?? account.paymentDueDate
                merged.transactions += account.transactions
                accounts[index] = merged
            }
        }
        return ExtractedStatement(accounts: accounts)
    }

    /// Each page as a JPEG about 1,600 px on its long side: what vision models read at full detail.
    static func render(_ file: URL) throws -> [Data] {
        if ReceiptScanner.isPDF(file) {
            guard let pdf = PDFDocument(url: file) else { throw ReadError.unreadableFile }
            if pdf.isLocked { throw ReadError.passwordProtected }
            return (0..<pdf.pageCount).compactMap { i in
                guard let page = pdf.page(at: i) else { return nil }
                let bounds = page.bounds(for: .mediaBox)
                let scale = 1600 / max(bounds.width, bounds.height)
                return jpeg(page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox))
            }
        }
        guard let image = NSImage(contentsOf: file), let data = jpeg(image) else { throw ReadError.unreadableFile }
        return [data]
    }

    private static func jpeg(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    enum ReadError: LocalizedError {
        case unreadableFile, passwordProtected
        var errorDescription: String? {
            switch self {
            case .unreadableFile: "That file couldn't be opened as a statement."
            case .passwordProtected: "This PDF is password-protected. Open it in Preview, export it without a password, and try that copy."
            }
        }
    }

    static let instructions = """
    You read Indian bank and credit card statements, scanned or digital, and return exactly what is printed.

    Accounts
    - Return one entry in "accounts" for each account the statement shows: a single-account statement has one; a composite \
    statement may list a savings account, a credit card and loans, some with transactions and some only in a summary.
    - kind: "bank" for savings, current and salary accounts; "credit_card"; "loan" for loans and lines of credit; "other" otherwise.
    - numberLast4: ONLY the last four digits of the account or card number. Never return a full account or card number.
    - Dates as YYYY-MM-DD. Indian statements write day before month ("05SEP2026", "05/09/26").
    - Balances and amounts as positive numbers without commas or currency symbols. Set the matching …IsDebit to true when \
    the figure is printed with "DR" or as debit (overdrawn, or owed on a card), false when "CR", null when unmarked.
    - openingBalance: the balance brought forward / opening balance; for a card, the previous balance owed. closingBalance: \
    the closing balance / balance carried forward; for a card, the total outstanding.
    - For a credit card, also creditLimit, totalDue, minimumDue and paymentDueDate when printed.

    Transactions
    - One entry per transaction row, in printed order. A row's details often wrap over several lines: join them with spaces.
    - Do NOT include "balance brought forward", "opening balance", "closing balance", page totals or summary rows.
    - amount: the figure in the withdrawal/debit or deposit/credit column. direction: "debit" if it is in the withdrawals / \
    debit column (money out, or a card purchase), "credit" if in the deposits / credit column (money in, or a card payment). \
    Read the column headers on each page: their order differs between banks and statements.
    - balanceAfter: the running balance printed on that row, else null.
    - reference: the UPI / NEFT / IMPS / cheque reference number if printed on the row, else null.
    - merchant: a short, human name for the other party, taken from the details ("Swiggy", "eCourts Delhi", "Acme Technologies"); \
    title case; null for interest, bank charges, ATM withdrawals and transfers between the holder's own accounts. For a \
    NACH / ECS / ACH / SI debit, the company being paid (the lender, fund house or insurer) when the details name one, \
    not the clearing house or bank that carried it.
    - categoryId: one id from the list in the message that fits the transaction's direction and purpose, or null.
    - recurring: true for money out that repeats on a schedule: an EMI or loan instalment, rent, a SIP, an insurance \
    premium, a subscription (Netflix, Spotify, a gym), a bill paid by standing instruction, or a NACH / ECS / ACH / SI \
    mandate debit. False otherwise, including all money in and credit card bill payments.
    - cardBillPayment: on a bank statement, true for money out that pays a credit card bill ("CC PAYMENT", "CREDIT CARD", \
    a BillPay or BBPS payment to a card, CRED). False otherwise, and always false on a credit card statement.
    - ownTransfer: on a bank statement, true for money moved between the holder's own accounts: to or from another \
    account or wallet in their name ("self", "own account", a sweep, the holder's own name as the other party). False \
    for money to or from anyone else, card bill payments and ATM cash withdrawals, and false when unsure. Always false \
    on a credit card statement.
    - If a figure is unreadable, give your best reading; the app checks every row against the printed balances.
    """

    /// Strict structured-output schema: every property listed and required, nulls allowed where optional.
    /// Built once and only read afterwards.
    nonisolated(unsafe) static let schema: [String: Any] = {
        func nullable(_ type: String) -> [String: Any] { ["type": [type, "null"]] }
        let transaction: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["date", "description", "merchant", "amount", "direction", "balanceAfter", "balanceAfterIsDebit", "reference", "categoryId", "recurring", "cardBillPayment", "ownTransfer"],
            "properties": [
                "date": ["type": "string"],
                "description": ["type": "string"],
                "merchant": nullable("string"),
                "amount": ["type": "number"],
                "direction": ["type": "string", "enum": ["debit", "credit"]],
                "balanceAfter": nullable("number"),
                "balanceAfterIsDebit": nullable("boolean"),
                "reference": nullable("string"),
                "categoryId": nullable("string"),
                "recurring": ["type": "boolean"],
                "cardBillPayment": ["type": "boolean"],
                "ownTransfer": ["type": "boolean"],
            ],
        ]
        let accountFields: [String: Any] = [
            "kind": ["type": "string", "enum": ["bank", "credit_card", "loan", "other"]],
            "institution": nullable("string"),
            "productName": nullable("string"),
            "numberLast4": nullable("string"),
            "ifsc": nullable("string"),
            "holder": nullable("string"),
            "currency": nullable("string"),
            "periodStart": nullable("string"),
            "periodEnd": nullable("string"),
            "statementDate": nullable("string"),
            "openingBalance": nullable("number"),
            "openingBalanceIsDebit": nullable("boolean"),
            "closingBalance": nullable("number"),
            "closingBalanceIsDebit": nullable("boolean"),
            "creditLimit": nullable("number"),
            "totalDue": nullable("number"),
            "minimumDue": nullable("number"),
            "paymentDueDate": nullable("string"),
            "transactions": ["type": "array", "items": transaction],
        ]
        let account: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": Array(accountFields.keys).sorted(),
            "properties": accountFields,
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["accounts"],
            "properties": ["accounts": ["type": "array", "items": account]],
        ]
    }()
}
