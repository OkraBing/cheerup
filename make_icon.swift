import Cocoa
// 生成启动图标：米白底、黑线拉拉队员、红色花球。用法：swift make_icon.swift 输出目录
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let k = CGFloat(px) / 1024
    ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: k, y: -k)          // 之后都按 1024 的坐标画，y 向下
    let paper = NSColor(red: 0.949, green: 0.941, blue: 0.922, alpha: 1)
    // 两个花球一红一绿：涨和跌的颜色各拿一个
    let red = NSColor(red: 0.90, green: 0.45, blue: 0.42, alpha: 1), green = NSColor(red: 0.42, green: 0.74, blue: 0.53, alpha: 1)
    // 底：macOS 图标的圆角方形，四周留边
    paper.setFill()
    NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186).fill()
    let white = NSColor(white: 0.97, alpha: 1), edge = NSColor(white: 0.20, alpha: 1), dark = NSColor(white: 0.10, alpha: 1)
    let w: CGFloat = 34, o: CGFloat = 13          // 白线的粗细、外面一圈描边的宽度
    let cx: CGFloat = 512, headY: CGFloat = 394, headR: CGFloat = 122
    let neck = headY + headR, hip: CGFloat = 634, foot: CGFloat = 794        // 和程序里一致：腿比最早那版短一点
    // 先把每个部件的路径准备好，再分两遍画：第一遍全部描深色的边，第二遍全部画本体，这样重叠处不会露出接缝
    var limbs: [NSBezierPath] = []
    func path(_ pts: [NSPoint]) -> NSBezierPath { let p = NSBezierPath(); p.move(to: pts[0]); for q in pts.dropFirst() { p.line(to: q) }; return p }
    limbs.append(path([NSPoint(x: cx, y: neck - 10), NSPoint(x: cx, y: hip)]))                              // 躯干
    for s in [-1.0, 1.0] as [CGFloat] {                                                                 // 腿，脚尖朝前
        let ax = cx + s * 64
        limbs.append(path([NSPoint(x: cx, y: hip), NSPoint(x: ax, y: foot), NSPoint(x: ax + s * 22, y: foot + 30)]))
    }
    var hands: [NSPoint] = []
    for s in [-1.0, 1.0] as [CGFloat] {                                                                 // 手臂高举成 V，手肘微微下坠
        let sh = NSPoint(x: cx + s * 16, y: neck + 34), h = NSPoint(x: cx + s * 232, y: headY - 14)      // 手臂也短一点
        let el = NSPoint(x: (sh.x + h.x) / 2 + s * 26, y: (sh.y + h.y) / 2 + 34)          // 手肘朝外、略朝下
        let p = NSBezierPath(); p.move(to: sh); p.curve(to: h, controlPoint1: el, controlPoint2: el)
        limbs.append(p); hands.append(h)
    }
    var poms: [NSBezierPath] = []
    for h in hands { for i in 0..<3 {
        let a = CGFloat(i) * .pi / 3 + 0.26
        poms.append(path([NSPoint(x: h.x - cos(a) * 62, y: h.y - sin(a) * 62), NSPoint(x: h.x + cos(a) * 62, y: h.y + sin(a) * 62)]))
    } }
    let ground = path([NSPoint(x: cx - 120, y: foot + 66), NSPoint(x: cx + 120, y: foot + 66)])
    let head = NSBezierPath(ovalIn: NSRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2))
    func stroke(_ p: NSBezierPath, _ width: CGFloat, _ c: NSColor) { p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round; c.setStroke(); p.stroke() }
    // 第一遍：描边
    stroke(ground, 26 + o * 2, edge)
    for l in limbs { stroke(l, w + o * 2, edge) }
    for q in poms { stroke(q, 36 + o * 2, edge) }
    stroke(head, o * 2, edge); edge.setFill(); head.fill()
    // 第二遍：本体
    stroke(ground, 26, NSColor(white: 0.62, alpha: 1))
    for l in limbs { stroke(l, w, white) }
    white.setFill(); head.fill()
    for (i, q) in poms.enumerated() { stroke(q, 36, i < 3 ? red : green) }
    // 脸：平眉毛下面挂半颗豆豆眼，一字嘴
    dark.setFill()
    for s in [-1.0, 1.0] as [CGFloat] {
        let ex = cx + s * 50, ey = headY - 36
        stroke(path([NSPoint(x: ex - 30, y: ey), NSPoint(x: ex + 30, y: ey)]), 13, dark)
        let e = NSBezierPath(); e.move(to: NSPoint(x: ex - 23, y: ey))
        e.curve(to: NSPoint(x: ex + 23, y: ey), controlPoint1: NSPoint(x: ex - 25, y: ey + 46), controlPoint2: NSPoint(x: ex + 25, y: ey + 46))
        e.close(); e.fill()
    }
    stroke(path([NSPoint(x: cx - 22, y: headY + 58), NSPoint(x: cx + 22, y: headY + 58)]), 18, dark)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let set = out + "/CheerUp.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: "\(set)/icon_\(name).png"))
}
try! draw(1024).write(to: URL(fileURLWithPath: out + "/icon_1024.png"))
