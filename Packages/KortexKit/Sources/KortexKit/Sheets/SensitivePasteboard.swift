import AppKit

/// Copies a revealed full account number without it outliving the copy: marked concealed and transient
/// (the nspasteboard.org types clipboard managers skip), kept off Universal Clipboard, and cleared after
/// a minute unless something else has been copied since.
@MainActor
enum SensitivePasteboard {
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let clearAfter: Duration = .seconds(60)

    static func copy(_ string: String, to pasteboard: NSPasteboard = .general, clearAfter: Duration = clearAfter) {
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        item.setData(Data(), forType: concealed)
        item.setData(Data(), forType: transient)
        pasteboard.writeObjects([item])
        let copied = pasteboard.changeCount
        Task {
            try? await Task.sleep(for: clearAfter)
            // A later copy of anything else bumps the count; leave that alone.
            if pasteboard.changeCount == copied { pasteboard.clearContents() }
        }
    }
}
