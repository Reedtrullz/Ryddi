#!/usr/bin/swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: Scripts/generate-app-icon.swift OUTPUT.png\n".utf8))
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = CGSize(width: 1_024, height: 1_024)
let image = NSImage(size: size)
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    FileHandle.standardError.write(Data("could not create icon drawing context\n".utf8))
    exit(1)
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let outer = CGPath(
    roundedRect: CGRect(x: 42, y: 42, width: 940, height: 940),
    cornerWidth: 210,
    cornerHeight: 210,
    transform: nil
)
context.addPath(outer)
context.setFillColor(NSColor(srgbRed: 0.075, green: 0.09, blue: 0.105, alpha: 1).cgColor)
context.fillPath()

context.addPath(outer)
context.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
context.setLineWidth(18)
context.strokePath()

let bladeColors = [
    NSColor(srgbRed: 0.15, green: 0.72, blue: 0.95, alpha: 1),
    NSColor(srgbRed: 0.24, green: 0.84, blue: 0.53, alpha: 1),
    NSColor(srgbRed: 0.96, green: 0.46, blue: 0.38, alpha: 1),
    NSColor(srgbRed: 0.88, green: 0.91, blue: 0.94, alpha: 1)
]

for index in 0..<4 {
    context.saveGState()
    context.translateBy(x: 512, y: 512)
    context.rotate(by: CGFloat(index) * .pi / 2)
    let blade = CGMutablePath()
    blade.move(to: CGPoint(x: 18, y: 72))
    blade.addCurve(
        to: CGPoint(x: 238, y: 300),
        control1: CGPoint(x: 80, y: 98),
        control2: CGPoint(x: 214, y: 198)
    )
    blade.addCurve(
        to: CGPoint(x: 326, y: 194),
        control1: CGPoint(x: 308, y: 315),
        control2: CGPoint(x: 347, y: 270)
    )
    blade.addCurve(
        to: CGPoint(x: 74, y: -16),
        control1: CGPoint(x: 306, y: 80),
        control2: CGPoint(x: 184, y: -5)
    )
    blade.addCurve(
        to: CGPoint(x: 18, y: 72),
        control1: CGPoint(x: 43, y: -12),
        control2: CGPoint(x: 24, y: 21)
    )
    blade.closeSubpath()
    context.addPath(blade)
    context.setFillColor(bladeColors[index].cgColor)
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.fillPath()
    context.restoreGState()
}

context.setShadow(offset: .zero, blur: 0, color: nil)
context.addEllipse(in: CGRect(x: 382, y: 382, width: 260, height: 260))
context.setFillColor(NSColor(srgbRed: 0.075, green: 0.09, blue: 0.105, alpha: 1).cgColor)
context.fillPath()
context.addEllipse(in: CGRect(x: 406, y: 406, width: 212, height: 212))
context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
context.setLineWidth(22)
context.strokePath()
context.addEllipse(in: CGRect(x: 468, y: 468, width: 88, height: 88))
context.setFillColor(NSColor(srgbRed: 0.24, green: 0.84, blue: 0.53, alpha: 1).cgColor)
context.fillPath()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode icon PNG\n".utf8))
    exit(1)
}
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: output, options: .atomic)
