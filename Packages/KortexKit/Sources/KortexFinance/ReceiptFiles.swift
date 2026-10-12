import Foundation
import UniformTypeIdentifiers

/// Where a receipt image is kept, as an entry's `Receipt` carries it.
public struct ReceiptImage: Equatable, Sendable {
    public var path: String
    public var mimeType: String

    public init(path: String, mimeType: String) {
        self.path = path
        self.mimeType = mimeType
    }
}

/// The receipt images kept on this device, as on the phone: never uploaded, the entry carries the
/// path. Reached only through the `FinanceStore`, which keeps an image once the rules have accepted
/// its entry and removes it with the entry. `ReceiptFolder` is the real one; `MemoryReceiptFiles`
/// is for previews and tests.
@MainActor
public protocol ReceiptFiles: AnyObject {
    /// Where an image for the entry would be kept. Nil when there's nowhere to keep it (signed out).
    func place(_ file: URL, for entryUid: String) -> ReceiptImage?
    /// Copies the image to its place, replacing what was there.
    func keep(_ file: URL, at image: ReceiptImage) throws
    /// Images no entry points at any more. Paths that aren't this user's are left alone.
    func remove(_ paths: [String])
    /// Reset data: every image this user kept.
    func removeAll()
    /// Whether the image is on this device.
    func exists(_ path: String) -> Bool
}

/// Receipt images in Application Support/Receipts/<user uid>, so each Google account signed in on
/// this Mac has its own. Earlier builds kept them straight in Receipts; those are still opened, and
/// removed with the entries that point at them.
@MainActor
public final class ReceiptFolder: ReceiptFiles {
    private let root: URL?
    private let folder: URL?

    /// Nil `userUid` (signed out) keeps nothing. `root` is the Receipts folder, for tests.
    public init(userUid: String?, root: URL? = nil) {
        let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Receipts", isDirectory: true)
        self.root = root?.standardizedFileURL
        folder = userUid.flatMap { uid in root?.appendingPathComponent(uid, isDirectory: true).standardizedFileURL }
    }

    public func place(_ file: URL, for entryUid: String) -> ReceiptImage? {
        guard let folder else { return nil }
        let kind = ReceiptImage.kind(of: file)
        return ReceiptImage(path: folder.appendingPathComponent("\(entryUid).\(kind.ext)").path, mimeType: kind.mime)
    }

    public func keep(_ file: URL, at image: ReceiptImage) throws {
        let fm = FileManager.default
        let target = URL(fileURLWithPath: image.path)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: target)
        try fm.copyItem(at: file, to: target)
    }

    public func remove(_ paths: [String]) {
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let parent = url.deletingLastPathComponent().path
            guard parent == folder?.path || parent == root?.path else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func removeAll() {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

/// Receipt images in memory, for `PreviewFinanceStore`.
@MainActor
public final class MemoryReceiptFiles: ReceiptFiles {
    /// Each kept image's path, with the file it was kept from.
    public private(set) var kept: [String: URL] = [:]

    public init() {}

    public func place(_ file: URL, for entryUid: String) -> ReceiptImage? {
        let kind = ReceiptImage.kind(of: file)
        return ReceiptImage(path: "/Receipts/preview/\(entryUid).\(kind.ext)", mimeType: kind.mime)
    }

    public func keep(_ file: URL, at image: ReceiptImage) throws { kept[image.path] = file }
    public func remove(_ paths: [String]) { paths.forEach { kept[$0] = nil } }
    public func removeAll() { kept = [:] }
    public func exists(_ path: String) -> Bool { kept[path] != nil }
}

extension ReceiptImage {
    /// The extension an image is kept under, and its MIME type.
    static func kind(of file: URL) -> (ext: String, mime: String) {
        let type = (try? file.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: file.pathExtension)
        if type?.conforms(to: .pdf) ?? (file.pathExtension.lowercased() == "pdf") { return ("pdf", "application/pdf") }
        let ext = file.pathExtension.isEmpty ? "jpg" : file.pathExtension.lowercased()
        return (ext, UTType(filenameExtension: ext)?.preferredMIMEType ?? "image/jpeg")
    }
}

extension FinanceData {
    /// The receipt images that entries pointed at before the change and none do after it: the
    /// entries' deletes, and receipts replaced on entries the change writes.
    public func receiptPathsDropped(by change: Change) -> [String] {
        var dropped = Set<String>(), stillKept = Set<String>(), touched = Set<String>()
        for write in change.writes {
            switch write {
            case .transaction(let tx):
                touched.insert(tx.uid)
                if let path = transactions[tx.uid]?.receipt?.photoDevicePath { dropped.insert(path) }
                if let path = tx.receipt?.photoDevicePath { stillKept.insert(path) }
            case .delete(.transactions, let uid, _):
                touched.insert(uid)
                if let path = transactions[uid]?.receipt?.photoDevicePath { dropped.insert(path) }
            default:
                break
            }
        }
        dropped.subtract(stillKept)
        guard !dropped.isEmpty else { return [] }
        for tx in transactions.values where !touched.contains(tx.uid) {
            if let path = tx.receipt?.photoDevicePath { dropped.remove(path) }
        }
        return dropped.sorted()
    }
}
