// StageKit.swift — reusable theatre scenery for backgrounds: velvet drapes with procedural folds,
// scalloped valances with gold fringe, brass stage-ring fragments, light cones with dust,
// vignettes, floors, chains, gears, bulbs. All pieces respect the upper-left key light.
import Foundation
import CoreGraphics

struct DrapeColors {
    var deep: RGBA, base: RGBA, sheen: RGBA
    static let ruby = DrapeColors(deep: hex(0x3A0714), base: hex(0x8E1A33), sheen: hex(0xE0506A))
    static let crimson = DrapeColors(deep: hex(0x42081A), base: hex(0xA51F3E), sheen: hex(0xF06078))
    static let burgundy = DrapeColors(deep: hex(0x2C0612), base: hex(0x6E1428), sheen: hex(0xB8405A))
    static let plum = DrapeColors(deep: hex(0x1C0A24), base: hex(0x4A1F5C), sheen: hex(0x9A5CB4))
    static let deepPlum = DrapeColors(deep: hex(0x12061A), base: hex(0x33163F), sheen: hex(0x7A4690))
}

struct Drape {
    var rect: CGRect
    var colors: DrapeColors
    var folds: Int = 7
    var outerLeft: Bool = true           // which side is the fixed/outer edge
    var pinchY: CGFloat? = nil           // tie-back height
    var pinch: CGFloat = 0.55            // 0…1 how much the folds gather toward the outer edge
    var sway: CGFloat = 0                // lateral sweep of the lower part (+ right)
    var seed: UInt64 = 1
    var hemDepth: CGFloat = 26
    var tassel: Bool = true
    var lightFromTop: CGFloat = 0.25     // extra brightness near the top
}

extension Canvas {
    /// Velvet drape: fold boundaries are curves; valleys/crests are painted as blurred tapered strokes that
    /// follow those curves, so gathering (tie-backs) and sweeping keep believable shading.
    @discardableResult
    func drape(_ d: Drape) -> CGPath {
        var rng = RNG(d.seed)
        let r = d.rect
        let n = d.folds
        let samples = 28
        let outerX = d.outerLeft ? r.minX : r.maxX
        // base fold boundary positions
        var baseX: [CGFloat] = []
        for i in 0...n {
            var t = CGFloat(i) / CGFloat(n)
            if i > 0 && i < n { t += rng.range(-0.25, 0.25) / CGFloat(n) }
            baseX.append(r.minX + r.width * t)
        }
        let phases = (0...n).map { _ in rng.range(0, 6.28) }
        func bx(_ i: Int, _ y: CGFloat) -> CGFloat {
            let ty = (y - r.minY) / r.height
            var x = baseX[i] + sin(ty * 5.0 + phases[i]) * r.width * 0.012
            if let py = d.pinchY {
                let sig = r.height * 0.20
                let g = exp(-pow((y - py) / sig, 2))
                // gather toward the outer edge; below the tie-back the drape fans slightly wider
                let below = y > py ? min(1, (y - py) / (r.height * 0.5)) : 0
                x = outerX + (x - outerX) * (1 - d.pinch * g) * (1 - 0.18 * below * (1 - g))
            }
            x += d.sway * pow(ty, 1.6) * (0.4 + 0.6 * CGFloat(i) / CGFloat(max(1, n)))
            return x
        }
        let ys = (0...samples).map { r.minY + r.height * CGFloat($0) / CGFloat(samples) }
        let curves: [[CGPoint]] = (0...n).map { i in ys.map { P(bx(i, $0), $0) } }
        // silhouette with scalloped hem
        let sil = buildPath { p in
            addSmooth(p, curves[0], closed: false, tension: 1, move: true)
            for i in 0..<n {
                let a = curves[i].last!, b = curves[i + 1].last!
                let mid = a.lerp(b, 0.5) + P(0, d.hemDepth * (0.6 + 0.4 * CGFloat((i * 7) % 3) / 2))
                p.addQuadCurve(to: b, control: mid + P(0, d.hemDepth * 0.4))
            }
            addSmooth(p, curves[n].reversed(), closed: false, tension: 1, move: false)
            p.closeSubpath()
        }
        // cast shadow on the backdrop
        shadowOnly(sil, dx: d.outerLeft ? 18 : -18, dy: 14, blur: 40, color: hex(0x07020A, 0.75))
        // base fill with vertical light falloff
        linear(sil, [(0, d.colors.base.mix(d.colors.sheen, d.lightFromTop)), (0.35, d.colors.base), (1, d.colors.deep.mix(d.colors.base, 0.35))], P(0, r.minY), P(0, r.maxY))
        let L = lightDir()
        clip(sil) {
            // soft valleys and crests
            blurred(radius: max(6, r.width / CGFloat(n) * 0.13)) { off in
                for i in 0...n {
                    let widths = ys.enumerated().map { (k, y) -> CGFloat in
                        let a = bx(max(0, i - 1), y), b = bx(min(n, i + 1), y)
                        return max(3, abs(b - a) * 0.26)
                    }
                    off.fill(taperedPath(curves[i], widths: widths, roundCaps: false), d.colors.deep.alpha(0.92))
                }
                for i in 0..<n {
                    let crest = ys.map { y -> CGPoint in
                        let a = bx(i, y), b = bx(i + 1, y)
                        return P(a + (b - a) * (0.40 + 0.06 * L.dx), y)
                    }
                    let widths = ys.map { y in max(2, abs(bx(i + 1, y) - bx(i, y)) * 0.30) }
                    off.fill(taperedPath(crest, widths: widths, roundCaps: false), d.colors.sheen.alpha(0.62))
                    let crest2 = ys.map { y -> CGPoint in
                        let a = bx(i, y), b = bx(i + 1, y)
                        return P(a + (b - a) * 0.66, y)
                    }
                    off.fill(taperedPath(crest2, widths: ys.map { y in max(2, abs(bx(i + 1, y) - bx(i, y)) * 0.16) }, roundCaps: false), d.colors.base.alpha(0.5))
                }
            }
            // crisp sheen lines on crests
            for i in 0..<n {
                let crest = ys.map { y -> CGPoint in let a = bx(i, y), b = bx(i + 1, y); return P(a + (b - a) * 0.38, y) }
                stroke(smoothPath(crest, closed: false), d.colors.sheen.lighter(0.3).alpha(0.18), 2.2)
            }
            // top light & bottom darkening
            linear(sil, [(0, RGBA.white.alpha(0.07)), (0.25, RGBA.clear), (0.75, RGBA.clear), (1, RGBA.black.alpha(0.35))], P(0, r.minY), P(0, r.maxY))
            fabricGrain(sil, alpha: 0.16, fibre: 0.45)
        }
        stroke(smoothPath(curves[d.outerLeft ? n : 0], closed: false), d.colors.sheen.alpha(0.35), 2)
        // tie-back rope + tassel
        if let py = d.pinchY, d.tassel {
            let x0 = outerX, x1 = bx(d.outerLeft ? n : 0, py)
            let dirS: CGFloat = d.outerLeft ? 1 : -1
            let rope = buildPath { p in
                p.move(to: P(x0 - 10 * dirS, py - 16))
                p.addQuadCurve(to: P(x1 + 8 * dirS, py - 4), control: P((x0 + x1) / 2, py + 26))
            }
            stroke(rope, hex(0x2A1606), 26)
            metalRim(rope, width: 18, metal: .gold)
            tassel(at: P(x1 + 2 * dirS, py + 4), size: 90)
        }
        return sil
    }

    /// Gold rope tassel hanging from `p`.
    func tassel(at p: CGPoint, size s: CGFloat) {
        let knob = circlePath(p + P(0, s * 0.16), s * 0.15)
        let skirt = buildPath { q in
            q.move(to: p + P(-s * 0.12, s * 0.26))
            q.addCurve(to: p + P(-s * 0.26, s * 0.98), control1: p + P(-s * 0.22, s * 0.45), control2: p + P(-s * 0.28, s * 0.80))
            q.addQuadCurve(to: p + P(s * 0.26, s * 0.98), control: p + P(0, s * 1.08))
            q.addCurve(to: p + P(s * 0.12, s * 0.26), control1: p + P(s * 0.28, s * 0.80), control2: p + P(s * 0.22, s * 0.45))
            q.closeSubpath()
        }
        stroke(skirt, hex(0x2A1606), 5)
        metalFill(skirt, .gold)
        clip(skirt) {
            for k in -6...6 {
                let x = CGFloat(k) * s * 0.042
                stroke(polygonPath([p + P(x * 0.5, s * 0.3), p + P(x * 1.1, s * 1.05)], closed: false), hex(0x5A3410, 0.55), 1.6)
            }
        }
        stroke(knob, hex(0x2A1606), 5)
        glossy(knob, light: hex(0xFFF3C0), base: hex(0xD9A04A), dark: hex(0x6E4214), spec: 1)
        let cord = rrectPath(CGRect(x: p.x - s * 0.13, y: p.y + s * 0.25, width: s * 0.26, height: s * 0.07), s * 0.03)
        stroke(cord, hex(0x2A1606), 4)
        metalFill(cord, .gold)
    }

    /// Scalloped valance across the top with gold braid, fringe and small tassels.
    func valance(top: CGFloat = 0, bandHeight: CGFloat, swagDepth: CGFloat, swags: Int, colors: DrapeColors, fringe: Bool = true, centerCalm: Bool = true) {
        let W = width
        let band = rectPath(CGRect(x: -10, y: top - 10, width: W + 20, height: bandHeight + 10))
        let sw = W / CGFloat(swags)
        var swagPaths: [CGPath] = []
        var bottoms: [[CGPoint]] = []
        for i in 0..<swags {
            let x0 = CGFloat(i) * sw - 6, x1 = CGFloat(i + 1) * sw + 6
            let depth = swagDepth * (centerCalm ? (0.72 + 0.28 * abs(CGFloat(i) - CGFloat(swags - 1) / 2) / max(1, CGFloat(swags - 1) / 2)) : 1)
            let pts = (0...20).map { k -> CGPoint in
                let t = CGFloat(k) / 20
                return P(x0 + (x1 - x0) * t, top + bandHeight + depth * sin(t * .pi))
            }
            bottoms.append(pts)
            swagPaths.append(buildPath { p in
                p.move(to: P(x0, top + bandHeight - 4))
                addSmooth(p, pts, closed: false, move: false)
                p.addLine(to: P(x1, top + bandHeight - 4))
                p.closeSubpath()
            })
        }
        // shadow under swags
        for s in swagPaths { shadowOnly(s, dx: 8, dy: 20, blur: 34, color: hex(0x05010A, 0.8)) }
        for (i, s) in swagPaths.enumerated() {
            let bb = s.bbox
            linear(s, [(0, colors.deep), (0.45, colors.base), (1, colors.deep.mix(colors.base, 0.5))], P(0, bb.minY), P(0, bb.maxY))
            clip(s) {
                blurred(radius: 7) { off in
                    // concentric drape folds following the swag curve
                    for k in 1...5 {
                        let f = CGFloat(k) / 6
                        let pts = bottoms[i].map { P($0.x, bb.minY + ($0.y - bb.minY) * f) }
                        off.stroke(smoothPath(pts, closed: false), (k % 2 == 0 ? colors.sheen.alpha(0.55) : colors.deep.alpha(0.8)), bb.height * 0.07)
                    }
                }
                fabricGrain(s, alpha: 0.14)
            }
        }
        // band
        linear(band, [(0, colors.deep), (0.6, colors.base), (1, colors.deep)], P(0, top), P(0, top + bandHeight))
        fabricGrain(band, alpha: 0.12)
        let braid = buildPath { p in p.move(to: P(-10, top + bandHeight - 6)); p.addLine(to: P(W + 10, top + bandHeight - 6)) }
        stroke(braid, hex(0x2A1606), 22)
        metalRim(braid, width: 16, metal: .gold, bbox: CGRect(x: 0, y: top + bandHeight - 30, width: W, height: 60))
        // braid twist marks
        var x: CGFloat = 0
        while x < W { stroke(polygonPath([P(x, top + bandHeight - 13), P(x + 8, top + bandHeight + 1)], closed: false), hex(0x6A4012, 0.7), 2); x += 14 }
        if fringe {
            for pts in bottoms {
                let path = smoothPath(pts, closed: false)
                let flat = flatten(path, step: 7).first ?? []
                for q in flat {
                    stroke(polygonPath([q, q + P(0, 24)], closed: false), hex(0x3A220A), 5)
                }
                for q in flat {
                    linear(polygonPath([q + P(-1.6, 0), q + P(1.6, 0), q + P(1.6, 22), q + P(-1.6, 22)]), [(0, hex(0xFFE7A0)), (0.5, hex(0xD9A04A)), (1, hex(0x7A4A18))], q, q + P(0, 22))
                }
                stroke(path, hex(0x2A1606), 10)
                metalRim(path, width: 7, metal: .gold)
            }
        }
        // tassels at swag junctions (outer ones only keep the centre calm)
        for i in 1..<swags {
            let xj = CGFloat(i) * sw
            let edge = abs(xj - W / 2) > W * 0.25
            if edge || !centerCalm { tassel(at: P(xj, top + bandHeight - 4), size: 110) }
        }
    }

    /// Fragment of a large brass stage ring; faded out toward the horizontal centre.
    func brassRingFragments(center c0: CGPoint, radius R: CGFloat, width w: CGFloat, calmHalfWidth: CGFloat, fadeWidth: CGFloat = 160, bolts: Int = 36) {
        layer {
            let ring = circlePath(c0, R)
            shadowOnly(ring.stroked(w), dx: 12, dy: 18, blur: 30, color: hex(0x05010A, 0.8))
            stroke(ring, Metal.brass.edge, w + 8)
            metalFill(ring.stroked(w), .brass, bbox: CGRect(x: c0.x - R, y: c0.y - R, width: 2 * R, height: 2 * R))
            // grooves
            for (off, col, lw) in [(-w * 0.30, hex(0x3A220A, 0.7), CGFloat(4)), (-w * 0.26, hex(0xFFE6B0, 0.45), 2), (w * 0.28, hex(0x3A220A, 0.7), 4), (w * 0.32, hex(0xFFE6B0, 0.35), 2)] {
                stroke(circlePath(c0, R + off), col, lw)
            }
            // specular wire along the inner lip (lit side)
            let (a, b) = lightAxis(CGRect(x: c0.x - R, y: c0.y - R, width: 2 * R, height: 2 * R))
            linear(circlePath(c0, R - w * 0.12).stroked(w * 0.10), [(0, RGBA.white.alpha(0.7)), (0.35, RGBA.white.alpha(0.0)), (0.7, RGBA.clear), (1, hex(0xFFD9A0, 0.25))], a, b)
            // bolts & notches
            for k in 0..<bolts {
                let ang = CGFloat(k) / CGFloat(bolts) * 2 * .pi
                let pc = c0 + P(cos(ang), sin(ang)) * R
                let bolt = circlePath(pc, w * 0.085)
                stroke(bolt, hex(0x2A1606, 0.9), 3)
                glossy(bolt, light: hex(0xFFF0C8), base: hex(0xC08840), dark: hex(0x5A3412), spec: 0.9)
                let t0 = c0 + P(cos(ang + .pi / CGFloat(bolts)), sin(ang + .pi / CGFloat(bolts))) * (R - w * 0.42)
                let t1 = c0 + P(cos(ang + .pi / CGFloat(bolts)), sin(ang + .pi / CGFloat(bolts))) * (R - w * 0.30)
                stroke(polygonPath([t0, t1], closed: false), hex(0x3A220A, 0.8), 3)
            }
            // erase the calm centre band
            ctx.setBlendMode(.destinationOut)
            let cx = width / 2
            linear(nil, [(0, RGBA.black.alpha(0)), (0.5, RGBA.black), (1, RGBA.black.alpha(0))],
                   P(cx - calmHalfWidth - fadeWidth, 0), P(cx + calmHalfWidth + fadeWidth, 0))
            fill(rectPath(CGRect(x: cx - calmHalfWidth, y: 0, width: calmHalfWidth * 2, height: height)), RGBA.black)
        }
    }

    /// Soft volumetric light cone with drifting dust motes.
    func lightCone(apex: CGPoint, toward target: CGPoint, spread: CGFloat, color: RGBA, alpha: CGFloat, dust: Int = 60, seed: UInt64 = 5, blur: CGFloat = 38) {
        let dir = (target - apex).norm
        let len = (target - apex).len
        let n = dir.perp
        let halfW = tan(spread / 2) * len
        let cone = polygonPath([apex + n * 10, target + n * halfW, target - n * halfW, apex - n * 10])
        blurred(radius: blur, blend: .screen) { off in
            off.linear(cone, [(0, color.alpha(alpha)), (0.55, color.alpha(alpha * 0.45)), (1, color.alpha(0))], apex, target)
            // brighter core
            let core = polygonPath([apex + n * 4, target + n * halfW * 0.4, target - n * halfW * 0.4, apex - n * 4])
            off.linear(core, [(0, color.lighter(0.4).alpha(alpha * 0.8)), (0.6, color.alpha(alpha * 0.2)), (1, color.alpha(0))], apex, target)
        }
        var rng = RNG(seed)
        layer(blend: .screen) {
            for _ in 0..<dust {
                let t = rng.range(0.15, 0.95)
                let s = rng.range(-0.8, 0.8)
                let p = apex + dir * (len * t) + n * (halfW * t * s)
                let rr = rng.range(1.2, 3.6)
                let a = rng.range(0.15, 0.6) * (1 - t * 0.6) * (1 - abs(s) * 0.6)
                blob(p, rx: rr * 2.2, ry: rr * 2.2, color: color.lighter(0.5).alpha(a * 0.5))
                fill(circlePath(p, rr * 0.5), color.lighter(0.7).alpha(a))
            }
        }
    }

    func vignette(strength: CGFloat = 0.6, center: CGPoint? = nil) {
        let c0 = center ?? P(width / 2, height * 0.46)
        radialEllipse(nil, [(0, RGBA.black.alpha(0)), (0.55, RGBA.black.alpha(0)), (0.85, RGBA.black.alpha(strength * 0.55)), (1, RGBA.black.alpha(strength))],
                      center: c0, rx: width * 0.78, ry: height * 0.62)
    }

    /// Whole-canvas fine noise (also dithers 8-bit gradients).
    func filmGrain(alpha: CGFloat = 0.06) { fabricGrain(nil, alpha: alpha, fibre: 0.0) }

    /// Perspective stage floor planks (very low contrast).
    func stageFloor(top y0: CGFloat, vanish: CGPoint, color: RGBA, lineColor: RGBA, planks: Int = 18) {
        let floor = rectPath(CGRect(x: 0, y: y0, width: width, height: height - y0))
        linear(floor, [(0, color.alpha(0)), (0.15, color), (1, color.darker(0.3))], P(0, y0), P(0, height))
        clip(floor) {
            for i in 0...planks {
                let xb = -width * 0.6 + CGFloat(i) / CGFloat(planks) * width * 2.2
                let top = vanish.lerp(P(xb, height), (y0 - vanish.y) / (height - vanish.y))
                stroke(polygonPath([top, P(xb, height)], closed: false), lineColor, 2)
            }
            var y = y0 + 40.0
            var gap: CGFloat = 40
            while y < height { stroke(polygonPath([P(0, y), P(width, y)], closed: false), lineColor.alpha(lineColor.a * 0.6), 1.5); gap *= 1.25; y += gap }
            linear(floor, [(0, Pal.plumStage), (0.12, Pal.plumStage.alpha(0))], P(0, y0), P(0, y0 + 120))
        }
    }

    /// Hanging link chain from a to b (vertical-ish), bronze.
    func chain(from a: CGPoint, to b: CGPoint, link: CGFloat, metal: Metal = .bronze, sag: CGFloat = 0) {
        let len = (b - a).len
        let count = Int(len / (link * 0.78))
        let dir = (b - a).norm
        for k in 0..<count {
            let t = CGFloat(k) / CGFloat(max(1, count - 1))
            let p = a.lerp(b, t) + dir.perp * (sag * sin(t * .pi))
            let ang = atan2(dir.y, dir.x)
            let flat = k % 2 == 1
            let e = rotatedEllipse(p, link * 0.55, flat ? link * 0.14 : link * 0.30, ang)
            if flat {
                stroke(e, metal.edge, link * 0.22)
                metalRim(e, width: link * 0.14, metal: metal)
            } else {
                stroke(e, metal.edge, link * 0.26)
                metalRim(e, width: link * 0.16, metal: metal)
            }
        }
    }

    /// Gear with n teeth, bronze plate with spokes and bolts.
    func gear(center c0: CGPoint, radius R: CGFloat, teeth: Int, rotation: CGFloat = 0, metal: Metal = .bronze, spokes: Int = 5) {
        let path = buildPath { p in
            let tooth = R * 0.12
            for k in 0..<teeth {
                let a0 = rotation + CGFloat(k) / CGFloat(teeth) * 2 * .pi
                let da = 2 * .pi / CGFloat(teeth)
                let pts = [(a0, R - tooth), (a0 + da * 0.18, R - tooth), (a0 + da * 0.28, R + tooth * 0.6), (a0 + da * 0.62, R + tooth * 0.6), (a0 + da * 0.72, R - tooth)]
                for (i, (a, r)) in pts.enumerated() {
                    let q = c0 + P(cos(a), sin(a)) * r
                    if k == 0 && i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
            }
            p.closeSubpath()
            // spoke windows (even-odd holes)
            for s in 0..<spokes {
                let a = rotation + CGFloat(s) / CGFloat(spokes) * 2 * .pi + .pi / CGFloat(spokes)
                let win = buildPath { q in
                    q.addArc(center: c0, radius: R * 0.70, startAngle: a - .pi / CGFloat(spokes) * 0.62, endAngle: a + .pi / CGFloat(spokes) * 0.62, clockwise: false)
                    q.addArc(center: c0, radius: R * 0.34, startAngle: a + .pi / CGFloat(spokes) * 0.45, endAngle: a - .pi / CGFloat(spokes) * 0.45, clockwise: true)
                    q.closeSubpath()
                }
                p.addPath(win)
            }
        }
        shadowOnly(path, dx: 14, dy: 20, blur: 26, color: hex(0x05010A, 0.85))
        stroke(path, metal.edge, 8)
        clip(path, evenOdd: true) {
            metalFill(rectPath(CGRect(x: c0.x - R * 1.2, y: c0.y - R * 1.2, width: R * 2.4, height: R * 2.4)), metal)
            let L = lightDir()
            innerShadow(path, dx: L.dx * 10, dy: L.dy * 10, blur: 10, color: metal.edge.alpha(0.8))
            innerShadow(path, dx: -L.dx * 6, dy: -L.dy * 6, blur: 6, color: metal.spec.alpha(0.6))
        }
        stroke(circlePath(c0, R * 0.78), metal.edge.alpha(0.6), 3)
        let hub = circlePath(c0, R * 0.2)
        stroke(hub, metal.edge, 6)
        glossy(hub, light: metal.spec, base: metal.stops[2].1, dark: metal.edge, spec: 0.8)
        for k in 0..<6 {
            let a = rotation + CGFloat(k) / 6 * 2 * .pi
            let b = circlePath(c0 + P(cos(a), sin(a)) * R * 0.88, R * 0.035)
            glossy(b, light: metal.spec, base: metal.stops[3].1, dark: metal.edge, spec: 0.8)
        }
    }

    /// Warm marquee bulb.
    func bulb(_ p: CGPoint, r: CGFloat, color: RGBA = hex(0xFFD98A), glow: CGFloat = 1) {
        layer(blend: .screen) { blob(p, rx: r * 4.5, ry: r * 4.5, color: color.alpha(0.35 * glow)) }
        let socket = circlePath(p, r * 1.25)
        stroke(socket, hex(0x2A1606), 3)
        metalFill(socket, .brass)
        let b = circlePath(p, r)
        glossy(b, light: hex(0xFFFFF0), base: color, dark: color.darker(0.35), spec: 1)
    }
}
