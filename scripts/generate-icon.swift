import AppKit
let output = CommandLine.arguments[1]
let directory = URL(fileURLWithPath: output).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: pixels*4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels)/1024, y: CGFloat(pixels)/1024)
    let rect = NSRect(x: 74, y: 74, width: 876, height: 876)
    let path = NSBezierPath(roundedRect: rect, xRadius: 208, yRadius: 208)
    NSGradient(starting: NSColor(red: 0.60, green: 0.48, blue: 0.99, alpha: 1), ending: NSColor(red: 0.37, green: 0.27, blue: 0.80, alpha: 1))!.draw(in: path, angle: -80)
    NSColor.white.setStroke()
    let frame = NSBezierPath(); frame.lineWidth = 50; frame.lineCapStyle = .round; frame.lineJoinStyle = .round
    for (x,y,dx,dy) in [(CGFloat(292),CGFloat(292),CGFloat(1),CGFloat(1)),(732,292,-1,1),(292,732,1,-1),(732,732,-1,-1)] {
        frame.move(to: NSPoint(x:x, y:y+dy*104)); frame.line(to:NSPoint(x:x,y:y)); frame.line(to:NSPoint(x:x+dx*104,y:y))
    }
    frame.stroke()
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect:NSRect(x:390,y:410,width:244,height:204),xRadius:28,yRadius:28).fill()
    NSColor(red:0.50,green:0.38,blue:0.90,alpha:1).setFill()
    NSBezierPath(ovalIn:NSRect(x:464,y:463,width:96,height:96)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name+".png"))
}
let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/iconutil"); process.arguments = ["-c","icns",directory.path,"-o",URL(fileURLWithPath:output).appendingPathComponent("AppIcon.icns").path]
try process.run(); process.waitUntilExit()
if process.terminationStatus != 0 { exit(process.terminationStatus) }
