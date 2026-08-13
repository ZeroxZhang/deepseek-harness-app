/**
 * DeepSeek Harness — icon generator.
 *
 * Renders the repo favicon (SVG) as a white glyph on a DeepSeek-blue gradient
 * rounded square, writes an `.iconset`, and assembles `AppIcon.icns` via
 * `iconutil`. Falls back to white "DS" initials if the SVG cannot be
 * rasterized.
 *
 * Usage: icon-gen <svg-path> <out-icns-path> [preview-png-path]
 */

import Cocoa

@main
struct IconGenMain {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            fail("usage: icon-gen <svg-path> <out-icns-path> [preview-png-path]")
        }
        let svgPath = args[1]
        let icnsPath = args[2]
        let previewPath = args.count >= 4 ? args[3] : nil

        guard let base = renderBase(svgPath: svgPath) else {
            fail("could not render base icon")
        }

        let fm = FileManager.default
        // The directory name must end with `.iconset` for iconutil to accept it.
        let iconsetDir = NSTemporaryDirectory() + "dsh-icon-\(ProcessInfo.processInfo.processIdentifier).iconset"
        try? fm.removeItem(atPath: iconsetDir)
        do {
            try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
        } catch {
            fail("could not create iconset directory: \(error)")
        }

        let entries: [(name: String, px: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for entry in entries {
            guard let data = scaledPNG(base, px: entry.px) else {
                fail("could not render \(entry.px)px icon")
            }
            let url = URL(fileURLWithPath: iconsetDir).appendingPathComponent("\(entry.name).png")
            do {
                try data.write(to: url)
            } catch {
                fail("could not write \(url.path): \(error)")
            }
        }

        if let previewPath = previewPath, let data = scaledPNG(base, px: 512) {
            try? data.write(to: URL(fileURLWithPath: previewPath))
        }

        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
        do {
            try iconutil.run()
            iconutil.waitUntilExit()
        } catch {
            fail("iconutil failed: \(error)")
        }
        guard iconutil.terminationStatus == 0 else {
            fail("iconutil exited \(iconutil.terminationStatus)")
        }
        try? fm.removeItem(atPath: iconsetDir)
        print("icon: \(icnsPath)")
    }

    // MARK: rendering

    static func renderBase(svgPath: String) -> CGImage? {
        let px = 1024
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Rounded-square background with the DeepSeek blue gradient.
        let canvas = CGRect(x: 0, y: 0, width: px, height: px)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: canvas, cornerWidth: 224, cornerHeight: 224, transform: nil))
        ctx.clip()
        let colors = [
            CGColor(srgbRed: 0.35, green: 0.48, blue: 1.0, alpha: 1),
            CGColor(srgbRed: 0.19, green: 0.26, blue: 0.88, alpha: 1),
        ] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])
        ctx.restoreGState()

        // White whale: use the SVG's alpha channel as a mask.
        if let svg = NSImage(contentsOfFile: svgPath) {
            var proposed = CGRect(origin: .zero, size: svg.size)
            if let cg = svg.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
                let glyphRect = canvas.insetBy(dx: 180, dy: 180)
                ctx.saveGState()
                ctx.clip(to: glyphRect, mask: cg)
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(glyphRect)
                ctx.restoreGState()
                return ctx.makeImage()
            }
        }

        // Fallback: white "DS" initials.
        let text = NSAttributedString(string: "DS", attributes: [
            .font: NSFont.systemFont(ofSize: 430, weight: .bold),
            .foregroundColor: NSColor.white,
        ])
        let textSize = text.size()
        let drawPoint = NSPoint(
            x: (CGFloat(px) - textSize.width) / 2,
            y: (CGFloat(px) - textSize.height) / 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        text.draw(at: drawPoint)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    static func scaledPNG(_ source: CGImage, px: Int) -> Data? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: px, height: px))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(("icon-gen: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }
}
