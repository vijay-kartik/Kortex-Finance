import Foundation
import Testing
@testable import KortexFinance
@testable import KortexKit

/// Receipt images kept and removed through the store, as the receipt sheet and Reset Data use it.
@MainActor
struct ReceiptFilesTests {
    private let image = URL(fileURLWithPath: "/tmp/receipt.jpg")
    private let parsed = ParsedReceipt(total: 24_500, items: [ReceiptItem(name: "Cold brew", quantity: 1, amountMinor: 24_500)])

    private func store() -> (PreviewFinanceStore, MemoryReceiptFiles) {
        let files = MemoryReceiptFiles()
        let store = PreviewFinanceStore(receipts: files)
        store.apply(AccountRules.add(AccountDraft(kind: .bank, name: "HDFC Savings", openingMinor: 1_000_000), in: store.data))
        return (store, files)
    }

    private func draft(_ store: PreviewFinanceStore, amountMinor: Int64 = 24_500) -> TransactionDraft {
        TransactionDraft(type: .expense, amountMinor: amountMinor, accountUid: store.data.moneyAccounts[0].uid, merchant: "Blue Tokai", source: .receipt)
    }

    @Test func savedExpenseKeepsTheImage() throws {
        let (store, files) = store()
        #expect(ReceiptSaving.add(draft(store), from: parsed, image: image, finance: store) == nil)
        let tx = try #require(store.data.transactions.values.first { $0.source == .receipt })
        let path = try #require(tx.receipt?.photoDevicePath)
        #expect(files.kept == [path: image])
        #expect(tx.receipt?.photoMimeType == "image/jpeg")
        #expect(store.receipts.exists(path))
    }

    @Test func refusedSaveLeavesNoFile() {
        let (store, files) = store()
        let before = store.changes.count
        #expect(ReceiptSaving.add(draft(store, amountMinor: 0), from: parsed, image: image, finance: store) == .invalidAmount)
        #expect(files.kept.isEmpty)
        #expect(store.changes.count == before)
    }

    @Test func attachToAGoneEntryLeavesNoFile() {
        let (store, files) = store()
        #expect(ReceiptSaving.attach(parsed, image: image, to: "gone", finance: store) == .notFound)
        #expect(files.kept.isEmpty)
    }

    @Test func notKeepingTheImageCopiesNothing() throws {
        let (store, files) = store()
        #expect(ReceiptSaving.add(draft(store), from: parsed, image: nil, finance: store) == nil)
        #expect(files.kept.isEmpty)
        let tx = try #require(store.data.transactions.values.first { $0.source == .receipt })
        #expect(tx.receipt?.photoDevicePath == nil)
        #expect(tx.receipt?.items.count == 1)
    }

    @Test func deletingTheEntryRemovesItsImage() throws {
        let (store, files) = store()
        ReceiptSaving.add(draft(store), from: parsed, image: image, finance: store)
        let tx = try #require(store.data.transactions.values.first { $0.source == .receipt })
        store.apply(EntryRules.delete(tx.uid, in: store.data))
        #expect(files.kept.isEmpty)
    }

    @Test func deletingTheAccountWithItsEntriesRemovesTheirImages() throws {
        let (store, files) = store()
        ReceiptSaving.add(draft(store), from: parsed, image: image, finance: store)
        let account = store.data.moneyAccounts[0]
        store.apply(AccountRules.delete(account.uid, withEntries: true, in: store.data))
        #expect(files.kept.isEmpty)
    }

    @Test func replacingTheReceiptRemovesTheOldImage() throws {
        let (store, files) = store()
        ReceiptSaving.add(draft(store), from: parsed, image: image, finance: store)
        let tx = try #require(store.data.transactions.values.first { $0.source == .receipt })
        let pdf = URL(fileURLWithPath: "/tmp/receipt.pdf")
        #expect(ReceiptSaving.attach(parsed, image: pdf, to: tx.uid, finance: store) == nil)
        let path = try #require(store.data.transactions[tx.uid]?.receipt?.photoDevicePath)
        #expect(path.hasSuffix(".pdf"))
        #expect(files.kept == [path: pdf])
    }

    @Test func eraseAllRemovesTheImages() async throws {
        let (store, files) = store()
        ReceiptSaving.add(draft(store), from: parsed, image: image, finance: store)
        try await store.eraseAll()
        #expect(files.kept.isEmpty)
    }

    // MARK: ReceiptFolder

    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReceiptFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func source(in root: URL, _ name: String = "scan.png") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    @Test func folderKeepsEachUsersImagesApart() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try source(in: root)
        let a = ReceiptFolder(userUid: "userA", root: root.appendingPathComponent("Receipts"))
        let b = ReceiptFolder(userUid: "userB", root: root.appendingPathComponent("Receipts"))

        let kept = try #require(a.place(file, for: "tx1"))
        #expect(kept.path.hasSuffix("/Receipts/userA/tx1.png"))
        #expect(kept.mimeType == "image/png")
        try a.keep(file, at: kept)
        #expect(a.exists(kept.path))

        // Another account can't remove A's images, one by one or by resetting.
        b.remove([kept.path])
        b.removeAll()
        #expect(a.exists(kept.path))

        a.remove([kept.path])
        #expect(!a.exists(kept.path))
    }

    @Test func folderRemovesOnlyItsOwnFiles() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let receipts = root.appendingPathComponent("Receipts", isDirectory: true)
        try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
        let legacy = try source(in: receipts, "old.jpg")
        let elsewhere = try source(in: root, "elsewhere.jpg")
        let folder = ReceiptFolder(userUid: "userA", root: receipts)

        folder.remove([elsewhere.path, legacy.path])
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test func signedOutFolderKeepsNothing() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ReceiptFolder(userUid: nil, root: root).place(try source(in: root), for: "tx1") == nil)
    }

    // MARK: ReceiptDrops

    @Test func dropsDiscardOnlyTheirOwnCopies() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try source(in: root)
        let drops = ReceiptDrops(folder: root.appendingPathComponent("ReceiptDrops", isDirectory: true))

        let copy = try #require(drops.copy(file))
        #expect(copy.deletingLastPathComponent().standardizedFileURL.path == drops.folder.path)
        #expect(copy.pathExtension == "png")

        drops.discard(file)
        #expect(FileManager.default.fileExists(atPath: file.path))
        drops.discard(copy)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }

    @Test func dropsRemoveAllEmptiesTheFolder() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try source(in: root)
        let drops = ReceiptDrops(folder: root.appendingPathComponent("ReceiptDrops", isDirectory: true))
        let copies = [try #require(drops.copy(file)), try #require(drops.copy(file))]

        drops.removeAll()
        #expect(copies.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
