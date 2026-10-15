// Regenerate with: xcrun swift -module-cache-path /private/tmp/lilt-icon-cache Lilt/Tools/GenerateIcon.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import simd

let size = 1024
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let asset = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: asset, withIntermediateDirectories: true)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}
func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func gradient(_ colors: [CGColor], locations: [CGFloat]? = nil, from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
    context.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func fill(_ path: CGPath, with fill: CGColor) {
    context.addPath(path); context.setFillColor(fill); context.fillPath()
}

// An opaque full-bleed walnut case. The system supplies the final iOS icon mask.
gradient([color(0.38, 0.235, 0.11), color(0.245, 0.13, 0.055)],
         from: CGPoint(x: 0, y: 0), to: CGPoint(x: 970, y: 1024))
let rim = rounded(CGRect(x: 29, y: 29, width: 966, height: 966), 89)
context.saveGState()
context.addPath(rim); context.clip()
gradient([color(0.73, 0.52, 0.29), color(0.46, 0.28, 0.13), color(0.29, 0.15, 0.06)],
         locations: [0, 0.53, 1], from: CGPoint(x: 60, y: 30), to: CGPoint(x: 960, y: 1060))
context.restoreGState()
context.addPath(rim); context.setLineWidth(3); context.setStrokeColor(color(0.89, 0.7, 0.43, 0.43)); context.strokePath()

let board = rounded(CGRect(x: 66, y: 66, width: 892, height: 892), 53)
context.saveGState()
context.addPath(board); context.clip()
gradient([color(0.895, 0.725, 0.465), color(0.79, 0.585, 0.335), color(0.64, 0.435, 0.22)],
         locations: [0, 0.56, 1], from: CGPoint(x: 220, y: 20), to: CGPoint(x: 890, y: 1240))

// A deterministic, continuous maple grain drawn at icon resolution.
for line in 0..<205 {
    let path = CGMutablePath()
    let x = CGFloat(line) * 5.65 - 60
    for step in 0...50 {
        let y = CGFloat(step) * 22
        let phase = CGFloat(line) * 0.173
        let bend = sin(y * 0.0067 + phase) * 10 + sin(y * 0.015 + phase * 0.35) * 3
        let point = CGPoint(x: x + bend, y: y)
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    context.addPath(path)
    context.setStrokeColor(color(0.325, 0.185, 0.065, line % 5 == 0 ? 0.105 : 0.052))
    context.setLineWidth(line % 5 == 0 ? 1.9 : 0.85)
    context.strokePath()
}
// The inner rebate casts a narrow ambient occlusion line around the floor.
context.addPath(board); context.setLineWidth(12); context.setStrokeColor(color(0.255, 0.145, 0.052, 0.38)); context.strokePath()
context.addPath(rounded(CGRect(x: 72, y: 72, width: 880, height: 880), 48))
context.setLineWidth(2); context.setStrokeColor(color(1, 0.86, 0.58, 0.35)); context.strokePath()
context.restoreGState()

func wall(_ points: [CGPoint]) {
    let path = CGMutablePath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.addLine(to: point) }
    let outline = path.copy(strokingWithWidth: 46, lineCap: .round, lineJoin: .round, miterLimit: 10)
    let foot = path.copy(strokingWithWidth: 50, lineCap: .round, lineJoin: .round, miterLimit: 10)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 11, height: -17), blur: 18, color: color(0.16, 0.085, 0.025, 0.5))
    fill(foot, with: color(0.54, 0.36, 0.17))
    context.restoreGState()
    context.saveGState()
    context.addPath(outline); context.clip()
    gradient([color(0.97, 0.79, 0.505), color(0.85, 0.63, 0.35), color(0.57, 0.375, 0.155)],
             locations: [0, 0.63, 1], from: CGPoint(x: 180, y: points.map(\.y).min()! - 25),
             to: CGPoint(x: 840, y: points.map(\.y).max()! + 35))
    for i in 0..<6 {
        context.addPath(path)
        context.setLineWidth(CGFloat(5 + i * 5))
        context.setStrokeColor(color(0.98, 0.83, 0.58, CGFloat(6 - i) * 0.012))
        context.strokePath()
    }
    context.restoreGState()
    var transform = CGAffineTransform(translationX: -2, y: -3)
    if let highlight = path.copy(using: &transform) {
        context.addPath(highlight); context.setLineWidth(32); context.setLineCap(.round); context.setLineJoin(.round)
        context.setStrokeColor(color(1, 0.86, 0.61, 0.26)); context.strokePath()
    }
}

// Spacious, winding corridors stay recognizable when the icon is reduced to a home-screen tile.
wall([CGPoint(x: 433, y: 178), CGPoint(x: 433, y: 404), CGPoint(x: 790, y: 404)])
wall([CGPoint(x: 186, y: 545), CGPoint(x: 625, y: 545), CGPoint(x: 625, y: 786)])
wall([CGPoint(x: 338, y: 853), CGPoint(x: 338, y: 722), CGPoint(x: 464, y: 722)])

func hole(center: CGPoint, radius: CGFloat, goal: Bool) {
    let outer = CGRect(x: center.x - radius - 12, y: center.y - radius - 12,
                       width: (radius + 12) * 2, height: (radius + 12) * 2)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 4, height: -8), blur: 12, color: color(0.1, 0.05, 0.01, 0.5))
    context.setFillColor(color(0.65, 0.43, 0.15)); context.fillEllipse(in: outer)
    context.restoreGState()
    context.saveGState()
    context.addEllipse(in: outer); context.clip()
    gradient([color(0.98, 0.80, 0.43), color(0.6, 0.37, 0.1), color(0.91, 0.66, 0.26)],
             locations: [0, 0.63, 1], from: CGPoint(x: center.x - radius, y: center.y - radius),
             to: CGPoint(x: center.x + radius, y: center.y + radius))
    context.restoreGState()
    let inner = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    context.saveGState()
    context.addEllipse(in: inner); context.clip()
    let pitColors = [color(0.13, 0.115, 0.075), color(0.012, 0.017, 0.018), color(0.025, 0.035, 0.031)]
    gradient(pitColors, locations: [0, 0.32, 1], from: CGPoint(x: center.x, y: center.y - radius),
             to: CGPoint(x: center.x, y: center.y + radius))
    context.restoreGState()
    if goal {
        context.addEllipse(in: inner.insetBy(dx: 8, dy: 8)); context.setLineWidth(5)
        context.setStrokeColor(color(0.22, 0.67, 0.43, 0.9)); context.strokePath()
        context.addEllipse(in: inner.insetBy(dx: 12, dy: 12)); context.setLineWidth(1.5)
        context.setStrokeColor(color(0.58, 0.91, 0.65, 0.45)); context.strokePath()
    }
}
hole(center: CGPoint(x: 795, y: 772), radius: 67, goal: true)
hole(center: CGPoint(x: 198, y: 774), radius: 44, goal: false)

func steelMarble(center: CGPoint, radius: CGFloat) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 16, height: -25), blur: 18, color: color(0.085, 0.07, 0.045, 0.62))
    context.setFillColor(color(0.20, 0.23, 0.26))
    context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    context.restoreGState()
    // Analytic sphere lighting gives the steel its ceiling reflection, dark horizon and warm floor bounce.
    let dimension = 300
    var pixels = [UInt8](repeating: 0, count: dimension * dimension * 4)
    let light = simd_normalize(SIMD3<Float>(-0.55, -0.72, 1.05))
    let half = simd_normalize(light + SIMD3<Float>(0, 0, 1))
    for y in 0..<dimension {
        for x in 0..<dimension {
            let xy = SIMD2<Float>((Float(x) + 0.5) / Float(dimension) * 2 - 1,
                                  (Float(y) + 0.5) / Float(dimension) * 2 - 1)
            let distance = simd_length(xy)
            guard distance <= 1 else { continue }
            let z = sqrt(max(0, 1 - simd_dot(xy, xy)))
            let n = SIMD3<Float>(xy.x, xy.y, z)
            let reflection = SIMD3<Float>(2 * z * xy.x, 2 * z * xy.y, 2 * z * z - 1)
            let t = max(0, min(1, (-reflection.y + 0.4) / 1.3))
            let sky = t * t * (3 - 2 * t)
            var steel = SIMD3<Float>(0.16, 0.20, 0.245) * (1 - sky) + SIMD3<Float>(0.77, 0.83, 0.88) * sky
            let horizon = exp(-pow((reflection.y - 0.15) * 6, 2))
            steel *= 1 - horizon * 0.43
            let ceiling = exp(-pow((reflection.x + 0.38 + reflection.y * 0.18) * 8, 2)) * max(0, min(1, (reflection.z + 0.2) / 0.8))
            steel += SIMD3<Float>(0.55, 0.58, 0.61) * ceiling
            steel += SIMD3<Float>(repeating: exp(-pow((reflection.x - 0.66) * 18, 2)) * 0.24)
            let fresnel = pow(1 - z, 3) * 0.5
            steel = steel * (1 - fresnel) + SIMD3<Float>(0.38, 0.42, 0.45) * fresnel
            steel += max(reflection.y, 0) * SIMD3<Float>(0.17, 0.105, 0.045)
            steel *= 0.78 + max(simd_dot(n, light), 0) * 0.22
            steel += SIMD3<Float>(repeating: pow(max(simd_dot(n, half), 0), 115) * 1.15)
            let alpha = min(1, max(0, (1 - distance) * Float(dimension) * 0.5))
            let offset = (y * dimension + x) * 4
            pixels[offset] = UInt8(min(255, max(0, steel.x * alpha * 255)))
            pixels[offset + 1] = UInt8(min(255, max(0, steel.y * alpha * 255)))
            pixels[offset + 2] = UInt8(min(255, max(0, steel.z * alpha * 255)))
            pixels[offset + 3] = UInt8(alpha * 255)
        }
    }
    let data = Data(pixels)
    let image = CGImage(width: dimension, height: dimension, bitsPerComponent: 8, bitsPerPixel: 32,
                        bytesPerRow: dimension * 4, space: colorSpace,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: CGDataProvider(data: data as CFData)!, decode: nil,
                        shouldInterpolate: true, intent: .defaultIntent)!
    context.saveGState()
    context.translateBy(x: center.x - radius, y: center.y + radius)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2))
    context.restoreGState()
}
steelMarble(center: CGPoint(x: 250, y: 260), radius: 83)

// Tiny brushed brass fasteners reinforce the crafted case without competing with the maze.
for point in [CGPoint(x: 100, y: 100), CGPoint(x: 924, y: 100), CGPoint(x: 100, y: 924), CGPoint(x: 924, y: 924)] {
    context.setFillColor(color(0.43, 0.29, 0.115)); context.fillEllipse(in: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
    context.setStrokeColor(color(0.97, 0.79, 0.46, 0.8)); context.setLineWidth(1.7)
    context.strokeEllipse(in: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
    context.move(to: CGPoint(x: point.x - 3, y: point.y + 1)); context.addLine(to: CGPoint(x: point.x + 3, y: point.y - 1))
    context.setStrokeColor(color(0.24, 0.15, 0.04)); context.setLineWidth(2); context.strokePath()
}

let output = asset.appendingPathComponent("icon.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not export the app icon") }
let contents = """
{
  "images" : [
    {
      "filename" : "icon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try contents.write(to: asset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print(output.path)
