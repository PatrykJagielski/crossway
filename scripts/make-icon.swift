// Renders the Crossway app icon (1024×1024 PNG). Usage: swift make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Rounded "squircle" background with a purple → pink gradient.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(path)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let colors = [NSColor(calibratedRed: 0.36, green: 0.16, blue: 0.75, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.93, green: 0.27, blue: 0.48, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

// Windows-like 2×2 panes, faint, in the background.
ctx.setFillColor(NSColor.white.withAlphaComponent(0.10).cgColor)
let pane: CGFloat = 150, gap: CGFloat = 18
let origin = CGPoint(x: rect.maxX - pane * 2 - gap - 70, y: rect.minY + 70)
for row in 0..<2 { for col in 0..<2 {
    ctx.fill(CGRect(x: origin.x + CGFloat(col) * (pane + gap), y: origin.y + CGFloat(row) * (pane + gap), width: pane, height: pane))
}}
ctx.restoreGState()

// Wine glass symbol in the centre.
let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let glass = NSImage(systemSymbolName: "wineglass.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = glass.size
    glass.draw(in: CGRect(x: (size - s.width) / 2, y: (size - s.height) / 2 + 10, width: s.width, height: s.height))
}
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
