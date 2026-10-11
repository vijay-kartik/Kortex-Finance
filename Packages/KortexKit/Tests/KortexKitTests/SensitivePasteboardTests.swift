import AppKit
import Testing
@testable import KortexKit

/// On a pasteboard of its own, so the tests never touch the user's clipboard.
@MainActor
struct SensitivePasteboardTests {
    private func withPasteboard(_ body: (NSPasteboard) async throws -> Void) async rethrows {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        try await body(pasteboard)
    }

    @Test func copyMarksTheNumberConcealedAndTransient() async {
        await withPasteboard { pasteboard in
            SensitivePasteboard.copy("4111111111111111", to: pasteboard)
            let types = pasteboard.types ?? []
            #expect(pasteboard.string(forType: .string) == "4111111111111111")
            #expect(types.contains(SensitivePasteboard.concealed))
            #expect(types.contains(SensitivePasteboard.transient))
        }
    }

    @Test func clearsTheNumberAfterTheTimeout() async throws {
        try await withPasteboard { pasteboard in
            SensitivePasteboard.copy("4111111111111111", to: pasteboard, clearAfter: .milliseconds(50))
            try await Task.sleep(for: .milliseconds(300))
            #expect(pasteboard.string(forType: .string) == nil)
        }
    }

    @Test func leavesALaterCopyAlone() async throws {
        try await withPasteboard { pasteboard in
            SensitivePasteboard.copy("4111111111111111", to: pasteboard, clearAfter: .milliseconds(50))
            pasteboard.clearContents()
            pasteboard.setString("something else", forType: .string)
            try await Task.sleep(for: .milliseconds(300))
            #expect(pasteboard.string(forType: .string) == "something else")
        }
    }
}
