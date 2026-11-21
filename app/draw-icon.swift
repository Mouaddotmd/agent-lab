// Draws Agent Lab's icon: a rounded square in a deep gradient with two overlapping people.
import AppKit
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.20, green: 0.22, blue: 0.62, alpha: 1), NSColor(red: 0.45, green: 0.25, blue: 0.75, alpha: 1)])!.draw(in: path, angle: -60)
let cfg = NSImage.SymbolConfiguration(pointSize: 420, weight: .medium).applying(.init(paletteColors: [.white, NSColor.white.withAlphaComponent(0.7)]))
if let sym = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
  let s = sym.size
  sym.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
