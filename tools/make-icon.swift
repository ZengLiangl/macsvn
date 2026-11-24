// 生成 macsvn 的应用图标（1024×1024 主图），再由 sips/iconutil 导出 .icns。
// 用法：swift tools/make-icon.swift <输出路径.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// 图标主体按 macOS 规范留白：squircle 占约 824×824，居中。
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius: CGFloat = rect.width * 0.2237
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// 圆角矩形做裁剪，后续内容都限制在里面
ctx.saveGState()
path.addClip()

// 背景渐变：亮蓝 → 深靛蓝，斜向
let colors = [
    NSColor(srgbRed: 0.30, green: 0.56, blue: 1.00, alpha: 1).cgColor,
    NSColor(srgbRed: 0.09, green: 0.23, blue: 0.72, alpha: 1).cgColor
] as CFArray
if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
}

// 顶部一层柔和高光，避免大尺寸显得死板
let highlight = NSBezierPath(ovalIn: NSRect(
    x: rect.minX - rect.width * 0.15,
    y: rect.midY,
    width: rect.width * 1.3,
    height: rect.height * 0.9
))
NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16).setFill()
highlight.fill()

// 主体：白色粗体 S（SVN），下方三个提交节点，呼应版本历史
let glyph = "S" as NSString
let font = NSFont.systemFont(ofSize: rect.width * 0.62, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white
]
let textSize = glyph.size(withAttributes: attrs)
let textOrigin = NSPoint(
    x: rect.midX - textSize.width / 2,
    y: rect.midY - textSize.height / 2 + rect.height * 0.06
)
glyph.draw(at: textOrigin, withAttributes: attrs)

// 底部三点：代表本地改动 → 提交 → 版本库
let dotY = rect.minY + rect.height * 0.135
let dotR = rect.width * 0.032
let gap = rect.width * 0.105
for (index, alpha) in [0.55, 0.8, 1.0].enumerated() {
    let cx = rect.midX + CGFloat(index - 1) * gap
    let dot = NSBezierPath(ovalIn: NSRect(x: cx - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2))
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: CGFloat(alpha)).setFill()
    dot.fill()
}

ctx.restoreGState()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
try? png.write(to: out)
print("已生成 \(out.path)")
