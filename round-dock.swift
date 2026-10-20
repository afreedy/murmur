import AppKit
let args = CommandLine.arguments
let source = NSImage(contentsOfFile: args[1])!
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let rect = NSRect(x: 96, y: 96, width: 832, height: 832)
NSBezierPath(roundedRect: rect, xRadius: 186, yRadius: 186).addClip()
source.draw(in: rect)
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
