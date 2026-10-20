import Foundation
import KortexFinance
import Testing
@testable import KortexKit

@MainActor
struct AppModelTests {
    @Test func dismissClosesTheSheetItBelongsTo() {
        let model = AppModel()
        model.sheet = .account(nil, .bank)
        model.dismiss(.account(nil, .bank))
        #expect(model.sheet == nil)
    }

    @Test func lateDismissLeavesTheNextSheetOpen() {
        let model = AppModel()
        model.sheet = .account(nil, .creditCard)
        model.sheet = .newEntry(.expense)
        model.dismiss(.account(nil, .creditCard))
        #expect(model.sheet == .newEntry(.expense))
    }

    @Test func dismissWithNothingShowingStaysClosed() {
        let model = AppModel()
        model.dismiss(.recurring(nil))
        #expect(model.sheet == nil)
    }

    // MARK: Dropped receipts

    private func dropped() throws -> URL {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("AppModelTests-\(UUID().uuidString).jpg")
        try Data([1, 2, 3]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        return try #require(ReceiptDrops.temporary.copy(source))
    }

    @Test func closingADroppedReceiptDeletesItsCopy() throws {
        let model = AppModel()
        let file = try dropped()
        model.sheet = .receipt(file)
        #expect(FileManager.default.fileExists(atPath: file.path))
        model.dismiss(.receipt(file))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func replacingADroppedReceiptSheetDeletesItsCopy() throws {
        let model = AppModel()
        let file = try dropped()
        model.sheet = .receipt(file)
        model.sheet = .newEntry(.expense)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func closingAChosenReceiptKeepsTheFile() throws {
        let chosen = FileManager.default.temporaryDirectory.appendingPathComponent("AppModelTests-\(UUID().uuidString).jpg")
        try Data([1, 2, 3]).write(to: chosen)
        defer { try? FileManager.default.removeItem(at: chosen) }
        let model = AppModel()
        model.sheet = .receipt(chosen)
        model.dismiss(.receipt(chosen))
        #expect(FileManager.default.fileExists(atPath: chosen.path))
    }
}
