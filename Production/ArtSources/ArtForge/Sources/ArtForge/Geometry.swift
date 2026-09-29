// Geometry.swift — vector maths and path construction helpers (y-down design space).
import Foundation
import CoreGraphics

@inline(__always) func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { P(a.x + b.x, a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { P(a.x - b.x, a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { P(a.x * s, a.y * s) }
    static func / (a: CGPoint, s: CGFloat) -> CGPoint { P(a.x / s, a.y / s) }
    var len: CGFloat { sqrt(x * x + y * y) }
    var norm: CGPoint { let l = max(1e-9, len); return P(x / l, y / l) }
    var perp: CGPoint { P(-y, x) }           // rotate +90° (in y-down: clockwise visually)
    func dot(_ o: CGPoint) -> CGFloat { x * o.x + y * o.y }
    func lerp(_ o: CGPoint, _ t: CGFloat) -> CGPoint { P(x + (o.x - x) * t, y + (o.y - y) * t) }
    func rotated(_ a: CGFloat, about c: CGPoint = .zero) -> CGPoint {
        let d = self - c; let s = sin(a), co = cos(a)
        return c + P(d.x * co - d.y * s, d.x * s + d.y * co)
    }
    func dist(_ o: CGPoint) -> CGFloat { (self - o).len }
}

func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }
func clamp01(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }
func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { let t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
/// Direction for a limb angle measured from straight DOWN, positive swinging toward screen right.
func dirDown(_ degrees: CGFloat) -> CGPoint { let a = deg(degrees); return P(sin(a), cos(a)) }

struct V3 {
    var x, y, z: CGFloat
    init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) { self.x = x; self.y = y; self.z = z }
    static func - (a: V3, b: V3) -> V3 { V3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func + (a: V3, b: V3) -> V3 { V3(a.x + b.x, a.y + b.y, a.z + b.z) }
    func dot(_ o: V3) -> CGFloat { x * o.x + y * o.y + z * o.z }
    func cross(_ o: V3) -> V3 { V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x) }
    var norm: V3 { let l = max(1e-9, sqrt(x * x + y * y + z * z)); return V3(x / l, y / l, z / l) }
}

/// Scene key light (screen upper-left, toward viewer), used for flat facet shading.
let keyLight = V3(-0.55, -0.72, 0.9).norm
let halfVec = (keyLight + V3(0, 0, 1)).norm

// MARK: - Path builders

func buildPath(_ f: (CGMutablePath) -> Void) -> CGPath { let p = CGMutablePath(); f(p); return p }

func circlePath(_ c: CGPoint, _ r: CGFloat) -> CGPath { CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil) }
func ellipsePath(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry), transform: nil)
}
func rotatedEllipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ angle: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
    return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: &t)
}
func rectPath(_ r: CGRect) -> CGPath { CGPath(rect: r, transform: nil) }
func rrectPath(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    let rr = min(rad, min(r.width, r.height) / 2)
    return CGPath(roundedRect: r, cornerWidth: rr, cornerHeight: rr, transform: nil)
}
func polygonPath(_ pts: [CGPoint], closed: Bool = true) -> CGPath {
    buildPath { p in
        guard let f = pts.first else { return }
        p.move(to: f); for q in pts.dropFirst() { p.addLine(to: q) }
        if closed { p.closeSubpath() }
    }
}
/// Catmull-Rom spline through points, converted to cubic Béziers.
func smoothPath(_ pts: [CGPoint], closed: Bool = true, tension: CGFloat = 1) -> CGPath {
    buildPath { p in addSmooth(p, pts, closed: closed, tension: tension, move: true) }
}
func addSmooth(_ p: CGMutablePath, _ pts: [CGPoint], closed: Bool, tension: CGFloat = 1, move: Bool = true) {
    let n = pts.count
    guard n >= 2 else { return }
    if move { p.move(to: pts[0]) } else { p.addLine(to: pts[0]) }
    let segs = closed ? n : n - 1
    for i in 0..<segs {
        let p0 = pts[closed ? (i - 1 + n) % n : max(0, i - 1)]
        let p1 = pts[i]
        let p2 = pts[(i + 1) % n]
        let p3 = pts[closed ? (i + 2) % n : min(n - 1, i + 2)]
        let c1 = p1 + (p2 - p0) * (tension / 6)
        let c2 = p2 - (p3 - p1) * (tension / 6)
        p.addCurve(to: p2, control1: c1, control2: c2)
    }
    if closed { p.closeSubpath() }
}
/// Rounded polygon: each corner replaced by a quadratic arc of radius r.
func roundedPolygon(_ pts: [CGPoint], radius r: CGFloat) -> CGPath {
    buildPath { p in
        let n = pts.count
        for i in 0..<n {
            let a = pts[(i - 1 + n) % n], b = pts[i], c = pts[(i + 1) % n]
            let d1 = (a - b).norm, d2 = (c - b).norm
            let rr = min(r, (a - b).len * 0.45, (c - b).len * 0.45)
            let s = b + d1 * rr, e = b + d2 * rr
            if i == 0 { p.move(to: s) } else { p.addLine(to: s) }
            p.addQuadCurve(to: e, control: b)
        }
        p.closeSubpath()
    }
}
func starPoints(_ c: CGPoint, outer: CGFloat, inner: CGFloat, n: Int = 5, rotation: CGFloat = -.pi / 2) -> [CGPoint] {
    (0..<(2 * n)).map { i in
        let r = i % 2 == 0 ? outer : inner
        let a = rotation + CGFloat(i) * .pi / CGFloat(n)
        return c + P(cos(a) * r, sin(a) * r)
    }
}
/// Tapered stroke along a polyline (widths per point) returned as a filled outline.
func taperedPath(_ pts: [CGPoint], widths: [CGFloat], roundCaps: Bool = true) -> CGPath {
    let n = pts.count
    guard n >= 2 else { return CGMutablePath() }
    var left: [CGPoint] = [], right: [CGPoint] = []
    for i in 0..<n {
        let a = pts[max(0, i - 1)], b = pts[min(n - 1, i + 1)]
        let t = (b - a).norm
        let nrm = t.perp
        left.append(pts[i] + nrm * (widths[i] / 2))
        right.append(pts[i] - nrm * (widths[i] / 2))
    }
    return buildPath { p in
        addSmooth(p, left, closed: false, move: true)
        if roundCaps {
            let e = pts[n - 1], w = widths[n - 1] / 2
            let dir = (pts[n - 1] - pts[n - 2]).norm
            p.addQuadCurve(to: right[n - 1], control: e + dir * (w * 1.3))
        } else { p.addLine(to: right[n - 1]) }
        addSmooth(p, right.reversed(), closed: false, move: false)
        if roundCaps {
            let s = pts[0], w = widths[0] / 2
            let dir = (pts[0] - pts[1]).norm
            p.addQuadCurve(to: left[0], control: s + dir * (w * 1.3))
        }
        p.closeSubpath()
    }
}

// MARK: - Flattening & resampling

func flatten(_ path: CGPath, step: CGFloat = 1) -> [[CGPoint]] {
    var subs: [[CGPoint]] = []
    var cur: [CGPoint] = []
    var last = CGPoint.zero
    var start = CGPoint.zero
    path.applyWithBlock { e in
        let el = e.pointee
        switch el.type {
        case .moveToPoint:
            if cur.count > 1 { subs.append(cur) }
            last = el.points[0]; start = last; cur = [last]
        case .addLineToPoint:
            let q = el.points[0]
            let n = max(1, Int((q - last).len / step))
            for i in 1...n { cur.append(last.lerp(q, CGFloat(i) / CGFloat(n))) }
            last = q
        case .addQuadCurveToPoint:
            let c = el.points[0], q = el.points[1]
            let n = max(2, Int(((c - last).len + (q - c).len) / step))
            for i in 1...n {
                let t = CGFloat(i) / CGFloat(n), u = 1 - t
                cur.append(last * (u * u) + c * (2 * u * t) + q * (t * t))
            }
            last = q
        case .addCurveToPoint:
            let c1 = el.points[0], c2 = el.points[1], q = el.points[2]
            let n = max(3, Int(((c1 - last).len + (c2 - c1).len + (q - c2).len) / step))
            for i in 1...n {
                let t = CGFloat(i) / CGFloat(n), u = 1 - t
                let a = last * (u * u * u) + c1 * (3 * u * u * t)
                cur.append(a + c2 * (3 * u * t * t) + q * (t * t * t))
            }
            last = q
        case .closeSubpath:
            if last.dist(start) > 0.001 { cur.append(start) }
            if cur.count > 1 { subs.append(cur) }
            cur = []; last = start
        @unknown default: break
        }
    }
    if cur.count > 1 { subs.append(cur) }
    return subs
}

/// Evenly resample a closed polyline to n points (by arc length).
func resampleClosed(_ pts0: [CGPoint], _ n: Int) -> [CGPoint] {
    var pts = pts0
    if let f = pts.first, let l = pts.last, f.dist(l) > 1e-6 { pts.append(f) }
    var cum: [CGFloat] = [0]
    for i in 1..<pts.count { cum.append(cum[i - 1] + pts[i].dist(pts[i - 1])) }
    let total = cum.last!
    var out: [CGPoint] = []
    var j = 1
    for k in 0..<n {
        let d = total * CGFloat(k) / CGFloat(n)
        while j < cum.count - 1 && cum[j] < d { j += 1 }
        let seg = max(1e-9, cum[j] - cum[j - 1])
        out.append(pts[j - 1].lerp(pts[j], (d - cum[j - 1]) / seg))
    }
    return out
}

func scalePoints(_ pts: [CGPoint], about c: CGPoint, _ s: CGFloat) -> [CGPoint] { pts.map { c + ($0 - c) * s } }
func scalePoints(_ pts: [CGPoint], about c: CGPoint, sx: CGFloat, sy: CGFloat) -> [CGPoint] {
    pts.map { P(c.x + ($0.x - c.x) * sx, c.y + ($0.y - c.y) * sy) }
}
func centroid(_ pts: [CGPoint]) -> CGPoint { pts.reduce(.zero, +) / CGFloat(max(1, pts.count)) }

extension CGPath {
    func transformed(_ t: CGAffineTransform) -> CGPath { var tt = t; return copy(using: &tt) ?? self }
    func stroked(_ w: CGFloat, cap: CGLineCap = .round, join: CGLineJoin = .round) -> CGPath {
        copy(strokingWithWidth: w, lineCap: cap, lineJoin: join, miterLimit: 4)
    }
    var bbox: CGRect { boundingBoxOfPath }
    var center: CGPoint { P(bbox.midX, bbox.midY) }
}
func combine(_ paths: [CGPath]) -> CGPath { buildPath { p in for q in paths { p.addPath(q) } } }

/// Transform mapping a unit design (centred at 0,0, extent ±1) into a target box.
func fitTransform(center c: CGPoint, scale s: CGFloat) -> CGAffineTransform {
    CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: s, y: s)
}
