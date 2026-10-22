import AppKit

// Vector-drawn desk riser icon; export as an opaque 1024px App Store icon.
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                        bytesPerRow: 1024 * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.94, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let ink = NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.18, alpha: 1)
ink.setFill()
NSBezierPath(roundedRect: NSRect(x: 180, y: 585, width: 664, height: 66), xRadius: 25, yRadius: 25).fill()
NSBezierPath(roundedRect: NSRect(x: 180, y: 232, width: 664, height: 48), xRadius: 20, yRadius: 20).fill()
let legs = NSBezierPath()
legs.lineWidth = 40
legs.lineCapStyle = .round
legs.move(to: NSPoint(x: 290, y: 300)); legs.line(to: NSPoint(x: 450, y: 560))
legs.move(to: NSPoint(x: 734, y: 300)); legs.line(to: NSPoint(x: 574, y: 560))
ink.setStroke(); legs.stroke()
let arrow = NSBezierPath()
arrow.lineWidth = 38
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 512, y: 718)); arrow.line(to: NSPoint(x: 512, y: 845))
arrow.move(to: NSPoint(x: 454, y: 790)); arrow.line(to: NSPoint(x: 512, y: 848)); arrow.line(to: NSPoint(x: 570, y: 790))
NSColor(calibratedRed: 0.72, green: 0.25, blue: 0.17, alpha: 1).setStroke(); arrow.stroke()
NSGraphicsContext.restoreGraphicsState()
let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
