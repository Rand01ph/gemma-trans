import AppKit
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let badge = CommandLine.arguments[3]
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let data = try Data(contentsOf: source.appendingPathComponent("Contents.json"))
try data.write(to: output.appendingPathComponent("Contents.json"))
let catalog = try JSONSerialization.jsonObject(with: data) as! [String: Any]
for item in catalog["images"] as! [[String: String]] {
    guard let file = item["filename"], let input = NSImage(contentsOf: source.appendingPathComponent(file)),
          let imageData = input.tiffRepresentation, let original = NSBitmapImageRep(data: imageData) else { continue }
    let width = original.pixelsWide, height = original.pixelsHigh
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let w = CGFloat(width), h = CGFloat(height)
    input.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    (badge == "QA" ? NSColor.systemPurple : NSColor.systemBlue).setFill()
    NSBezierPath(roundedRect: NSRect(x: w * 0.40, y: h * 0.12, width: w * 0.49, height: h * 0.25),
                 xRadius: w * 0.05, yRadius: h * 0.05).fill()
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: h * 0.17), .foregroundColor: NSColor.white]
    let size = (badge as NSString).size(withAttributes: attributes)
    (badge as NSString).draw(at: NSPoint(x: w * 0.645 - size.width / 2, y: h * 0.245 - size.height / 2), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(file))
}
