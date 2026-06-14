import AppKit
import CoreGraphics

func ctx(_ w: Int, _ h: Int) -> (NSBitmapImageRep, CGContext) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let c = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = c
    return (rep, c.cgContext)
}
func save(_ rep: NSBitmapImageRep, _ path: String) {
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote", path)
}
func C(_ r: Double,_ g: Double,_ b: Double,_ a: Double = 1) -> CGColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor }
let rgb = CGColorSpaceCreateDeviceRGB()

// ---- 菜单栏模板图标：灵动岛胶囊轮廓 + 专辑点 + 频谱（黑色模板，系统自动着色）----
do {
    let W = 88, H = 44   // 2x of 44x22pt
    let (rep, cg) = ctx(W, H)
    let pill = CGRect(x: 5, y: 9, width: 78, height: 26)
    // 胶囊描边
    let path = CGPath(roundedRect: pill, cornerWidth: 13, cornerHeight: 13, transform: nil)
    cg.addPath(path); cg.setStrokeColor(C(0,0,0)); cg.setLineWidth(4.5); cg.strokePath()
    // 左：专辑点
    cg.setFillColor(C(0,0,0))
    cg.fillEllipse(in: CGRect(x: 16, y: 16, width: 12, height: 12))
    // 右：频谱 3 条
    let hs: [CGFloat] = [9, 16, 11]
    for (i, hh) in hs.enumerated() {
        let x = CGFloat(48 + i*9)
        cg.addPath(CGPath(roundedRect: CGRect(x: x, y: 22 - hh/2, width: 5, height: hh), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
        cg.fillPath()
    }
    save(rep, "/tmp/menubar.png")
}

// ---- 设置预览用的「真实」示例专辑封面（256，抽象渐变+形状）----
do {
    let S = 256
    let (rep, cg) = ctx(S, S)
    cg.saveGState()
    cg.addRect(CGRect(x:0,y:0,width:S,height:S)); cg.clip()
    cg.drawLinearGradient(CGGradient(colorsSpace: rgb, colors: [C(0.15,0.18,0.42), C(0.85,0.32,0.45)] as CFArray, locations:[0,1])!,
        start: CGPoint(x:0,y:S), end: CGPoint(x:S,y:0), options: [])
    // 抽象同心圆波纹
    cg.setBlendMode(.softLight)
    for r in stride(from: 40, through: 220, by: 26) {
        cg.setStrokeColor(C(1,1,1,0.5)); cg.setLineWidth(6)
        cg.strokeEllipse(in: CGRect(x: Double(S)*0.62 - Double(r)/2, y: Double(S)*0.34 - Double(r)/2, width: Double(r), height: Double(r)))
    }
    cg.setBlendMode(.normal)
    // 高光
    cg.drawRadialGradient(CGGradient(colorsSpace: rgb, colors: [C(1,1,1,0.35), C(1,1,1,0)] as CFArray, locations:[0,1])!,
        startCenter: CGPoint(x: Double(S)*0.3, y: Double(S)*0.78), startRadius: 0,
        endCenter: CGPoint(x: Double(S)*0.3, y: Double(S)*0.78), endRadius: Double(S)*0.5, options: [])
    cg.restoreGState()
    save(rep, "/tmp/sample_cover.png")
}
