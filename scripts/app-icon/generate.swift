// Renders App/Assets.xcassets/AppIcon.appiconset from icon.svg on Apple's macOS icon grid: the tile
// clipped to an 824-pt continuous rounded rect, inset 100 pt in the 1024 canvas, with a drop shadow.
// Run: xcrun swift scripts/app-icon/generate.swift
import AppKit
import SwiftUI

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let output = here.appending(path: "../../App/Assets.xcassets/AppIcon.appiconset").standardizedFileURL
guard let tile = NSImage(contentsOf: here.appending(path: "icon.svg")) else {
    fatalError("Can't read icon.svg")
}

func render(pixels: Int) -> Data {
    let scale = CGFloat(pixels) / 1024
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: scale, y: scale)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: body).cgPath

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.addPath(shape)
    context.clip()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    tile.draw(in: body)
    NSGraphicsContext.current = nil

    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    return bitmap.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: output.appending(path: name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appending(path: "Contents.json"))
print("Wrote \(images.count) icons to \(output.path)")
