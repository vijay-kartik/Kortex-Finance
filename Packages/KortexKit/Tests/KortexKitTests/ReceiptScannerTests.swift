import AppKit
import Testing
@testable import KortexFinance
@testable import KortexKit

/// The real reading path: a receipt drawn as an image, read by Vision, grouped into rows, parsed.
struct ReceiptScannerTests {
    private let rows: [(String, String)] = [
        ("BREWHOUSE CAFE", ""),
        ("30/09/2026 13:42", "Bill #4821"),
        ("Cappuccino x2", "420.00"),
        ("Avocado toast", "380.00"),
        ("Cold brew", "200.00"),
        ("Subtotal", "1,000.00"),
        ("CGST 2.5%", "25.00"),
        ("SGST 2.5%", "25.00"),
        ("TOTAL", "1,050.00"),
        ("PAID VISA ****8824", "1,050.00"),
    ]

    /// Labels on the left, prices on the right, as printed: Vision returns them as separate boxes.
    private func drawReceipt() throws -> URL {
        let size = NSSize(width: 900, height: 1300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let font = NSFont.monospacedSystemFont(ofSize: 40, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        for (i, row) in rows.enumerated() {
            let y = size.height - 120 - CGFloat(i) * 105
            NSAttributedString(string: row.0, attributes: attrs).draw(at: NSPoint(x: 60, y: y))
            let right = NSAttributedString(string: row.1, attributes: attrs)
            right.draw(at: NSPoint(x: size.width - 60 - right.size().width, y: y))
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("receipt-\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    @Test func readsADrawnReceiptEndToEnd() async throws {
        let url = try drawReceipt()
        let text = await ReceiptScanner.recognise(url)
        let receipt = ReceiptParser.parse(text, today: LocalDay(year: 2026, month: 10, day: 1)!)
        #expect(receipt.total == 1_050_00, "read:\n\(text)")
        #expect(receipt.taxMinor == 50_00)
        #expect(receipt.last4 == "8824")
        #expect(receipt.date == LocalDay(year: 2026, month: 9, day: 30))
        #expect(receipt.items.count == 3)
        #expect(receipt.merchant == "Brewhouse Cafe")
    }
}
