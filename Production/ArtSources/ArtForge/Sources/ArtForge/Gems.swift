// Gems.swift — VC07–VC11 base tokens (Heart, Diamond, Clover, Bell, Star) and the shared
// faceted-gem renderer. Every token is a bold, shape-distinct silhouette with bevel facets,
// a narrow polished-gold rim, a dark separating outline and upper-left specular.
import Foundation
import CoreGraphics

struct GemColors {
    let deep: RGBA, mid: RGBA, light: RGBA, glint: RGBA, edge: RGBA
    static let ruby = GemColors(deep: hex(0x4A0414), mid: hex(0xC8102F), light: hex(0xFF4A62), glint: hex(0xFFD0D8), edge: hex(0x2A020C))
    static let sapphire = GemColors(deep: hex(0x0A2A66), mid: hex(0x1C6FD8), light: hex(0x4DB4FF), glint: hex(0xD8F2FF), edge: hex(0x06122E))
    static let emerald = GemColors(deep: hex(0x05412D), mid: hex(0x169A69), light: hex(0x46D9A0), glint: hex(0xD4FFEC), edge: hex(0x032014))
    static let amethyst = GemColors(deep: hex(0x2E0F60), mid: hex(0x7B43D2), light: hex(0xB883F7), glint: hex(0xF2E2FF), edge: hex(0x14052E))
    static let amber = GemColors(deep: hex(0x6E2E04), mid: hex(0xE38A1C), light: hex(0xFFC54F), glint: hex(0xFFF6D0), edge: hex(0x2E1202))
    static let crimsonCrystal = GemColors(deep: hex(0x4E0414), mid: hex(0xD0203F), light: hex(0xFF6B7E), glint: hex(0xFFE0E4), edge: hex(0x22010A))
}

/// Flat-facet colour from a facet normal under the scene key light.
func facetColor(_ n: V3, _ g: GemColors, gain: CGFloat = 1) -> RGBA {
    let d = max(0, n.dot(keyLight)) * gain
    let t = clamp01((d - 0.12) / 0.86)
    var col = t < 0.5 ? g.deep.mix(g.mid, t / 0.5) : g.mid.mix(g.light, (t - 0.5) / 0.5)
    let s = pow(max(0, n.dot(halfVec)), 36)
    col = col.mix(g.glint, min(1, s * 0.85))
    return col
}

struct GemStyle {
    var rim: CGFloat = 13           // gold rim width (design px at 512)
    var outline: CGFloat = 5        // dark outline outside the rim
    var bevel: CGFloat = 42         // bevel facet slope in degrees
    var tableSlope: CGFloat = 12    // star-facet slope on the table
    var tableScale: CGFloat = 0.52
    var shadow: Bool = true
}

extension Canvas {
    /// Generic bevel-cut gem from an explicit outer polygon.
    /// - outer: polygon vertices (clockwise or ccw), silhouette path `shape` used for clipping/rim.
    func facetedGem(shape: CGPath, outer: [CGPoint], tableCenter: CGPoint, colors g: GemColors, style s: GemStyle,
                    tableFacets: Bool = true, rimMetal: Metal = .gold, drawRim: Bool = true) {
        let n = outer.count
        let inner = scalePoints(outer, about: tableCenter, s.tableScale)
        let ctr = centroid(outer)
        let bev = deg(s.bevel)
        clip(shape) {
            fill(shape, g.deep)
            // bevel facets (extend outer points outward so chords never leave slivers)
            let ext = scalePoints(outer, about: tableCenter, 1.08)
            for i in 0..<n {
                let j = (i + 1) % n
                let e = outer[j] - outer[i]
                var o = e.perp.norm
                let mid = (outer[i] + outer[j]) * 0.5
                if o.dot(mid - ctr) < 0 { o = o * -1 }
                let nrm = V3(o.x * sin(bev), o.y * sin(bev), cos(bev)).norm
                let base = facetColor(nrm, g)
                let quad = polygonPath([ext[i], ext[j], inner[j], inner[i]])
                let im = (inner[i] + inner[j]) * 0.5
                linear(quad, [(0, base.lighter(0.10)), (1, base.darker(0.10))], im, mid)
            }
            // table
            let tablePath = polygonPath(inner)
            if tableFacets {
                let ts = deg(s.tableSlope)
                for i in 0..<n {
                    let j = (i + 1) % n
                    let e = inner[j] - inner[i]
                    var o = e.perp.norm
                    let mid = (inner[i] + inner[j]) * 0.5
                    if o.dot(mid - tableCenter) < 0 { o = o * -1 }
                    let nrm = V3(o.x * sin(ts), o.y * sin(ts), cos(ts)).norm
                    let base = facetColor(nrm, g, gain: 0.98)
                    fill(polygonPath([tableCenter, inner[i], inner[j]]), base)
                }
            } else {
                let (a, b) = lightAxis(tablePath.bbox)
                linear(tablePath, [(0, g.light), (0.5, g.mid), (1, g.deep.mix(g.mid, 0.4))], a, b)
            }
            // facet ridges
            let ridgeCol = g.glint.alpha(0.22)
            for i in 0..<n { stroke(polygonPath([outer[i], inner[i]], closed: false), ridgeCol, 1.4) }
            stroke(tablePath, g.glint.alpha(0.45), 2.0)
            // transmitted light pooling at the lower-right inside the table (depth cue)
            let L = lightDir(); let l = P(L.dx, L.dy)
            let tb = tablePath.bbox
            let tr = max(tb.width, tb.height)
            layer(blend: .screen) {
                blob(P(tb.midX, tb.midY) - l * (tr * 0.30), rx: tr * 0.34, ry: tr * 0.22, color: g.light.alpha(0.55), angle: atan2(-L.dx, L.dy) + .pi / 2, clip: tablePath)
            }
            // broad soft gloss on the upper-left
            let sb = shape.bbox
            let sr = max(sb.width, sb.height)
            layer(blend: .screen) {
                blob(P(sb.midX, sb.midY) + l * (sr * 0.22), rx: sr * 0.42, ry: sr * 0.30, color: RGBA.white.alpha(0.13), angle: atan2(-L.dx, L.dy) + .pi / 2)
            }
            // occlusion at the lower-right edge
            innerShadow(shape, dx: L.dx * sr * 0.035, dy: L.dy * sr * 0.035, blur: sr * 0.05, color: g.edge.alpha(0.55))
        }
        if drawRim { metalRim(shape, width: s.rim, metal: rimMetal) }
    }

    /// Crisp specular highlights placed on the lit shoulder of a gem.
    func gemSpecular(_ shape: CGPath, at p: CGPoint, size: CGFloat, angle: CGFloat = deg(-40)) {
        clip(shape) {
            // curved window reflection
            let r = size
            let arc = buildPath { q in
                q.addArc(center: p + P(r * 0.9, r * 0.9), radius: r * 1.25, startAngle: deg(185), endAngle: deg(265), clockwise: false)
            }
            stroke(arc, RGBA.white.alpha(0.85), r * 0.20)
            blob(p + P(r * 0.1, r * 0.1), rx: r * 0.55, ry: r * 0.32, color: RGBA.white.alpha(0.45), angle: angle)
        }
        clip(shape) { fill(circlePath(p + P(-size * 0.05, size * 0.55), size * 0.10), RGBA.white.alpha(0.95)) }
    }
}

// MARK: - Shapes (unit space ≈ ±1, y-down)

/// Symmetric chubby heart: right half defined, left half mirrored.
func heartHalfPoints(notch: CGFloat = -0.52) -> [CGPoint] {
    let half = buildPath { p in
        p.move(to: P(0, 0.93))
        p.addCurve(to: P(0.90, -0.10), control1: P(0.34, 0.66), control2: P(0.90, 0.30))
        p.addCurve(to: P(0.47, -0.84), control1: P(0.90, -0.56), control2: P(0.72, -0.84))
        p.addCurve(to: P(0, notch), control1: P(0.22, -0.84), control2: P(0.05, notch - 0.18))
    }
    return flatten(half, step: 0.004).first!
}
func heartPath(notch: CGFloat = -0.52) -> CGPath {
    let r = heartHalfPoints(notch: notch)
    let l = r.reversed().map { P(-$0.x, $0.y) }
    return smoothPath(Array(r.dropLast()) + Array(l.dropLast()), closed: true, tension: 0.9)
}
func heartOuterPolygon(segmentsPerSide k: Int) -> [CGPoint] {
    // resample the right half evenly (open curve), mirror for left
    let r = heartHalfPoints()
    var cum: [CGFloat] = [0]
    for i in 1..<r.count { cum.append(cum[i - 1] + r[i].dist(r[i - 1])) }
    let total = cum.last!
    // bias samples: more resolution on the lobes
    var right: [CGPoint] = []
    var j = 1
    for s in 0...k {
        let d = total * CGFloat(s) / CGFloat(k)
        while j < cum.count - 1 && cum[j] < d { j += 1 }
        let seg = max(1e-9, cum[j] - cum[j - 1])
        right.append(r[j - 1].lerp(r[j], clamp01((d - cum[j - 1]) / seg)))
    }
    // right: tip ... notch ; left: notch ... tip (mirrored), skip duplicates
    let left = right.reversed().map { P(-$0.x, $0.y) }
    return Array(right) + Array(left.dropFirst().dropLast())
}

// MARK: - Token renderers (canvas 512 design units)

enum Gems {
    static let S: CGFloat = 190          // unit → design px (≈10–12 % transparent padding at 512)
    static let C = P(256, 256)

    static func place(_ c: Canvas, scale: CGFloat = S, center: CGPoint = C, _ body: () -> Void) {
        c.transform(CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: scale / S, y: scale / S)) { body() }
    }

    static func heart(_ c: Canvas, center: CGPoint = C, scale: CGFloat = S, shadow: Bool = true) {
        let t = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: scale, y: scale)
        let k = scale / S
        let shape = heartPath().transformed(t)
        let outer = heartOuterPolygon(segmentsPerSide: 9).map { $0.applying(t) }
        let tc = P(0, -0.02).applying(t)
        if shadow { c.dropShadow(shape, dx: 7 * k, dy: 11 * k, blur: 16 * k, alpha: 0.42) }
        c.stroke(shape, GemColors.ruby.edge, (13 + 10) * k)
        var st = GemStyle(); st.rim *= k; st.tableScale = 0.50
        c.facetedGem(shape: shape, outer: outer, tableCenter: tc, colors: .ruby, style: st)
        c.gemSpecular(shape, at: P(-0.52, -0.46).applying(t), size: 58 * k)
        c.glint(P(-0.50, -0.20).applying(t), size: 20 * k)
    }

    static func diamond(_ c: Canvas, center: CGPoint = C, scale: CGFloat = S, shadow: Bool = true) {
        let t = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: scale, y: scale)
        let k = scale / S
        let outer = [P(0, -1.0), P(0.76, 0), P(0, 1.0), P(-0.76, 0)].map { $0.applying(t) }
        let shape = roundedPolygon(outer, radius: 12 * k)
        if shadow { c.dropShadow(shape, dx: 7 * k, dy: 11 * k, blur: 16 * k, alpha: 0.42) }
        c.stroke(shape, GemColors.sapphire.edge, (13 + 10) * k)
        var st = GemStyle(); st.rim *= k; st.tableScale = 0.44; st.bevel = 46; st.tableSlope = 16
        c.facetedGem(shape: shape, outer: outer, tableCenter: P(0, 0).applying(t), colors: .sapphire, style: st)
        c.gemSpecular(shape, at: P(-0.30, -0.44).applying(t), size: 48 * k)
        c.glint(P(-0.36, -0.08).applying(t), size: 18 * k)
    }

    static func star(_ c: Canvas, center: CGPoint = C, scale: CGFloat = S, shadow: Bool = true) {
        let t = CGAffineTransform(translationX: center.x, y: center.y + 0.06 * scale).scaledBy(x: scale, y: scale)
        let k = scale / S
        let pts = starPoints(.zero, outer: 1.04, inner: 0.52).map { $0.applying(t) }
        let shape = roundedPolygon(pts, radius: 14 * k)
        let ctr = P(0, 0).applying(t)
        if shadow { c.dropShadow(shape, dx: 7 * k, dy: 11 * k, blur: 16 * k, alpha: 0.42) }
        c.stroke(shape, GemColors.amethyst.edge, (13 + 10) * k)
        let g = GemColors.amethyst
        c.clip(shape) {
            c.fill(shape, g.deep)
            // 10 ridge facets rising to a raised centre
            let h: CGFloat = 0.55 * scale
            let apex = V3(ctr.x, ctr.y, h)
            let ext = scalePoints(pts, about: ctr, 1.1)
            for i in 0..<pts.count {
                let j = (i + 1) % pts.count
                let a = V3(pts[i].x, pts[i].y, 0), b = V3(pts[j].x, pts[j].y, 0)
                var nrm = (b - a).cross(apex - a).norm
                if nrm.z < 0 { nrm = V3(-nrm.x, -nrm.y, -nrm.z) }
                let col = facetColor(nrm, g)
                let tri = polygonPath([ctr, ext[i], ext[j]])
                c.linear(tri, [(0, col.lighter(0.08)), (1, col.darker(0.12))], ctr, (pts[i] + pts[j]) * 0.5)
            }
            for i in 0..<pts.count { c.stroke(polygonPath([ctr, pts[i]], closed: false), g.glint.alpha(i % 2 == 0 ? 0.40 : 0.18), 1.6 * k) }
            // small raised table at the centre
            let table = starPoints(ctr, outer: 0.24 * scale, inner: 0.12 * scale)
            let tp = roundedPolygon(table, radius: 3 * k)
            let (a, b) = c.lightAxis(tp.bbox)
            c.linear(tp, [(0, g.glint), (0.4, g.light), (1, g.mid)], a, b)
            c.stroke(tp, g.glint.alpha(0.6), 1.6 * k)
            let L = c.lightDir(); let l = P(L.dx, L.dy)
            c.layer(blend: .screen) {
                c.blob(ctr - l * (0.35 * scale), rx: 0.40 * scale, ry: 0.22 * scale, color: g.light.alpha(0.45), angle: atan2(-L.dx, L.dy) + .pi / 2)
            }
            let sr = shape.bbox.width
            c.innerShadow(shape, dx: L.dx * sr * 0.035, dy: L.dy * sr * 0.035, blur: sr * 0.05, color: g.edge.alpha(0.55))
        }
        c.metalRim(shape, width: 13 * k, metal: .gold)
        c.gemSpecular(shape, at: P(-0.20, -0.62).applying(t), size: 36 * k)
        c.glint(P(-0.55, -0.22).applying(t), size: 18 * k)
    }

    static func clover(_ c: Canvas, center: CGPoint = C, scale: CGFloat = S, shadow: Bool = true) {
        let k = scale / S
        let g = GemColors.emerald
        let ct = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: scale, y: scale)
        // stem (behind the leaves), from centre toward lower-right
        let stemPts = [P(0.02, 0.05), P(0.30, 0.42), P(0.52, 0.66), P(0.60, 0.92)].map { $0.applying(ct) }
        let stem = taperedPath(stemPts, widths: [0.20, 0.16, 0.13, 0.12].map { $0 * scale })
        // leaves: heart shapes pointing inward, one per quadrant (up/right/down/left), each cut to its
        // own 90° wedge so the four lobes never overlap and read as separate leaves with dark seams.
        var leaves: [(CGPath, [CGPoint], CGPoint, CGFloat)] = []
        let gap = 0.035 * scale
        for q in 0..<4 {
            let ang = CGFloat(q) * .pi / 2
            let lt = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: ang)
                .translatedBy(x: 0, y: -0.52 * scale)
                .scaledBy(x: 0.52 * scale, y: -0.50 * scale)       // flip: heart tip points to clover centre
            var shape = heartPath(notch: -0.36).transformed(lt)
            if #available(macOS 14.0, *) {
                // wedge between the two diagonals around this leaf's axis, shrunk by the seam gap
                let wt = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: ang)
                let far = 2.0 * scale
                let wedge = polygonPath([P(gap * 1.4142, 0), P(far, -far + gap * 1.4142), P(-far, -far + gap * 1.4142), P(-gap * 1.4142, 0), P(0, -gap * 1.4142)].map { $0.applying(wt) })
                shape = shape.intersection(wedge)
            }
            let outline = flatten(shape, step: 0.5).max(by: { $0.count < $1.count }) ?? []
            let outer = resampleClosed(outline, 22)
            let tc = P(0, 0.08).applying(lt)
            leaves.append((shape, outer, tc, ang))
        }
        let all = combine(leaves.map { $0.0 } + [stem])
        if shadow { c.dropShadow(all, dx: 7 * k, dy: 11 * k, blur: 16 * k, alpha: 0.42) }
        // dark backing: fills the seams so leaves read as four separate lobes with dark gaps
        c.stroke(all, g.edge, 23 * k)
        c.fill(all, g.edge)
        // stem
        c.glossy(stem, light: g.light, base: g.mid, dark: g.deep, spec: 0.5)
        c.metalRim(stem, width: 9 * k)
        var st = GemStyle(); st.rim = 11 * k; st.tableScale = 0.50; st.bevel = 44
        for (shape, outer, tc, _) in leaves {
            c.facetedGem(shape: shape, outer: outer, tableCenter: tc, colors: g, style: st)
        }
        // central gold boss where leaves meet
        let boss = circlePath(center, 0.13 * scale)
        c.stroke(boss, g.edge, 6 * k)
        c.glossy(boss, light: hex(0xFFF1B0), base: hex(0xE0A64E), dark: hex(0x7A4A1C), spec: 1, specSize: 1.2)
        c.gemSpecular(leaves[0].0, at: P(-0.36, -0.86).applying(ct), size: 30 * k)
        c.gemSpecular(leaves[3].0, at: P(-0.86, -0.36).applying(ct), size: 26 * k)
    }

    static func bell(_ c: Canvas, center: CGPoint = C, scale: CGFloat = S, shadow: Bool = true) {
        let k = scale / S
        let g = GemColors.amber
        let t = CGAffineTransform(translationX: center.x, y: center.y + 0.02 * scale).scaledBy(x: scale, y: scale)
        // right-half profile, mirrored
        let prof: [CGPoint] = [P(0, -0.80), P(0.26, -0.77), P(0.43, -0.60), P(0.49, -0.30), P(0.54, 0.02),
                               P(0.64, 0.30), P(0.80, 0.50), P(0.88, 0.60)]
        // body outline closed across the lip line
        let body = buildPath { p in
            addSmooth(p, prof.map { $0.applying(t) }, closed: false)
            p.addCurve(to: P(0, 0.66).applying(t), control1: P(0.70, 0.66).applying(t), control2: P(0.35, 0.66).applying(t))
            p.addCurve(to: P(-0.88, 0.60).applying(t), control1: P(-0.35, 0.66).applying(t), control2: P(-0.70, 0.66).applying(t))
            addSmooth(p, prof.reversed().map { P(-$0.x, $0.y).applying(t) }, closed: false, move: false)
            p.closeSubpath()
        }
        // lip ring seen slightly from below: outer ellipse, opening (inner ellipse), clapper inside
        let lipC = P(0, 0.64).applying(t)
        let lipOuter = ellipsePath(lipC, 0.93 * scale, 0.19 * scale)
        let opening = ellipsePath(P(0, 0.665).applying(t), 0.78 * scale, 0.125 * scale)
        let lipBand = combine([lipOuter, opening])
        let loopRing = ellipsePath(P(0, -0.90).applying(t), 0.15 * scale, 0.14 * scale)
        let clapper = circlePath(P(0.0, 0.80).applying(t), 0.165 * scale)
        let everything = combine([body, lipOuter, loopRing, clapper])
        if shadow { c.dropShadow(everything, dx: 7 * k, dy: 11 * k, blur: 16 * k, alpha: 0.42) }
        c.stroke(everything, g.edge, 23 * k)
        c.fill(everything, g.edge)
        // hanging loop
        c.stroke(loopRing, g.edge, 22 * k)
        c.metalRim(loopRing, width: 12 * k)
        // body: cylindrical metallic banding (horizontal) + vertical key light
        let bb = body.bbox
        c.clip(body) {
            c.linear(body, [(0.00, hex(0x8A3E08)), (0.10, hex(0xE8961E)), (0.24, hex(0xFFD875)), (0.33, hex(0xFFF3C0)),
                            (0.42, hex(0xFFC44A)), (0.60, hex(0xE0851A)), (0.78, hex(0xA2480C)), (0.90, hex(0xB0344A)), (1.0, hex(0x5A1A0E))],
                     P(bb.minX, 0), P(bb.maxX, 0))
            c.layer(blend: .multiply) {
                c.linear(body, [(0, RGBA.white), (0.55, RGBA.white), (1, hex(0xC98C6A))], P(0, bb.minY), P(0, bb.maxY))
            }
            c.layer(blend: .screen) {
                c.linear(body, [(0, hex(0xFFF3C0, 0.45)), (0.35, hex(0xFFF3C0, 0.0))], P(0, bb.minY), P(0, bb.maxY))
            }
            // shoulder ring engraving
            let ringY = P(0, -0.34).applying(t).y
            let ring = buildPath { p in
                p.move(to: P(P(-0.52, 0).applying(t).x, ringY + 6 * k))
                p.addQuadCurve(to: P(P(0.52, 0).applying(t).x, ringY + 6 * k), control: P(center.x, ringY + 22 * k))
            }
            c.stroke(ring, hex(0x7A3A08, 0.65), 9 * k)
            c.stroke(ring.transformed(CGAffineTransform(translationX: 0, y: -3 * k)), hex(0xFFE7A0, 0.8), 3.5 * k)
            // vertical specular stripe
            let stripe = buildPath { p in
                let x0 = P(-0.30, 0).applying(t).x
                p.move(to: P(x0, P(0, -0.66).applying(t).y))
                p.addCurve(to: P(x0 - 0.16 * scale, P(0, 0.46).applying(t).y), control1: P(x0 - 0.06 * scale, P(0, -0.2).applying(t).y), control2: P(x0 - 0.06 * scale, P(0, 0.2).applying(t).y))
            }
            c.stroke(stripe, RGBA.white.alpha(0.55), 20 * k)
            c.stroke(stripe, RGBA.white.alpha(0.95), 7 * k)
            let L = c.lightDir()
            c.innerShadow(body, dx: L.dx * 14 * k, dy: L.dy * 14 * k, blur: 16 * k, color: hex(0x3A1004, 0.55))
        }
        c.metalRim(body, width: 8 * k, metal: .gold)
        // mouth interior: burgundy reflected light
        c.radialEllipse(opening, [(0, hex(0x8A1838)), (0.65, hex(0x420820)), (1, hex(0x1A0208))], center: P(0.15, 0.62).applying(t), rx: 0.78 * scale, ry: 0.20 * scale)
        // clapper hangs inside the opening, lower half pokes below the front lip
        c.stroke(clapper, g.edge, 6 * k)
        c.glossy(clapper, light: hex(0xFFF0B8), base: hex(0xD09036), dark: hex(0x5A300C), bounce: hex(0xB5264A, 0.7), spec: 1, specSize: 1.2)
        // lip band on top
        c.clip(lipBand, evenOdd: true) {
            c.linear(lipOuter, [(0.0, hex(0xA8601A)), (0.18, hex(0xFFE08A)), (0.30, hex(0xFFFBE0)), (0.45, hex(0xF4B548)),
                           (0.7, hex(0xB7661A)), (0.88, hex(0xC0405A)), (1, hex(0x6E2A10))],
                     P(lipOuter.bbox.minX, 0), P(lipOuter.bbox.maxX, 0))
            c.linear(lipOuter, [(0, RGBA.white.alpha(0.35)), (0.5, RGBA.clear), (1, RGBA.black.alpha(0.3))], P(0, lipOuter.bbox.minY), P(0, lipOuter.bbox.maxY))
        }
        c.stroke(lipOuter, g.edge, 4 * k)
        c.stroke(opening, g.edge.alpha(0.8), 3 * k)
        c.glint(P(-0.36, -0.52).applying(t), size: 22 * k)
    }
}
