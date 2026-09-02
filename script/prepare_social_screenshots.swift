#!/usr/bin/env swift

import AppKit
import CoreImage
import Foundation

private let canvasSize = NSSize(width: 1440, height: 1920)
private let releaseURL = "https://github.com/Rand01ph/gemma-trans/releases/tag/v2.0.0"

private struct Palette {
    let background: NSColor
    let surface: NSColor
    let primary: NSColor
    let secondary: NSColor
    let accent: NSColor
    let border: NSColor

    static let light = Palette(
        background: NSColor(calibratedRed: 0.956, green: 0.964, blue: 0.974, alpha: 1),
        surface: .white,
        primary: NSColor(calibratedWhite: 0.06, alpha: 1),
        secondary: NSColor(calibratedWhite: 0.28, alpha: 1),
        accent: NSColor(calibratedRed: 0.01, green: 0.52, blue: 1, alpha: 1),
        border: NSColor(calibratedWhite: 0.1, alpha: 0.1)
    )

    static let dark = Palette(
        background: NSColor(calibratedRed: 0.075, green: 0.088, blue: 0.102, alpha: 1),
        surface: NSColor(calibratedRed: 0.105, green: 0.12, blue: 0.135, alpha: 1),
        primary: NSColor(calibratedWhite: 0.97, alpha: 1),
        secondary: NSColor(calibratedWhite: 0.72, alpha: 1),
        accent: NSColor(calibratedRed: 0.2, green: 0.61, blue: 1, alpha: 1),
        border: NSColor(calibratedWhite: 1, alpha: 0.12)
    )
}

private struct ScreenshotCard {
    let filename: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let source: String
    let cropFromTop: NSRect
    let palette: Palette
}

private func rectFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: canvasSize.height - y - height, width: width, height: height)
}

private func loadImage(_ path: String) throws -> NSImage {
    let url = URL(fileURLWithPath: path)
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(
            domain: "PrepareSocialScreenshots",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "could not load \(path)"]
        )
    }
    return image
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left,
    lineHeightMultiple: CGFloat = 1
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineHeightMultiple = lineHeightMultiple
    NSString(string: text).draw(
        with: rect,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    )
}

private func drawBackground(_ palette: Palette) {
    palette.background.setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    let glow = NSGradient(
        starting: palette.accent.withAlphaComponent(0.16),
        ending: palette.accent.withAlphaComponent(0)
    )
    glow?.draw(
        in: NSBezierPath(
            ovalIn: rectFromTop(x: 710, y: -280, width: 930, height: 930)
        ),
        angle: -45
    )
}

private func drawHeader(
    eyebrow: String,
    title: String,
    subtitle: String,
    palette: Palette
) {
    drawText(
        eyebrow.uppercased(),
        in: rectFromTop(x: 100, y: 92, width: 1240, height: 44),
        font: .systemFont(ofSize: 24, weight: .semibold),
        color: palette.accent
    )
    drawText(
        title,
        in: rectFromTop(x: 100, y: 164, width: 1240, height: 210),
        font: .systemFont(ofSize: 70, weight: .bold),
        color: palette.primary,
        lineHeightMultiple: 0.96
    )
    drawText(
        subtitle,
        in: rectFromTop(x: 100, y: 382, width: 1240, height: 102),
        font: .systemFont(ofSize: 31, weight: .regular),
        color: palette.secondary,
        lineHeightMultiple: 1.08
    )
}

private func drawFooter(index: Int, palette: Palette) {
    drawText(
        String(format: "%02d", index),
        in: rectFromTop(x: 100, y: 1800, width: 90, height: 42),
        font: .monospacedDigitSystemFont(ofSize: 25, weight: .semibold),
        color: palette.accent
    )
    drawText(
        "GemmaTrans 2.0  ·  本地 AI 翻译",
        in: rectFromTop(x: 205, y: 1800, width: 1135, height: 42),
        font: .systemFont(ofSize: 25, weight: .medium),
        color: palette.secondary,
        alignment: .right
    )
}

private func drawRoundedImage(
    _ image: NSImage,
    cropFromTop: NSRect,
    in destination: NSRect,
    palette: Palette,
    radius: CGFloat = 34
) {
    let sourceRect = NSRect(
        x: cropFromTop.minX,
        y: image.size.height - cropFromTop.minY - cropFromTop.height,
        width: cropFromTop.width,
        height: cropFromTop.height
    )

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
    shadow.shadowBlurRadius = 38
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    palette.surface.setFill()
    NSBezierPath(roundedRect: destination, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: destination, xRadius: radius, yRadius: radius).addClip()
    image.draw(in: destination, from: sourceRect, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    palette.border.setStroke()
    let border = NSBezierPath(roundedRect: destination, xRadius: radius, yRadius: radius)
    border.lineWidth = 2
    border.stroke()
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
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(
            domain: "PrepareSocialScreenshots",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "could not create output bitmap"]
        )
    }

    bitmap.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(
        in: NSRect(origin: .zero, size: image.size),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(
        using: .jpeg,
        properties: [.compressionFactor: 0.94]
    ) else {
        throw NSError(
            domain: "PrepareSocialScreenshots",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "could not encode JPEG"]
        )
    }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
}

private func renderCanvas(
    size: NSSize = canvasSize,
    _ draw: () -> Void
) -> NSImage {
    let canvas = NSImage(size: size)
    canvas.lockFocus()
    draw()
    canvas.unlockFocus()
    return canvas
}

private func drawPill(
    _ text: String,
    top: CGFloat,
    palette: Palette,
    number: Int? = nil
) {
    let rect = rectFromTop(x: 100, y: top, width: 1240, height: 142)
    palette.surface.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30).fill()
    palette.border.setStroke()
    let outline = NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30)
    outline.lineWidth = 2
    outline.stroke()

    if let number {
        let numberRect = NSRect(
            x: rect.minX + 28,
            y: rect.midY - 31,
            width: 62,
            height: 62
        )
        palette.accent.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: numberRect, xRadius: 20, yRadius: 20).fill()
        drawText(
            "\(number)",
            in: NSRect(x: numberRect.minX, y: numberRect.minY + 12, width: 62, height: 38),
            font: .monospacedDigitSystemFont(ofSize: 25, weight: .bold),
            color: palette.accent,
            alignment: .center
        )
    }

    drawText(
        text,
        in: NSRect(
            x: rect.minX + (number == nil ? 38 : 112),
            y: rect.minY + 45,
            width: rect.width - (number == nil ? 76 : 150),
            height: 52
        ),
        font: .systemFont(ofSize: 31, weight: .semibold),
        color: palette.primary
    )
}

private func qrCode(for value: String, size: CGFloat) -> NSImage? {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(Data(value.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else { return nil }
    let scale = floor(size / output.extent.width)
    let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let representation = NSCIImageRep(ciImage: transformed)
    let image = NSImage(size: representation.size)
    image.addRepresentation(representation)
    return image
}

private func screenshotCards(root: URL) -> [ScreenshotCard] {
    let base = root.appendingPathComponent("docs/app-store/screenshots/2.0.0").path
    return [
        ScreenshotCard(
            filename: "02-main-window.jpg",
            eyebrow: "主窗口",
            title: "双栏翻译，一眼完成校对",
            subtitle: "原文与译文并排呈现，内容、操作和状态层级清楚。",
            source: "\(base)/01-main-dark.jpg",
            cropFromTop: NSRect(x: 245, y: 260, width: 2070, height: 1270),
            palette: .dark
        ),
        ScreenshotCard(
            filename: "03-quick-panel.jpg",
            eyebrow: "划词翻译",
            title: "选中文字，译文就出现",
            subtitle: "浮窗可以固定位置，连续翻译长文时不打断阅读。",
            source: "\(base)/03-panel-light.jpg",
            cropFromTop: NSRect(x: 200, y: 560, width: 2160, height: 740),
            palette: .light
        ),
        ScreenshotCard(
            filename: "04-general-settings.jpg",
            eyebrow: "通用设置",
            title: "选项更少，真正有用",
            subtitle: "外观、目标语言和译文字号都保持紧凑、直接。",
            source: "\(base)/04-settings-general-light.jpg",
            cropFromTop: NSRect(x: 560, y: 285, width: 1440, height: 1235),
            palette: .light
        ),
        ScreenshotCard(
            filename: "05-local-models.jpg",
            eyebrow: "本地模型",
            title: "四款模型，按需下载",
            subtitle: "首次启动不自动下载；海外源不可用时自动切换国内源。",
            source: "\(base)/05-settings-models-light.jpg",
            cropFromTop: NSRect(x: 560, y: 285, width: 1440, height: 1235),
            palette: .light
        ),
        ScreenshotCard(
            filename: "06-integrations.jpg",
            eyebrow: "接入工作流",
            title: "快捷键与本地 API",
            subtitle: "连接 PopClip、Bob、Raycast，或者你自己的本地工具。",
            source: "\(base)/06-settings-integrations-light.jpg",
            cropFromTop: NSRect(x: 560, y: 285, width: 1440, height: 1235),
            palette: .light
        )
    ]
}

private func makeScreenshotCard(_ card: ScreenshotCard, index: Int) throws -> NSImage {
    let source = try loadImage(card.source)
    return renderCanvas {
        drawBackground(card.palette)
        drawHeader(
            eyebrow: card.eyebrow,
            title: card.title,
            subtitle: card.subtitle,
            palette: card.palette
        )

        let cropAspect = card.cropFromTop.width / card.cropFromTop.height
        let contentWidth: CGFloat = 1240
        let maximumHeight: CGFloat = 1160
        var contentHeight = contentWidth / cropAspect
        var renderedWidth = contentWidth
        if contentHeight > maximumHeight {
            contentHeight = maximumHeight
            renderedWidth = contentHeight * cropAspect
        }
        let destination = rectFromTop(
            x: (canvasSize.width - renderedWidth) / 2,
            y: 555,
            width: renderedWidth,
            height: contentHeight
        )
        drawRoundedImage(
            source,
            cropFromTop: card.cropFromTop,
            in: destination,
            palette: card.palette
        )
        drawFooter(index: index, palette: card.palette)
    }
}

private func makeCover(root: URL) throws -> NSImage {
    let palette = Palette.dark
    let source = try loadImage(
        root.appendingPathComponent(
            "docs/app-store/screenshots/2.0.0/01-main-dark.jpg"
        ).path
    )
    let icon = try loadImage(
        root.appendingPathComponent(
            "App/GemmaTrans/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png"
        ).path
    )

    return renderCanvas {
        drawBackground(palette)
        icon.draw(
            in: rectFromTop(x: 100, y: 100, width: 132, height: 132),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        drawText(
            "GemmaTrans 2.0",
            in: rectFromTop(x: 265, y: 118, width: 1000, height: 60),
            font: .systemFont(ofSize: 36, weight: .semibold),
            color: palette.primary
        )
        drawText(
            "我和 AI 把一个翻译 App 的 UI\n重做了五遍",
            in: rectFromTop(x: 100, y: 300, width: 1240, height: 270),
            font: .systemFont(ofSize: 76, weight: .bold),
            color: palette.primary,
            lineHeightMultiple: 0.96
        )
        drawText(
            "这一次，我们不只做了 Liquid Glass，\n还把设计规则写进了项目。",
            in: rectFromTop(x: 100, y: 600, width: 1240, height: 120),
            font: .systemFont(ofSize: 33, weight: .regular),
            color: palette.secondary,
            lineHeightMultiple: 1.08
        )
        drawRoundedImage(
            source,
            cropFromTop: NSRect(x: 245, y: 260, width: 2070, height: 1270),
            in: rectFromTop(x: 100, y: 840, width: 1240, height: 760),
            palette: palette
        )
        drawFooter(index: 1, palette: palette)
    }
}

private func makeDesignCard() -> NSImage {
    let palette = Palette.dark
    return renderCanvas {
        drawBackground(palette)
        drawHeader(
            eyebrow: "DESIGN.MD",
            title: "玻璃不是越多越高级",
            subtitle: "我们把审美写成了每次迭代都能复用、检查和推翻的规则。",
            palette: palette
        )
        drawPill("窗口外壳：Liquid Glass 表达空间层级", top: 600, palette: palette)
        drawPill("阅读内容：安静、清楚，不再叠第二层玻璃", top: 776, palette: palette)
        drawPill("主操作：只使用系统 Accent 强调", top: 952, palette: palette)
        drawPill("状态反馈：就绪、失败、危险各守语义", top: 1128, palette: palette)
        drawText(
            "“内容不是玻璃。玻璃主要负责表达窗口层级和操作；译文阅读面保持安静。”",
            in: rectFromTop(x: 125, y: 1395, width: 1190, height: 190),
            font: .systemFont(ofSize: 40, weight: .semibold),
            color: palette.primary,
            alignment: .center,
            lineHeightMultiple: 1.05
        )
        drawFooter(index: 7, palette: palette)
    }
}

private func makeProcessCard() -> NSImage {
    let palette = Palette.light
    return renderCanvas {
        drawBackground(palette)
        drawHeader(
            eyebrow: "AI × DESIGN",
            title: "最重要的不是一句 Prompt",
            subtitle: "真正让结果变好的，是把 AI 放进一套可验证的设计闭环。",
            palette: palette
        )
        let steps = [
            "拆解组件与真实使用场景",
            "用设计审查 Skill 找出问题",
            "记录 Before / After / Why",
            "启动 fresh build，截图验证",
            "不对就推翻，再迭代一轮"
        ]
        for (offset, step) in steps.enumerated() {
            drawPill(
                step,
                top: 565 + CGFloat(offset) * 190,
                palette: palette,
                number: offset + 1
            )
        }
        drawFooter(index: 8, palette: palette)
    }
}

private func makeDownloadCard(root: URL) throws -> NSImage {
    let palette = Palette.dark
    let icon = try loadImage(
        root.appendingPathComponent(
            "App/GemmaTrans/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png"
        ).path
    )
    return renderCanvas {
        drawBackground(palette)
        icon.draw(
            in: rectFromTop(x: 495, y: 205, width: 450, height: 450),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        drawText(
            "GemmaTrans 2.0",
            in: rectFromTop(x: 100, y: 755, width: 1240, height: 86),
            font: .systemFont(ofSize: 70, weight: .bold),
            color: palette.primary,
            alignment: .center
        )
        drawText(
            "完全运行在 Mac 本地的 AI 翻译工具",
            in: rectFromTop(x: 100, y: 865, width: 1240, height: 60),
            font: .systemFont(ofSize: 32, weight: .regular),
            color: palette.secondary,
            alignment: .center
        )

        if let qr = qrCode(for: releaseURL, size: 340) {
            let qrBackground = rectFromTop(x: 500, y: 1010, width: 440, height: 440)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: qrBackground, xRadius: 42, yRadius: 42).fill()
            qr.draw(
                in: rectFromTop(x: 550, y: 1060, width: 340, height: 340),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
        }

        drawText(
            "扫码前往 GitHub 下载",
            in: rectFromTop(x: 100, y: 1490, width: 1240, height: 55),
            font: .systemFont(ofSize: 30, weight: .semibold),
            color: palette.primary,
            alignment: .center
        )
        drawText(
            "Apple Silicon  ·  macOS 15+  ·  免费开源",
            in: rectFromTop(x: 100, y: 1560, width: 1240, height: 50),
            font: .systemFont(ofSize: 26, weight: .regular),
            color: palette.secondary,
            alignment: .center
        )
        drawFooter(index: 9, palette: palette)
    }
}

private func makeContactSheet(images: [NSImage]) -> NSImage {
    let size = NSSize(width: 2160, height: 2880)
    let margin: CGFloat = 90
    let gap: CGFloat = 42
    let thumbWidth = (size.width - margin * 2 - gap * 2) / 3
    let thumbHeight = thumbWidth * 4 / 3

    return renderCanvas(size: size) {
        NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        for (index, image) in images.enumerated() {
            let column = index % 3
            let row = index / 3
            let x = margin + CGFloat(column) * (thumbWidth + gap)
            let yFromTop = margin + CGFloat(row) * (thumbHeight + gap)
            let destination = NSRect(
                x: x,
                y: size.height - yFromTop - thumbHeight,
                width: thumbWidth,
                height: thumbHeight
            )

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = 22
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: destination, xRadius: 24, yRadius: 24).fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: destination, xRadius: 24, yRadius: 24).addClip()
            image.draw(in: destination, from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

do {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let output = root.appendingPathComponent(
        "docs/social/screenshots/2.0.0/xiaohongshu"
    )

    var generatedImages: [NSImage] = []
    let cover = try makeCover(root: root)
    generatedImages.append(cover)
    try writeJPEG(cover, to: output.appendingPathComponent("01-cover.jpg"))
    for (offset, card) in screenshotCards(root: root).enumerated() {
        let image = try makeScreenshotCard(card, index: offset + 2)
        generatedImages.append(image)
        try writeJPEG(
            image,
            to: output.appendingPathComponent(card.filename)
        )
    }
    let design = makeDesignCard()
    generatedImages.append(design)
    try writeJPEG(design, to: output.appendingPathComponent("07-design-system.jpg"))
    let process = makeProcessCard()
    generatedImages.append(process)
    try writeJPEG(process, to: output.appendingPathComponent("08-ai-design-process.jpg"))
    let download = try makeDownloadCard(root: root)
    generatedImages.append(download)
    try writeJPEG(download, to: output.appendingPathComponent("09-download.jpg"))
    try writeJPEG(
        makeContactSheet(images: generatedImages),
        to: output.deletingLastPathComponent().appendingPathComponent("xiaohongshu-preview.jpg")
    )
    print("Wrote 9 Xiaohongshu images to \(output.path)")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
