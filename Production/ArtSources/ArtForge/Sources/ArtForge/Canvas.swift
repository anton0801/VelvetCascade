// Canvas.swift — bitmap canvas, colour type, gradient/shadow/blur helpers, PNG I/O.
// Coordinate convention everywhere in ArtForge: design units, origin top-left, y grows DOWN.
import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let sRGBSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let graySpace = CGColorSpaceCreateDeviceGray()

// MARK: - Colour

struct RGBA {
    var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(hex v: UInt32, a: CGFloat = 1) {
        r = CGFloat((v >> 16) & 0xFF) / 255; g = CGFloat((v >> 8) & 0xFF) / 255; b = CGFloat(v & 0xFF) / 255; self.a = a
    }
    var cg: CGColor { CGColor(colorSpace: sRGBSpace, components: [r, g, b, a])! }
    func mix(_ o: RGBA, _ t: CGFloat) -> RGBA {
        RGBA(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t, a + (o.a - a) * t)
    }
    func lighter(_ t: CGFloat) -> RGBA { let w = RGBA(1, 1, 1, a); return mix(w, t) }
    func darker(_ t: CGFloat) -> RGBA { RGBA(r * (1 - t), g * (1 - t), b * (1 - t), a) }
    func alpha(_ na: CGFloat) -> RGBA { RGBA(r, g, b, na) }
    func mul(_ o: RGBA) -> RGBA { RGBA(r * o.r, g * o.g, b * o.b, a) }
    static let white = RGBA(1, 1, 1, 1)
    static let black = RGBA(0, 0, 0, 1)
    static let clear = RGBA(0, 0, 0, 0)
}
func hex(_ v: UInt32, _ a: CGFloat = 1) -> RGBA { RGBA(hex: v, a: a) }

/// Velvet Cascade master palette (docs/spec/MASTER_PROMPT_RU.md, "Color palette").
enum Pal {
    static let deepVelvet = hex(0x160C1D)
    static let plumStage = hex(0x27142E)
    static let panel = hex(0x351B36)
    static let ruby = hex(0xB52643)
    static let crimson = hex(0xE04459)
    static let antiqueGold = hex(0xAF783B)
    static let spotGold = hex(0xFFD26E)
    static let ivory = hex(0xFFF3DC)
    static let rose = hex(0xCDB5CB)
    static let ink = hex(0x2D1930)
    static let sapphire = hex(0x369FEE)
    static let emerald = hex(0x38BA8A)
    static let amethyst = hex(0xA36BE8)
    // derived working colours
    static let plum = hex(0x4A2158)
    static let plumLight = hex(0x7B3F8E)
    static let plumDark = hex(0x241030)
    static let outline = hex(0x1A0914)
}

typealias Stops = [(CGFloat, RGBA)]

func makeGradient(_ stops: Stops) -> CGGradient {
    let cols = stops.map { $0.1.cg } as CFArray
    var locs = stops.map { $0.0 }
    return CGGradient(colorsSpace: sRGBSpace, colors: cols, locations: &locs)!
}

// MARK: - Deterministic RNG

struct RNG {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    mutating func unit() -> CGFloat { CGFloat(next() % 1_000_000) / 1_000_000 }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * unit() }
}

// MARK: - Canvas

final class Canvas {
    let ctx: CGContext
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: CGFloat
    let opaque: Bool
    let width: CGFloat
    let height: CGFloat

    init(width: CGFloat, height: CGFloat, scale: CGFloat = 1, opaque: Bool = false) {
        self.width = width; self.height = height; self.scale = scale; self.opaque = opaque
        pixelWidth = Int((width * scale).rounded()); pixelHeight = Int((height * scale).rounded())
        let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        ctx = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGBSpace, bitmapInfo: info)!
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
    }

    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
    func makeImage() -> CGImage { ctx.makeImage()! }

    // MARK: state helpers
    func save(_ body: () -> Void) { ctx.saveGState(); body(); ctx.restoreGState() }
    func clip(_ p: CGPath, evenOdd: Bool = false, _ body: () -> Void) {
        ctx.saveGState(); ctx.addPath(p); ctx.clip(using: evenOdd ? .evenOdd : .winding); body(); ctx.restoreGState()
    }
    func layer(alpha: CGFloat = 1, blend: CGBlendMode = .normal, _ body: () -> Void) {
        ctx.saveGState(); ctx.setAlpha(alpha); ctx.setBlendMode(blend)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil); body(); ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
    func transform(_ t: CGAffineTransform, _ body: () -> Void) { ctx.saveGState(); ctx.concatenate(t); body(); ctx.restoreGState() }

    /// Unit vector (in current user space) pointing toward the scene key light (screen upper-left).
    func lightDir() -> CGVector {
        let m = ctx.ctm
        // device space is y-up: upper-left on screen = (-1, +1)
        let inv = m.inverted()
        let v = CGPoint(x: -0.62, y: 0.78)
        let lx = v.x * inv.a + v.y * inv.c
        let ly = v.x * inv.b + v.y * inv.d
        let l = max(1e-6, sqrt(lx * lx + ly * ly))
        return CGVector(dx: lx / l, dy: ly / l)
    }
    /// Converts a user-space length to device pixels under the current CTM.
    func deviceLen(_ v: CGFloat) -> CGFloat {
        let m = ctx.ctm; return v * sqrt(abs(m.a * m.d - m.b * m.c))
    }
    func deviceSize(_ dx: CGFloat, _ dy: CGFloat) -> CGSize {
        let m = ctx.ctm; return CGSize(width: dx * m.a + dy * m.c, height: dx * m.b + dy * m.d)
    }

    // MARK: primitives
    func fill(_ p: CGPath, _ c: RGBA, evenOdd: Bool = false) {
        ctx.addPath(p); ctx.setFillColor(c.cg); ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
    }
    func stroke(_ p: CGPath, _ c: RGBA, _ w: CGFloat, cap: CGLineCap = .round, join: CGLineJoin = .round) {
        ctx.saveGState(); ctx.addPath(p); ctx.setStrokeColor(c.cg); ctx.setLineWidth(w)
        ctx.setLineCap(cap); ctx.setLineJoin(join); ctx.strokePath(); ctx.restoreGState()
    }
    func linear(_ p: CGPath?, _ stops: Stops, _ from: CGPoint, _ to: CGPoint, evenOdd: Bool = false) {
        ctx.saveGState()
        if let p { ctx.addPath(p); ctx.clip(using: evenOdd ? .evenOdd : .winding) }
        ctx.drawLinearGradient(makeGradient(stops), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    func radial(_ p: CGPath?, _ stops: Stops, center: CGPoint, radius: CGFloat, focus: CGPoint? = nil, focusRadius: CGFloat = 0, extend: Bool = true) {
        ctx.saveGState()
        if let p { ctx.addPath(p); ctx.clip() }
        ctx.drawRadialGradient(makeGradient(stops), startCenter: focus ?? center, startRadius: focusRadius,
                               endCenter: center, endRadius: radius,
                               options: extend ? [.drawsBeforeStartLocation, .drawsAfterEndLocation] : [.drawsBeforeStartLocation])
        ctx.restoreGState()
    }
    /// Elliptical radial gradient (rx, ry) optionally rotated.
    func radialEllipse(_ p: CGPath?, _ stops: Stops, center: CGPoint, rx: CGFloat, ry: CGFloat, angle: CGFloat = 0, extend: Bool = true) {
        ctx.saveGState()
        if let p { ctx.addPath(p); ctx.clip() }
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        ctx.scaleBy(x: 1, y: ry / rx)
        ctx.drawRadialGradient(makeGradient(stops), startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: rx,
                               options: extend ? [.drawsBeforeStartLocation, .drawsAfterEndLocation] : [.drawsBeforeStartLocation])
        ctx.restoreGState()
    }
    /// Soft blob: elliptical radial falloff of one colour.
    func blob(_ c: CGPoint, rx: CGFloat, ry: CGFloat, color: RGBA, angle: CGFloat = 0, falloff: CGFloat = 1, clip: CGPath? = nil) {
        radialEllipse(clip, [(0, color), (0.5 * falloff, color.alpha(color.a * 0.55)), (1, color.alpha(0))],
                      center: c, rx: rx, ry: ry, angle: angle, extend: false)
    }

    // MARK: shadows & glows
    func withShadow(dx: CGFloat = 0, dy: CGFloat = 0, blur: CGFloat, color: RGBA, _ body: () -> Void) {
        ctx.saveGState()
        ctx.setShadow(offset: deviceSize(dx, dy), blur: deviceLen(blur), color: color.cg)
        body()
        ctx.restoreGState()
    }
    /// Draws only the blurred shadow of `p`: the shape itself is clipped out, its shadow is kept.
    /// (An earlier "throw the shape off-canvas" variant produced truncated shadows for large shapes.)
    /// Callers draw the object on top afterwards, so the part of the shadow under the shape is never needed.
    func shadowOnly(_ p: CGPath, dx: CGFloat = 0, dy: CGFloat = 0, blur: CGFloat, color: RGBA, evenOdd: Bool = false) {
        ctx.saveGState()
        let clipBox = ctx.boundingBoxOfClipPath.insetBy(dx: -abs(dx) - blur * 4 - 20, dy: -abs(dy) - blur * 4 - 20)
        let outside = CGMutablePath()
        outside.addRect(clipBox.union(p.boundingBoxOfPath.insetBy(dx: -blur * 4 - 20, dy: -blur * 4 - 20)))
        outside.addPath(p)
        ctx.addPath(outside); ctx.clip(using: .evenOdd)
        ctx.setShadow(offset: deviceSize(dx, dy), blur: deviceLen(blur), color: color.cg)
        ctx.addPath(p); ctx.setFillColor(color.alpha(1).cg); ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
        ctx.restoreGState()
    }
    func glow(_ p: CGPath, color: RGBA, blur: CGFloat, passes: Int = 1) {
        for _ in 0..<passes { shadowOnly(p, blur: blur, color: color) }
    }
    /// Inner shadow / inner light band: offset (dx,dy) moves the "hole"; the band appears on the opposite side.
    func innerShadow(_ p: CGPath, dx: CGFloat, dy: CGFloat, blur: CGFloat, color: RGBA) {
        ctx.saveGState()
        ctx.addPath(p); ctx.clip()
        let bb = p.boundingBoxOfPath.insetBy(dx: -abs(dx) - blur * 3 - 10, dy: -abs(dy) - blur * 3 - 10)
        let m = CGMutablePath(); m.addRect(bb)
        m.addPath(p, transform: CGAffineTransform(translationX: dx, y: dy))
        ctx.setShadow(offset: .zero, blur: deviceLen(blur), color: color.cg)
        ctx.addPath(m); ctx.setFillColor(color.cg); ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }
    /// Soft edge light: like innerShadow, but draws only the blurred part (no solid band).
    func innerGlow(_ p: CGPath, dx: CGFloat, dy: CGFloat, blur: CGFloat, color: RGBA) {
        ctx.saveGState()
        ctx.addPath(p); ctx.clip()
        let bb = p.boundingBoxOfPath.insetBy(dx: -abs(dx) - blur * 3 - 10, dy: -abs(dy) - blur * 3 - 10)
        let m = CGMutablePath(); m.addRect(bb)
        m.addPath(p, transform: CGAffineTransform(translationX: dx, y: dy))
        shadowOnly(m, blur: blur, color: color, evenOdd: true)
        ctx.restoreGState()
    }

    // MARK: offscreen blur layer (CoreImage)
    /// Render `body` into an offscreen canvas with the same CTM, gaussian-blur it and composite.
    func blurred(radius: CGFloat, alpha: CGFloat = 1, blend: CGBlendMode = .normal, _ body: (Canvas) -> Void) {
        let off = Canvas(width: width, height: height, scale: scale, opaque: false)
        off.ctx.concatenate(off.ctx.ctm.inverted())
        off.ctx.concatenate(ctx.ctm)
        body(off)
        let img = off.makeImage()
        let blurredImg = gaussianBlur(img, radius: deviceLen(radius))
        ctx.saveGState()
        ctx.concatenate(ctx.ctm.inverted())
        ctx.setAlpha(alpha); ctx.setBlendMode(blend)
        ctx.draw(blurredImg, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.restoreGState()
    }
    /// Draw a pixel image covering the whole canvas (image pixels == canvas pixels).
    func drawFull(_ img: CGImage, alpha: CGFloat = 1, blend: CGBlendMode = .normal) {
        ctx.saveGState()
        ctx.concatenate(ctx.ctm.inverted())
        ctx.setAlpha(alpha); ctx.setBlendMode(blend)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.restoreGState()
    }
    /// Draw another image into a design-space rect (handles the flipped CTM).
    func drawImage(_ img: CGImage, in r: CGRect, alpha: CGFloat = 1, blend: CGBlendMode = .normal) {
        ctx.saveGState()
        ctx.setAlpha(alpha); ctx.setBlendMode(blend)
        ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
        ctx.restoreGState()
    }
}

// MARK: - CoreImage

let ciContext: CIContext = {
    CIContext(options: [.workingColorSpace: sRGBSpace, .outputColorSpace: sRGBSpace, .cacheIntermediates: false])
}()

private let ciLock = NSLock()
func gaussianBlur(_ img: CGImage, radius: CGFloat) -> CGImage {
    // CoreImage renders are serialised: concurrent GPU renders produced a rare column artifact.
    ciLock.lock(); defer { ciLock.unlock() }
    let ci = CIImage(cgImage: img)
    let ext = ci.extent
    let f = CIFilter(name: "CIGaussianBlur")!
    f.setValue(radius, forKey: kCIInputRadiusKey)
    // transparent padding (not clamp) so alpha layers fade out correctly at the canvas edge
    let padded = ci.composited(over: CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: ext.insetBy(dx: -radius * 3, dy: -radius * 3)))
    f.setValue(padded, forKey: kCIInputImageKey)
    let out = f.outputImage!.cropped(to: ext)
    return ciContext.createCGImage(out, from: ext, format: .RGBA8, colorSpace: sRGBSpace)!
}

// MARK: - Noise

/// Grayscale noise image (mid-grey 0.5 ± amplitude) with optional vertical fibre streaks.
func noiseImage(width: Int, height: Int, seed: UInt64, amplitude: CGFloat = 0.5, fibre: CGFloat = 0, fibreAngle: CGFloat = 0) -> CGImage {
    var rng = RNG(seed)
    var buf = [UInt8](repeating: 128, count: width * height)
    // per-column fibre offsets
    var col = [CGFloat](repeating: 0, count: width + height)
    var v: CGFloat = 0
    for i in 0..<col.count { v = v * 0.55 + (rng.unit() - 0.5) * 0.9; col[i] = v }
    let slope = tan(fibreAngle)
    for y in 0..<height {
        for x in 0..<width {
            let n = rng.unit() - 0.5
            var val = n * amplitude
            if fibre > 0 {
                let ci = Int(CGFloat(x) + CGFloat(y) * slope) % col.count
                val += col[ci < 0 ? ci + col.count : ci] * fibre
            }
            let g = max(0, min(255, Int((0.5 + val) * 255)))
            buf[y * width + x] = UInt8(g)
        }
    }
    let data = CFDataCreate(nil, buf, buf.count)!
    let prov = CGDataProvider(data: data)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                   space: graySpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                   provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

// MARK: - PNG I/O & resampling

func writePNG(_ img: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot create PNG destination \(url.path)")
    }
    CGImageDestinationAddImage(dest, img, nil)
    if !CGImageDestinationFinalize(dest) { fatalError("PNG write failed \(url.path)") }
}

/// High-quality downscale (uniform; callers guarantee identical aspect ratio).
func resample(_ img: CGImage, width: Int, height: Int, opaque: Bool) -> CGImage {
    let srcAR = CGFloat(img.width) / CGFloat(img.height)
    let dstAR = CGFloat(width) / CGFloat(height)
    precondition(abs(srcAR - dstAR) < 0.002, "non-uniform resample requested")
    var cur = img
    // step down by halves for quality, then final pass
    while cur.width / 2 >= width && cur.width / 2 > 0 && cur.width != width {
        cur = rawResize(cur, cur.width / 2, cur.height / 2, opaque: opaque)
    }
    if cur.width != width || cur.height != height { cur = rawResize(cur, width, height, opaque: opaque) }
    return cur
}

private func rawResize(_ img: CGImage, _ w: Int, _ h: Int, opaque: Bool) -> CGImage {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGBSpace, bitmapInfo: info)!
    c.interpolationQuality = .high
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return c.makeImage()!
}
