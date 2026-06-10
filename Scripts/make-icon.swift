#!/usr/bin/swift
// 渲染占位图标（圆角渐变底 + 白色"译"字），产出 iconset 供 iconutil 转 .icns
import AppKit

let variants: [(px: Int, name: String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
let iconset = "/tmp/GemmaTransAppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for (px, name) in variants {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.05
    let path = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset),
        xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(
        starting: NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.96, alpha: 1),
        ending: NSColor(calibratedRed: 0.05, green: 0.25, blue: 0.65, alpha: 1)
    )!.draw(in: path, angle: -90)
    let text = NSAttributedString(string: "译", attributes: [
        .font: NSFont.systemFont(ofSize: s * 0.52, weight: .semibold),
        .foregroundColor: NSColor.white,
    ])
    let ts = text.size()
    text.draw(at: NSPoint(x: (s - ts.width) / 2, y: (s - ts.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
print("iconset 渲染完成: \(iconset)")
