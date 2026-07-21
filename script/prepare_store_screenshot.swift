#!/usr/bin/env swift

import AppKit
import Foundation

private struct Arguments {
    let capturedURL: URL
    let cleanHeaderURL: URL
    let outputURL: URL
    let background: NSColor
    let title: String?
    let subtitle: String?

    init() throws {
        let values = CommandLine.arguments
        guard (5...7).contains(values.count) else {
            throw NSError(
                domain: "PrepareStoreScreenshot",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    "usage: prepare_store_screenshot.swift <captured> <clean-header> <output.jpg> <RRGGBB> [title] [subtitle]"]
            )
        }
        capturedURL = URL(fileURLWithPath: values[1])
        cleanHeaderURL = URL(fileURLWithPath: values[2])
        outputURL = URL(fileURLWithPath: values[3])
        guard values[4].count == 6, let rgb = Int(values[4], radix: 16) else {
            throw NSError(
                domain: "PrepareStoreScreenshot",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "background must be a six-digit RGB hex value"]
            )
        }
        background = NSColor(
            calibratedRed: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255,
            alpha: 1
        )
        title = values.indices.contains(5) && !values[5].isEmpty ? values[5] : nil
        subtitle = values.indices.contains(6) && !values[6].isEmpty ? values[6] : nil
    }
}

private func loadImage(_ url: URL) throws -> NSImage {
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(
            domain: "PrepareStoreScreenshot",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "could not load \(url.path)"]
        )
    }
    return image
}

private func patchedCapture(captured: NSImage, cleanHeader: NSImage) -> NSImage {
    let canvas = NSImage(size: captured.size)
    canvas.lockFocus()
    captured.draw(
        in: NSRect(origin: .zero, size: captured.size),
        from: .zero,
        operation: .copy,
        fraction: 1
    )

    // Computer Use places a 75 × 22 pt status pill and the system pointer over
    // the active window. Before capture we park the pointer in this title-bar
    // region, then replace only the region from the app's deterministic Debug
    // fixture. Every product pixel below the title bar remains untouched.
    let patchSize = NSSize(width: min(220, captured.size.width), height: min(42, captured.size.height))
    let fixtureScale = max(cleanHeader.size.width / captured.size.width, 1)
    let sourceSize = NSSize(
        width: min(patchSize.width * fixtureScale, cleanHeader.size.width),
        height: min(patchSize.height * fixtureScale, cleanHeader.size.height)
    )
    let sourceRect = NSRect(
        x: 0,
        y: cleanHeader.size.height - sourceSize.height,
        width: sourceSize.width,
        height: sourceSize.height
    )
    let destinationRect = NSRect(
        x: 0,
        y: captured.size.height - patchSize.height,
        width: patchSize.width,
        height: patchSize.height
    )
    cleanHeader.draw(
        in: destinationRect,
        from: sourceRect,
        operation: .copy,
        fraction: 1
    )
    canvas.unlockFocus()
    return canvas
}

private func storeCanvas(
    image: NSImage,
    background: NSColor,
    title: String?,
    subtitle: String?
) -> NSImage {
    let targetSize = NSSize(width: 2560, height: 1600)
    let hasCaption = title != nil || subtitle != nil
    let maximumContentSize = hasCaption
        ? NSSize(width: 2300, height: 1130)
        : NSSize(width: 2400, height: 1480)
    let scale = min(
        maximumContentSize.width / image.size.width,
        maximumContentSize.height / image.size.height
    )
    let renderedSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderedRect = NSRect(
        x: (targetSize.width - renderedSize.width) / 2,
        y: hasCaption ? 100 : (targetSize.height - renderedSize.height) / 2,
        width: renderedSize.width,
        height: renderedSize.height
    )

    let canvas = NSImage(size: targetSize)
    canvas.lockFocus()
    background.setFill()
    NSRect(origin: .zero, size: targetSize).fill()

    if hasCaption {
        let components = background.usingColorSpace(.deviceRGB)
        let luminance = (components?.redComponent ?? 1) * 0.2126
            + (components?.greenComponent ?? 1) * 0.7152
            + (components?.blueComponent ?? 1) * 0.0722
        let primary = luminance > 0.55
            ? NSColor(calibratedWhite: 0.07, alpha: 1)
            : NSColor(calibratedWhite: 0.97, alpha: 1)
        let secondary = primary.withAlphaComponent(0.62)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        if let title {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 72, weight: .semibold),
                .foregroundColor: primary,
                .paragraphStyle: paragraphStyle
            ]
            NSString(string: title).draw(
                in: NSRect(x: 130, y: 1420, width: 2300, height: 92),
                withAttributes: attributes
            )
        }
        if let subtitle {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 34, weight: .regular),
                .foregroundColor: secondary,
                .paragraphStyle: paragraphStyle
            ]
            NSString(string: subtitle).draw(
                in: NSRect(x: 180, y: 1350, width: 2200, height: 52),
                withAttributes: attributes
            )
        }
    }

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(
        roundedRect: renderedRect,
        xRadius: 18 * scale,
        yRadius: 18 * scale
    ).addClip()
    image.draw(in: renderedRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    canvas.unlockFocus()
    return canvas
}

private func writeJPEG(_ image: NSImage, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(image.size.width),
        pixelsHigh: Int(image.size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(
            domain: "PrepareStoreScreenshot",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "could not create output bitmap"]
        )
    }
    bitmap.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
        throw NSError(
            domain: "PrepareStoreScreenshot",
            code: 6,
            userInfo: [NSLocalizedDescriptionKey: "could not encode JPEG"]
        )
    }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
}

do {
    let arguments = try Arguments()
    let captured = try loadImage(arguments.capturedURL)
    let cleanHeader = try loadImage(arguments.cleanHeaderURL)
    let patched = patchedCapture(captured: captured, cleanHeader: cleanHeader)
    let canvas = storeCanvas(
        image: patched,
        background: arguments.background,
        title: arguments.title,
        subtitle: arguments.subtitle
    )
    try writeJPEG(canvas, to: arguments.outputURL)
    print("Wrote \(arguments.outputURL.path)")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
