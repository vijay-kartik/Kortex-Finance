import AppKit
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Reads the text on a receipt image or PDF, on this Mac (Apple Vision), as one line per printed
/// row so "Cold brew ... 200.00" stays together for `ReceiptParser`.
enum ReceiptScanner {
    /// A digital PDF's own text when it has some; otherwise what Vision reads off the image or the
    /// PDF's first pages.
    static func recognise(_ url: URL) async -> String {
        await Task.detached(priority: .userInitiated) {
            if isPDF(url), let pdf = PDFDocument(url: url) {
                let text = pdf.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.count > 20 { return text }
                return (0..<min(pdf.pageCount, 3)).compactMap { pdf.page(at: $0).flatMap(image(of:)) }.map(read).joined(separator: "\n")
            }
            guard let image = cgImage(url) else { return "" }
            return read(image)
        }.value
    }

    static func isPDF(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .pdf)) ?? (url.pathExtension.lowercased() == "pdf")
    }

    /// A preview for the review sheet: the image, or a PDF's first page.
    static func preview(_ url: URL) -> NSImage? {
        if isPDF(url) {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 900, height: 1300), for: .mediaBox)
        }
        return NSImage(contentsOf: url)
    }

    private static func cgImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldAllowFloat: true] as CFDictionary)
    }

    private static func image(of page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = 2000 / max(bounds.width, bounds.height)
        return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Vision's words, grouped into printed rows (top to bottom), each row left to right.
    private static func read(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-IN", "en-US"]
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let pieces = (request.results ?? []).compactMap { o -> (box: CGRect, text: String)? in
            guard let text = o.topCandidates(1).first?.string else { return nil }
            return (o.boundingBox, text)
        }
        // Vision's boxes are normalised with the origin at the bottom left.
        var rows: [[(box: CGRect, text: String)]] = []
        for piece in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let i = rows.indices.last, let anchor = rows[i].first,
               abs(anchor.box.midY - piece.box.midY) < min(anchor.box.height, piece.box.height) * 0.6 {
                rows[i].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "   ") }.joined(separator: "\n")
    }
}

/// Where receipt images are kept: on this Mac only, as on the phone. Entries carry the path.
enum ReceiptStore {
    static func keep(_ url: URL, as uid: String) -> (path: String, mime: String)? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        let folder = base.appendingPathComponent("Receipts", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let pdf = ReceiptScanner.isPDF(url)
        let ext = pdf ? "pdf" : (url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased())
        let target = folder.appendingPathComponent("\(uid).\(ext)")
        try? fm.removeItem(at: target)
        do { try fm.copyItem(at: url, to: target) } catch { return nil }
        let mime = pdf ? "application/pdf" : (UTType(filenameExtension: ext)?.preferredMIMEType ?? "image/jpeg")
        return (target.path, mime)
    }

    /// Reset data: the kept images go with the entries that pointed at them.
    static func removeAll() {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        try? fm.removeItem(at: base.appendingPathComponent("Receipts", isDirectory: true))
    }
}

/// Turns what arrives by drag-and-drop or Continuity Camera into a file the sheet can read.
enum ReceiptInput {
    static let types: [UTType] = [.image, .pdf, .fileURL]

    /// The first image or PDF among `providers`, copied somewhere it outlives the drop.
    @MainActor static func load(_ providers: [NSItemProvider]) async -> URL? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await fileURL(provider), isReceiptFile(url) {
                return copyToTemp(url)
            }
            for type in [UTType.pdf, .image] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                if let url = await fileRepresentation(provider, type) { return url }
            }
        }
        return nil
    }

    static func isReceiptFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    @MainActor private static func fileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { done in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in done.resume(returning: url) }
        }
    }

    @MainActor private static func fileRepresentation(_ provider: NSItemProvider, _ type: UTType) async -> URL? {
        await withCheckedContinuation { done in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                // The file only lives for this callback.
                done.resume(returning: url.flatMap(copyToTemp))
            }
        }
    }

    private static func copyToTemp(_ url: URL) -> URL? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)
        do { try FileManager.default.copyItem(at: url, to: target) } catch { return nil }
        return target
    }
}
