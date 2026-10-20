import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16,32,64,128,256,512,1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 512
    NSColor(srgbRed: 159/255, green: 232/255, blue: 112/255, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 8*scale, y: 8*scale, width: 496*scale, height: 496*scale), xRadius: 112*scale, yRadius: 112*scale).fill()
    NSColor(srgbRed: 22/255, green: 51/255, blue: 0, alpha: 1).setFill()
    for (i,h) in [100,190,290,190,100].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: CGFloat(120 + i*56)*scale, y: CGFloat(256-h/2)*scale, width: 32*scale, height: CGFloat(h)*scale), xRadius: 16*scale, yRadius: 16*scale).fill()
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = rep.representation(using: .png, properties: [:])!
    let name = size == 1024 ? "icon_512x512@2x.png" : "icon_\(size)x\(size).png"
    try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    if [32,64,256,512].contains(size) {
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png"))
    }
}
