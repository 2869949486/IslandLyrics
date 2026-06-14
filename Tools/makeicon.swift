import AppKit
import CoreGraphics

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext
let rgb = CGColorSpaceCreateDeviceRGB()
func C(_ r: Double,_ g: Double,_ b: Double,_ a: Double = 1) -> CGColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor
}

// 背景 squircle + 对角渐变（紫→粉，音乐感）
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let corner = size * 0.2237
cg.saveGState()
cg.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
cg.clip()
cg.drawLinearGradient(CGGradient(colorsSpace: rgb,
    colors: [C(0.43,0.36,1.0), C(1.0,0.36,0.66)] as CFArray, locations: [0,1])!,
    start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
// 顶部柔光
cg.drawRadialGradient(CGGradient(colorsSpace: rgb,
    colors: [C(1,1,1,0.25), C(1,1,1,0)] as CFArray, locations: [0,1])!,
    startCenter: CGPoint(x: size*0.32, y: size*0.82), startRadius: 0,
    endCenter: CGPoint(x: size*0.32, y: size*0.82), endRadius: size*0.6, options: [])
cg.restoreGState()

// 黑色灵动岛胶囊（带投影）
let pillW = size*0.66, pillH = size*0.30
let pillRect = CGRect(x: (size-pillW)/2, y: (size-pillH)/2, width: pillW, height: pillH)
let pillPath = CGPath(roundedRect: pillRect, cornerWidth: pillH/2, cornerHeight: pillH/2, transform: nil)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 46, color: C(0,0,0,0.55))
cg.addPath(pillPath); cg.setFillColor(C(0.04,0.04,0.06)); cg.fillPath()
cg.restoreGState()
// 胶囊上缘高光
cg.saveGState(); cg.addPath(pillPath); cg.clip()
cg.drawLinearGradient(CGGradient(colorsSpace: rgb, colors: [C(1,1,1,0.10), C(1,1,1,0)] as CFArray, locations: [0,1])!,
    start: CGPoint(x: pillRect.midX, y: pillRect.maxY), end: CGPoint(x: pillRect.midX, y: pillRect.midY), options: [])
cg.restoreGState()

// 左：专辑圆点（白→灰渐变）
let dotD = pillH*0.52
let dotRect = CGRect(x: pillRect.minX + pillH*0.30, y: pillRect.midY - dotD/2, width: dotD, height: dotD)
cg.saveGState(); cg.addEllipse(in: dotRect); cg.clip()
cg.drawLinearGradient(CGGradient(colorsSpace: rgb, colors: [C(1,1,1), C(0.75,0.78,0.92)] as CFArray, locations: [0,1])!,
    start: CGPoint(x: dotRect.minX, y: dotRect.maxY), end: CGPoint(x: dotRect.maxX, y: dotRect.minY), options: [])
cg.restoreGState()
// 圆点中心小孔（黑胶感）
let holeD = dotD*0.16
cg.setFillColor(C(0.04,0.04,0.06))
cg.fillEllipse(in: CGRect(x: dotRect.midX-holeD/2, y: dotRect.midY-holeD/2, width: holeD, height: holeD))

// 右：频谱 4 条（青→品红渐变，圆角）
let barCount = 4
let barW = pillH*0.13
let gap = barW*0.75
let barsTotalW = CGFloat(barCount)*barW + CGFloat(barCount-1)*gap
let barsStartX = pillRect.maxX - pillH*0.34 - barsTotalW
let heights: [CGFloat] = [0.34, 0.66, 0.46, 0.80]
for i in 0..<barCount {
    let h = pillH*heights[i]
    let x = barsStartX + CGFloat(i)*(barW+gap)
    let y = pillRect.midY - h/2
    let bar = CGPath(roundedRect: CGRect(x: x, y: y, width: barW, height: h), cornerWidth: barW/2, cornerHeight: barW/2, transform: nil)
    cg.saveGState(); cg.addPath(bar); cg.clip()
    cg.drawLinearGradient(CGGradient(colorsSpace: rgb, colors: [C(0.0,0.90,1.0), C(1.0,0.30,0.85)] as CFArray, locations: [0,1])!,
        start: CGPoint(x: x, y: y+h), end: CGPoint(x: x, y: y), options: [])
    cg.restoreGState()
}

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "/tmp/appicon_1024.png"))
print("wrote /tmp/appicon_1024.png")
