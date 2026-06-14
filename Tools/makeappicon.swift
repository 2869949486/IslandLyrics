import AppKit
import CoreGraphics

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsctx
let cg = nsctx.cgContext
let rgb = CGColorSpaceCreateDeviceRGB()
func C(_ r: Double,_ g: Double,_ b: Double,_ a: Double = 1) -> CGColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor }

// 渐变 squircle（紫→粉，与设置头部图标同色系）
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let corner = size * 0.2237
cg.saveGState()
cg.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
cg.clip()
cg.drawLinearGradient(CGGradient(colorsSpace: rgb, colors: [C(0.43,0.36,1.0), C(1.0,0.36,0.66)] as CFArray, locations: [0,1])!,
    start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
// 顶部柔光
cg.drawRadialGradient(CGGradient(colorsSpace: rgb, colors: [C(1,1,1,0.22), C(1,1,1,0)] as CFArray, locations: [0,1])!,
    startCenter: CGPoint(x: size*0.32, y: size*0.82), startRadius: 0,
    endCenter: CGPoint(x: size*0.32, y: size*0.82), endRadius: size*0.62, options: [])
cg.restoreGState()

// 白色 music.note.list 字形，居中
let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
if let base = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil),
   let sym = base.withSymbolConfiguration(cfg) {
    let tinted = NSImage(size: sym.size)
    tinted.lockFocus()
    NSColor.white.set()
    let r = NSRect(origin: .zero, size: sym.size)
    sym.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()
    // 居中绘制 + 轻微投影
    let w = sym.size.width, h = sym.size.height
    let drawRect = NSRect(x: (size - w)/2, y: (size - h)/2, width: w, height: h)
    cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: C(0,0,0,0.28))
    tinted.draw(in: drawRect)
} else {
    print("symbol load failed")
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/appicon2_1024.png"))
print("wrote /tmp/appicon2_1024.png")
