import Foundation
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

NSColor(red: 0.61, green: 0.74, blue: 0.36, alpha: 1.0).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

NSColor(red: 0.82, green: 0.18, blue: 0.18, alpha: 1.0).setFill()
let crossSize: CGFloat = 300
let crossX = (size - crossSize) / 2
let crossY = (size - crossSize) / 2
let barWidth: CGFloat = 80

NSBezierPath(rect: NSRect(x: crossX + crossSize/2 - barWidth/2, y: crossY, width: barWidth, height: crossSize)).fill()
NSBezierPath(rect: NSRect(x: crossX, y: crossY + crossSize/2 - barWidth/2, width: crossSize, height: barWidth)).fill()

image.unlockFocus()

let tiffData = image.tiffRepresentation!
let bitmap = NSBitmapImageRep(data: tiffData)!
let pngData = bitmap.representation(using: .png, properties: [:])!
try pngData.write(to: URL(fileURLWithPath: "Icon-1024.png"))
print("Created Icon-1024.png")
