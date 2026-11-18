// 生成 HyperGO 的 App 图标（1024×1024 PNG）
// 用法：swift tools/make_icon.swift <输出路径>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// 翻转为左上角原点，方便按设计稿坐标绘制
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// 1. 背景：左上深蓝 → 右下青色
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0x2F4BFF), rgb(0x1E8BFF), rgb(0x14D1D9)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: size, y: size), options: [])

// 柔和高光
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 260, y: 200), startRadius: 0,
                       endCenter: CGPoint(x: 260, y: 200), endRadius: 620, options: [])

// 关键点
let start = CGPoint(x: 282, y: 770)
let mid = CGPoint(x: 470, y: 560)
let pinTip = CGPoint(x: 700, y: 560)   // 大头针尖端（目的地）

// 2. 路线：白色虚线曲线，起点 → 途经点 → 目的地
let route = CGMutablePath()
route.move(to: start)
route.addCurve(to: mid, control1: CGPoint(x: 282, y: 640), control2: CGPoint(x: 360, y: 560))
route.addCurve(to: pinTip, control1: CGPoint(x: 580, y: 560), control2: CGPoint(x: 640, y: 600))

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: rgb(0x0A1A6B, 0.30))
ctx.addPath(route)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.95))
ctx.setLineWidth(34)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [2, 64])
ctx.strokePath()
ctx.restoreGState()

// 3. 起点：白色圆环
func ring(_ c: CGPoint, outer: CGFloat, inner: CGFloat, fill: CGColor) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: rgb(0x0A1A6B, 0.35))
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
    ctx.restoreGState()
    ctx.setFillColor(fill)
    ctx.fillEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
}
ring(start, outer: 62, inner: 30, fill: rgb(0x2453FF))

// 途经点：小白点
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: rgb(0x0A1A6B, 0.30))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillEllipse(in: CGRect(x: mid.x - 36, y: mid.y - 36, width: 72, height: 72))
ctx.restoreGState()

// 4. 目的地：白色大头针（水滴形）
let headC = CGPoint(x: pinTip.x, y: pinTip.y - 250)  // 圆头中心
let r: CGFloat = 150
let pin = CGMutablePath()
// 从尖端出发，两侧切线连到圆头
let angle = asin(r / (pinTip.y - headC.y))           // 切线角
let leftT = CGPoint(x: headC.x - r * cos(angle), y: headC.y + r * sin(angle))
pin.move(to: pinTip)
pin.addQuadCurve(to: leftT, control: CGPoint(x: pinTip.x - 40, y: pinTip.y - 70))
pin.addArc(center: headC, radius: r, startAngle: .pi - angle, endAngle: angle, clockwise: false)
pin.addQuadCurve(to: pinTip, control: CGPoint(x: pinTip.x + 40, y: pinTip.y - 70))
pin.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x0A1A6B, 0.40))
ctx.addPath(pin)
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

// 圆头中心的彩色圆点
let dotR: CGFloat = 62
let dot = CGGradient(colorsSpace: cs, colors: [rgb(0x2F4BFF), rgb(0x14C3D9)] as CFArray, locations: [0, 1])!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: headC.x - dotR, y: headC.y - dotR, width: dotR * 2, height: dotR * 2))
ctx.clip()
ctx.drawLinearGradient(dot, start: CGPoint(x: headC.x - dotR, y: headC.y - dotR),
                       end: CGPoint(x: headC.x + dotR, y: headC.y + dotR), options: [])
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
