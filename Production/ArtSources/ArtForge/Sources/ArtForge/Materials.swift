// Materials.swift — shared material recipes: polished gold / brass rims, glossy volumes,
// velvet fabric, wood, matte metal, glows and sparkles. All shading follows one key light
// from the screen's upper-left (Canvas.lightDir()).
import Foundation
import CoreGraphics

// MARK: - Metals

struct Metal {
    let stops: Stops          // along the light axis: 0 = lit side, 1 = shadow side
    let spec: RGBA
    let edge: RGBA            // darkest edge colour for outlines

    static let gold = Metal(stops: [
        (0.00, hex(0xFFF8D6)), (0.10, hex(0xFFE598)), (0.24, hex(0xFFD26E)), (0.40, hex(0xE3A553)),
        (0.55, hex(0xAF783B)), (0.68, hex(0x7C4C1F)), (0.80, hex(0xA87536)), (0.90, hex(0xD9A45A)), (1.00, hex(0x8A5A26)),
    ], spec: hex(0xFFFDF0), edge: hex(0x3A200B))

    static let brass = Metal(stops: [
        (0.00, hex(0xFFEBB8)), (0.14, hex(0xF2C77C)), (0.32, hex(0xCF9A4E)), (0.50, hex(0xA06A2E)),
        (0.66, hex(0x6E4418)), (0.80, hex(0x8E5E28)), (0.92, hex(0xB98545)), (1.00, hex(0x5E3812)),
    ], spec: hex(0xFFF4D8), edge: hex(0x2E1A08))

    static let bronze = Metal(stops: [
        (0.00, hex(0xF4C996)), (0.18, hex(0xC98A52)), (0.40, hex(0x94592C)), (0.60, hex(0x5E3317)),
        (0.78, hex(0x7C4A26)), (0.92, hex(0xA86A3C)), (1.00, hex(0x4A2610)),
    ], spec: hex(0xFFE2C0), edge: hex(0x22100A))

    static let darkPlumMetal = Metal(stops: [
        (0.00, hex(0x6A4A72)), (0.20, hex(0x46304E)), (0.45, hex(0x2C1D33)), (0.70, hex(0x1D1222)),
        (0.88, hex(0x2A1A30)), (1.00, hex(0x140A18)),
    ], spec: hex(0xD8C4E0), edge: hex(0x0A040C))
}

extension Canvas {
    /// Light-axis endpoints across a bounding box.
    func lightAxis(_ bb: CGRect, extent: CGFloat = 0.62) -> (CGPoint, CGPoint) {
        let L = lightDir()
        let r = max(bb.width, bb.height) * extent
        let c = P(bb.midX, bb.midY)
        return (c + P(L.dx, L.dy) * r, c - P(L.dx, L.dy) * r)
    }

    /// Fill an area with a metallic light-axis gradient.
    func metalFill(_ p: CGPath, _ m: Metal, bbox: CGRect? = nil, extent: CGFloat = 0.62) {
        let (a, b) = lightAxis(bbox ?? p.bbox, extent: extent)
        linear(p, m.stops, a, b)
    }

    /// Polished metal rim stroked along `p` (centred on the path) with a wire highlight.
    func metalRim(_ p: CGPath, width w: CGFloat, metal m: Metal = .gold, outline: CGFloat = 0, outlineColor: RGBA? = nil, bbox: CGRect? = nil) {
        let bb = bbox ?? p.bbox
        if outline > 0 { stroke(p, outlineColor ?? m.edge, w + 2 * outline) }
        let band = p.stroked(w)
        metalFill(band, m, bbox: bb)
        // rounded-wire look: dark inner core on the shadow half, bright specular line on the lit half
        let (a, b) = lightAxis(bb)
        linear(p.stroked(w * 0.34), [(0, m.spec.alpha(0.95)), (0.30, m.spec.alpha(0.55)), (0.52, m.spec.alpha(0)), (1, m.spec.alpha(0))], a, b)
        linear(band, [(0, RGBA.clear), (0.55, RGBA.clear), (1, m.edge.alpha(0.35))], a, b)
    }

    /// Bevelled metal plate: face gradient + lit upper-left inner edge + dark lower-right inner edge.
    func metalPlate(_ p: CGPath, _ m: Metal, bevel: CGFloat, outline: CGFloat = 0, soften: CGFloat = 0.6) {
        if outline > 0 { stroke(p, m.edge, outline * 2) }
        metalFill(p, m)
        let L = lightDir()
        innerShadow(p, dx: -L.dx * bevel, dy: -L.dy * bevel, blur: bevel * soften, color: m.spec.alpha(0.85))
        innerShadow(p, dx: L.dx * bevel, dy: L.dy * bevel, blur: bevel * soften, color: m.edge.alpha(0.75))
    }

    // MARK: glossy volumes

    /// Smooth glossy "3D cartoon" volume: radial key-light gradient, lower-right occlusion,
    /// coloured bounce light, soft + sharp specular.
    func glossy(_ p: CGPath, light: RGBA, base: RGBA, dark: RGBA, bounce: RGBA? = nil, spec: CGFloat = 0.85, specSize: CGFloat = 1, occlusion: CGFloat = 0.55, keyOffset: CGFloat = 0.38) {
        let bb = p.bbox
        let L = lightDir(); let l = P(L.dx, L.dy)
        let r = max(bb.width, bb.height) * 0.5
        let c = P(bb.midX, bb.midY)
        radial(p, [(0, light), (0.45, base), (1.0, dark)], center: c - l * (r * 0.25), radius: r * 1.35, focus: c + l * (r * keyOffset), focusRadius: 0)
        let s = min(bb.width, bb.height)
        innerShadow(p, dx: L.dx * s * 0.10, dy: L.dy * s * 0.10, blur: s * 0.10, color: dark.darker(0.35).alpha(occlusion))
        if let bounce {
            innerShadow(p, dx: L.dx * s * 0.05, dy: L.dy * s * 0.05, blur: s * 0.05, color: bounce)
        }
        if spec > 0 {
            let hc = c + l * (r * 0.52)
            blob(hc, rx: s * 0.20 * specSize, ry: s * 0.12 * specSize, color: RGBA.white.alpha(0.55 * spec), angle: atan2(-L.dx, L.dy), clip: p)
            blob(hc + l * (s * 0.02), rx: s * 0.07 * specSize, ry: s * 0.045 * specSize, color: RGBA.white.alpha(0.95 * spec), angle: atan2(-L.dx, L.dy), clip: p)
        }
    }

    // MARK: velvet

    /// Velvet: dark where the surface faces the viewer, bright sheen toward grazing edges.
    func velvet(_ p: CGPath, base: RGBA, sheen: RGBA, deep: RGBA, sheenWidth: CGFloat? = nil, texture: CGFloat = 0.10) {
        let bb = p.bbox
        let s = sheenWidth ?? min(bb.width, bb.height) * 0.16
        fill(p, base)
        let L = lightDir()
        radial(p, [(0, deep.alpha(0.55)), (1, deep.alpha(0))], center: P(bb.midX, bb.midY), radius: max(bb.width, bb.height) * 0.55)
        // sheen along all edges, stronger on the lit side
        innerGlow(p, dx: 0, dy: 0, blur: s, color: sheen.alpha(0.55))
        innerShadow(p, dx: -L.dx * s * 0.6, dy: -L.dy * s * 0.6, blur: s * 0.9, color: sheen.alpha(0.55))
        innerShadow(p, dx: L.dx * s * 0.5, dy: L.dy * s * 0.5, blur: s * 0.8, color: deep.alpha(0.6))
        if texture > 0 { fabricGrain(p, alpha: texture) }
    }

    /// Overlay fine fabric noise inside a path (noise pixels mapped ~1:1 to device pixels).
    func fabricGrain(_ p: CGPath?, alpha: CGFloat, seed: UInt64 = 7, fibre: CGFloat = 0.35) {
        let img = sharedNoise(fibre: fibre)
        save {
            if let p { ctx.addPath(p); ctx.clip() }
            let k = deviceLen(1)                       // device px per user unit
            let tile = CGFloat(img.width) / max(1e-6, k)
            let bb = p?.bbox ?? bounds
            var y = floor(bb.minY / tile) * tile
            while y < bb.maxY {
                var x = floor(bb.minX / tile) * tile
                while x < bb.maxX { drawImage(img, in: CGRect(x: x, y: y, width: tile, height: tile), alpha: alpha, blend: .overlay); x += tile }
                y += tile
            }
        }
    }

    // MARK: glow & sparkle
    func softGlow(_ p: CGPath, color: RGBA, radius: CGFloat, strength: Int = 1) {
        layer(blend: .screen) { for _ in 0..<strength { shadowOnly(p, blur: radius, color: color) } }
    }
    /// Four-point specular glint (optical, thin) — used sparingly.
    func glint(_ c: CGPoint, size s: CGFloat, color: RGBA = .white, angle: CGFloat = 0) {
        blob(c, rx: s * 0.55, ry: s * 0.55, color: color.alpha(0.45))
        let arms = buildPath { p in
            for k in 0..<4 {
                let a = angle + CGFloat(k) * .pi / 2
                let len = (k % 2 == 0) ? s : s * 0.62
                let tip = c + P(cos(a), sin(a)) * len
                let side = P(-sin(a), cos(a)) * (s * 0.075)
                p.move(to: c + side); p.addLine(to: tip); p.addLine(to: c - side); p.closeSubpath()
            }
        }
        fill(arms, color.alpha(0.95))
        fill(circlePath(c, s * 0.10), color)
    }

    /// Soft contact / drop shadow under an isolated object (kept subtle, never a rectangle).
    func dropShadow(_ p: CGPath, dx: CGFloat, dy: CGFloat, blur: CGFloat, alpha: CGFloat) {
        shadowOnly(p, dx: dx, dy: dy, blur: blur, color: hex(0x12040E, alpha))
    }
}

// MARK: - Shared noise tiles

private let noiseLock = NSLock()
private var noiseCache: [Int: CGImage] = [:]
func sharedNoise(fibre: CGFloat) -> CGImage {
    let key = Int(fibre * 1000)
    noiseLock.lock(); defer { noiseLock.unlock() }
    if let n = noiseCache[key] { return n }
    let img = noiseImage(width: 512, height: 512, seed: 99 + UInt64(key), amplitude: 0.55, fibre: fibre)
    noiseCache[key] = img
    return img
}

// MARK: - Wood

extension Canvas {
    /// Dark theatre-prop wood with procedural grain running along `grainAngle`.
    func wood(_ p: CGPath, base: RGBA = hex(0x4A2A1C), light: RGBA = hex(0x7A4A2E), dark: RGBA = hex(0x24120C), grainAngle: CGFloat = 0, seed: UInt64 = 3, grainScale: CGFloat = 1) {
        let bb = p.bbox
        metalFill(p, Metal(stops: [(0, light), (0.5, base), (1, dark)], spec: light, edge: dark))
        clip(p) {
            var rng = RNG(seed)
            let c = P(bb.midX, bb.midY)
            let R = max(bb.width, bb.height) * 0.75
            transform(CGAffineTransform(translationX: c.x, y: c.y).rotated(by: grainAngle)) {
                let lines = Int(R * 2 / (6 * grainScale))
                for i in 0..<lines {
                    let y0 = -R + CGFloat(i) * 6 * grainScale + rng.range(-2, 2)
                    var pts: [CGPoint] = []
                    let amp = rng.range(0.5, 3.5) * grainScale
                    let ph = rng.range(0, 6.28)
                    let fr = rng.range(0.004, 0.012) / grainScale
                    var x = -R
                    while x <= R { pts.append(P(x, y0 + sin(x * fr * 6.28 + ph) * amp * 2)); x += 12 }
                    let col = rng.unit() < 0.5 ? dark.alpha(rng.range(0.15, 0.45)) : light.alpha(rng.range(0.08, 0.22))
                    stroke(smoothPath(pts, closed: false), col, rng.range(0.6, 2.2) * grainScale)
                }
                // a couple of knots
                for _ in 0..<2 {
                    let kc = P(rng.range(-R * 0.5, R * 0.5), rng.range(-R * 0.5, R * 0.5))
                    for k in 0..<5 {
                        stroke(ellipsePath(kc, CGFloat(k + 1) * 5 * grainScale, CGFloat(k + 1) * 2.2 * grainScale), dark.alpha(0.25), 1.2 * grainScale)
                    }
                }
            }
        }
        fabricGrain(p, alpha: 0.12, fibre: 0.1)
    }
}
