// Vell.swift — the hero "Vell", an original adult jester-conductor, built as ONE parametric
// drawing. Face, hat (three unequal points, gold bells), costume and proportions are fixed;
// only pose parameters change between VC04/VC05/VC06/VC37 and the onboarding scenes.
//
// Units: U = head height. Character origin = pelvis centre, y grows downward.
// Shading: 2-tone cel (base + hard terminator on the side away from the upper-left key light),
// a soft core shadow with reflected light at the dark edge, and a thin rim light on the lit edge.
import Foundation
import CoreGraphics

enum VCol {
    static let skin = hex(0xF6CFAF), skinLight = hex(0xFFE8D4), skinShadow = hex(0xD99A7E), skinDeep = hex(0xA9625A)
    static let blush = hex(0xF27684)
    static let hair = hex(0x2E1329), hairLight = hex(0x74406A)
    static let ink = hex(0x1E0A1A)
    static let red = hex(0xC9253F), redLight = hex(0xF45C70), redDark = hex(0x650B22)
    static let plum = hex(0x57256C), plumLight = hex(0x9055AC), plumDark = hex(0x250D31)
    static let glove = hex(0xFFF4DE), gloveShadow = hex(0xD5B998)
    static let ruff = hex(0xFFF7E8), ruffShadow = hex(0xC9A983)
    static let rim = hex(0xFF9CC0)
    static let shoe = hex(0x2C1232), shoeLight = hex(0x6A3A74)
}

/// Four-step cel palette of one material.
struct Tone {
    let light: RGBA, base: RGBA, shade: RGBA, deep: RGBA
    static let plum = Tone(light: VCol.plumLight, base: hex(0x5E2A74), shade: hex(0x32123F), deep: hex(0x1C0824))
    static let red = Tone(light: VCol.redLight, base: hex(0xCF2A45), shade: hex(0x86142D), deep: hex(0x4E0719))
    static let glove = Tone(light: RGBA.white, base: VCol.glove, shade: hex(0xE2C4A0), deep: hex(0xB88E66))
    static let shoe = Tone(light: VCol.shoeLight, base: VCol.shoe, shade: hex(0x1D0A21), deep: hex(0x0C030D))
    static let ruff = Tone(light: RGBA.white, base: VCol.ruff, shade: hex(0xEBDDC4), deep: VCol.ruffShadow)
}

enum HandPose { case open, fist, baton, point, flat }
enum HatStyle { case standard, portrait }

struct ArmPose {
    var upper: CGFloat            // degrees from straight down, + swings toward screen right
    var fore: CGFloat
    var hand: HandPose
    var handAngle: CGFloat? = nil // finger direction (deg from down); default = forearm. Solved automatically for .baton
    var front: Bool = true
    var spread: CGFloat = 0.8     // open hand: finger spread 0…1
    var curl: [CGFloat] = [0, 0, 0] // open hand: index, middle, ring curl 0…1
    var thumb: CGFloat = 0        // thumb swing (deg, + toward the fingers)
    var palm: Bool = true         // palm (true) or back of the glove (false) faces the viewer
    var foreOnTop: Bool = true    // forearm drawn over the upper arm at a sharp elbow
}

struct LegPose {
    var thigh: CGFloat = 0
    var shin: CGFloat = 0
    var toe: CGFloat = 1          // +1 toe points outward (screen side), scale of foot
    var behind: Bool = false      // drawn behind the other leg (crossed-back leg in a bow)
}

struct VellPose {
    var lean: CGFloat = 0         // upper-body roll in the picture plane (deg)
    var squash: CGFloat = 1
    var pitch: CGFloat = 0        // forward bend from the hips (deg): foreshortens the upper body
    var hipTilt: CGFloat = 0      // + lowers the screen-right hip (weight on the screen-left leg)
    var headTilt: CGFloat = 0
    var headShift = CGPoint.zero
    var headPitch: CGFloat = 0    // 0…1 head bowed forward (features lower, more hat visible)
    var look = CGPoint.zero
    var lid: CGFloat = 0.18
    var happyEyes = false
    var browL: CGFloat = 0        // screen-left brow raise (U*0.1 units)
    var browR: CGFloat = 0
    var browInner: CGFloat = 0    // lifts the inner brow ends (kind / caring expression)
    var smile: CGFloat = 1
    var mouthOpen: CGFloat = 0
    var armL = ArmPose(upper: -12, fore: -8, hand: .open)   // screen-left arm (character's right)
    var armR = ArmPose(upper: 12, fore: 8, hand: .baton)    // screen-right arm (character's left)
    var legL = LegPose(thigh: 4, shin: 2, toe: 1)
    var legR = LegPose(thigh: -4, shin: -2, toe: 1)
    var batonAngle: CGFloat = 170 // baton direction on screen (deg from down); the gripping fist is oriented to match
    var batonTilt: CGFloat = 30   // how far the baton leans from the knuckle line toward the fingers (deg)
    var hatSwing: CGFloat = 0     // extra droop of the side points
    var hatDroop: CGFloat = 0     // 0 = perky points, 1 = floppy points hanging beside the face
    var hatStyle: HatStyle = .standard
    var bust = false              // portrait framing: skip legs/tails
}

typealias Keys = [(CGFloat, CGFloat)]

/// Smooth piecewise profile lookup (smoothstep between keys).
func profileAt(_ k: Keys, _ t: CGFloat) -> CGFloat {
    if t <= k[0].0 { return k[0].1 }
    for i in 1..<k.count where t <= k[i].0 {
        let (t0, v0) = k[i - 1], (t1, v1) = k[i]
        let u = (t - t0) / max(1e-6, t1 - t0)
        return v0 + (v1 - v0) * (u * u * (3 - 2 * u))
    }
    return k[k.count - 1].1
}
/// Signed smallest difference a − b in degrees.
func angleDiff(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    var d = (a - b).truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    if d < -180 { d += 360 }
    return d
}
/// Semicircular cap from a to b around centre c0, bulging along d.
func roundCap(_ p: CGMutablePath, _ a: CGPoint, _ b: CGPoint, _ c0: CGPoint, _ d: CGPoint) {
    let r = (a.dist(c0) + b.dist(c0)) / 2
    let apex = c0 + d * r
    let k: CGFloat = 0.5523
    p.addCurve(to: apex, control1: a + d * (r * k), control2: apex + (a - c0).norm * (r * k))
    p.addCurve(to: b, control1: apex + (b - c0).norm * (r * k), control2: b + d * (r * k))
}

struct VellRig {
    let c: Canvas
    let pose: VellPose
    let ow: CGFloat = 0.02        // ink outline half-width (U)

    // MARK: skeleton
    var upperT: CGAffineTransform {
        let pt = deg(pose.pitch)
        return CGAffineTransform(rotationAngle: deg(pose.lean)).scaledBy(x: 1 + 0.07 * sin(pt), y: pose.squash * cos(pt))
    }
    func up(_ p: CGPoint) -> CGPoint { p.applying(upperT) }
    static let headScale: CGFloat = 1.32
    var headCenter: CGPoint { up(P(0, -2.29)) + pose.headShift }
    var headT: CGAffineTransform {
        CGAffineTransform(translationX: headCenter.x, y: headCenter.y).rotated(by: deg(pose.lean + pose.headTilt))
            .scaledBy(x: VellRig.headScale, y: VellRig.headScale)
    }
    func shoulder(_ left: Bool) -> CGPoint { up(P(left ? -0.58 : 0.58, -1.44)) }
    func hip(_ left: Bool) -> CGPoint { P(left ? -0.20 : 0.20, 0.10).rotated(deg(pose.hipTilt)) }

    // MARK: shading helpers
    func inked(_ p: CGPath, width: CGFloat? = nil, _ body: () -> Void) {
        c.stroke(p, VCol.ink, (width ?? ow) * 2)
        body()
    }
    func fabric(_ p: CGPath, light: RGBA, base: RGBA, dark: RGBA, rim: CGFloat = 0.45, extent: CGFloat = 0.55) {
        let bb = p.bbox
        let (a, b) = c.lightAxis(bb, extent: extent)
        c.linear(p, [(0, light), (0.42, base), (1, dark)], a, b)
        let L = c.lightDir()
        let s = min(bb.width, bb.height)
        c.innerShadow(p, dx: L.dx * s * 0.16, dy: L.dy * s * 0.16, blur: s * 0.16, color: dark.darker(0.25).alpha(0.55))
        c.innerShadow(p, dx: -L.dx * s * 0.07, dy: -L.dy * s * 0.07, blur: s * 0.10, color: light.lighter(0.25).alpha(0.40))
        if rim > 0 { c.innerShadow(p, dx: L.dx * 0.028, dy: L.dy * 0.028, blur: 0.018, color: VCol.rim.alpha(rim)) }
    }
    func goldTrim(_ p: CGPath, _ w: CGFloat = 0.026) { c.metalRim(p, width: w, metal: .gold) }

    /// 2-tone cel shading. `depth` ≈ the shape's thickness across the light (sets the shadow band width).
    func cel(_ p: CGPath, _ t: Tone, depth w: CGFloat, rim: CGFloat = 0.85, bounce: CGFloat = 0.28, gloss: CGFloat = 0.45, grain: CGFloat = 0) {
        let L = c.lightDir()
        c.fill(p, t.base)
        if gloss > 0 {
            let (a, b) = c.lightAxis(p.bbox, extent: 0.55)
            c.linear(p, [(0, t.light.alpha(gloss)), (0.45, t.light.alpha(0)), (1, t.light.alpha(0))], a, b)
        }
        // hard terminator: the outline shifted toward the light leaves a crescent on the far side
        c.innerShadow(p, dx: L.dx * w * 0.46, dy: L.dy * w * 0.46, blur: w * 0.012, color: t.shade)
        // core shadow and reflected light at the dark edge
        c.innerShadow(p, dx: L.dx * w * 0.15, dy: L.dy * w * 0.15, blur: w * 0.09, color: t.deep.alpha(0.45))
        if bounce > 0 { c.innerShadow(p, dx: L.dx * 0.02, dy: L.dy * 0.02, blur: 0.012, color: VCol.rim.alpha(bounce)) }
        if grain > 0 { c.fabricGrain(p, alpha: grain) }
        // rim light along the lit (upper-left) edge
        if rim > 0 { c.innerShadow(p, dx: -L.dx * 0.03, dy: -L.dy * 0.03, blur: 0.007, color: t.light.lighter(0.5).alpha(rim)) }
    }

    // MARK: limbs
    struct Limb { let path: CGPath; let pts: [CGPoint]; let hw: [CGFloat] }
    static let armOuter: Keys = [(0, 0.158), (0.14, 0.165), (0.42, 0.13), (0.53, 0.116), (0.65, 0.126), (0.86, 0.098), (1, 0.084)]
    static let armInner: Keys = [(0, 0.138), (0.3, 0.14), (0.5, 0.106), (0.56, 0.102), (0.67, 0.114), (1, 0.078)]
    static let legOuter: Keys = [(0, 0.215), (0.2, 0.205), (0.44, 0.146), (0.5, 0.132), (0.62, 0.146), (0.78, 0.114), (1, 0.074)]
    static let legInner: Keys = [(0, 0.19), (0.22, 0.17), (0.44, 0.124), (0.5, 0.114), (0.65, 0.136), (0.82, 0.098), (1, 0.07)]

    /// Tapered, slightly curved limb along a smooth bone chain. Profiles give the half-width on the outer and
    /// inner side as a function of t (0 = root, 1 = tip); `outerLeft` says which side of the chain is outer.
    func limb(_ ctrl: [CGPoint], t0: CGFloat, t1: CGFloat, outer: Keys, inner: Keys, outerLeft: Bool, capStart: Bool = false, capEnd: Bool = false) -> Limb {
        let raw = flatten(smoothPath(ctrl, closed: false), step: 0.01).first ?? ctrl
        var pts: [CGPoint] = []
        for q in raw where pts.last.map({ $0.dist(q) > 0.002 }) ?? true { pts.append(q) }
        let n = pts.count
        var acc: [CGFloat] = [0]
        for i in 1..<n { acc.append(acc[i - 1] + pts[i].dist(pts[i - 1])) }
        let total = max(1e-6, acc[n - 1])
        var lf: [CGPoint] = [], rt: [CGPoint] = [], hw: [CGFloat] = []
        for i in 0..<n {
            let t = t0 + (t1 - t0) * acc[i] / total
            let nl = (pts[min(n - 1, i + 1)] - pts[max(0, i - 1)]).norm.perp
            let hl = profileAt(outerLeft ? outer : inner, t), hr = profileAt(outerLeft ? inner : outer, t)
            lf.append(pts[i] + nl * hl); rt.append(pts[i] - nl * hr); hw.append((hl + hr) / 2)
        }
        let path = buildPath { p in
            p.move(to: lf[0])
            for q in lf.dropFirst() { p.addLine(to: q) }
            if capEnd { roundCap(p, lf[n - 1], rt[n - 1], pts[n - 1], (pts[n - 1] - pts[n - 2]).norm) } else { p.addLine(to: rt[n - 1]) }
            for q in rt.reversed().dropFirst() { p.addLine(to: q) }
            if capStart { roundCap(p, rt[0], lf[0], pts[0], (pts[0] - pts[1]).norm) }
            p.closeSubpath()
        }
        return Limb(path: path, pts: pts, hw: hw)
    }

    // MARK: entry point
    func draw() {
        let backArms = [(true, pose.armL), (false, pose.armR)].filter { !$0.1.front }
        let frontArms = [(true, pose.armL), (false, pose.armR)].filter { $0.1.front }
        if !pose.bust {
            tails()
            for (l, a) in backArms { drawArm(left: l, a) }
            if pose.legR.behind && !pose.legL.behind {
                leg(left: false, pose.legR); leg(left: true, pose.legL)
            } else {
                leg(left: true, pose.legL); leg(left: false, pose.legR)
            }
            breeches()
        } else {
            for (l, a) in backArms { drawArm(left: l, a) }
        }
        c.transform(upperT) { torso() }
        neckAndCollar()
        // in a bow the lowered head is nearer the viewer than the shoulders, so it overlaps the arms
        let headInFront = pose.headPitch > 0.5
        if headInFront { for (l, a) in frontArms { drawArm(left: l, a) } }
        c.transform(headT) {
            head()
            c.transform(CGAffineTransform(translationX: 0, y: 0.06 * pose.headPitch)) { hat() }
        }
        if !headInFront { for (l, a) in frontArms { drawArm(left: l, a) } }
    }

    // MARK: legs
    func leg(left: Bool, _ lp: LegPose) {
        let side: CGFloat = left ? -1 : 1
        let h = hip(left)
        let dt = dirDown(lp.thigh), ds = dirDown(lp.shin)
        let knee = h + dt * 1.13
        let ankle = knee + ds * 1.13
        let o: CGFloat = left ? 1 : -1
        let m1 = h.lerp(knee, 0.5) + dt.perp * (0.03 * o)
        let m2 = knee.lerp(ankle, 0.5) + ds.perp * (0.012 * o)
        shoe(at: ankle, side: side * lp.toe)
        let tone: Tone = left ? .red : .plum
        let lb = limb([h, m1, knee, m2, ankle], t0: 0, t1: 1, outer: Self.legOuter, inner: Self.legInner, outerLeft: left)
        inked(lb.path) { cel(lb.path, tone, depth: 0.30, grain: 0.05) }
        c.clip(lb.path) {
            // kneecap: soft light on the lit side and a small shade crescent below it
            let L = c.lightDir()
            c.blob(knee + P(L.dx, L.dy) * 0.045 - ds * 0.03, rx: 0.075, ry: 0.06, color: tone.light.alpha(0.5))
            let kc = knee + ds * 0.01
            c.stroke(buildPath { p in p.move(to: kc + ds.perp * 0.055); p.addQuadCurve(to: kc - ds.perp * 0.055, control: kc + ds * 0.05) }, tone.shade.alpha(0.8), 0.016)
            // gold garter band just below the knee
            let g = knee + ds * 0.15
            let n = ds.perp
            let band = buildPath { p in
                p.move(to: g + n * 0.2 - ds * 0.036); p.addQuadCurve(to: g - n * 0.2 - ds * 0.036, control: g + ds * 0.01)
                p.addLine(to: g - n * 0.2 + ds * 0.036); p.addQuadCurve(to: g + n * 0.2 + ds * 0.036, control: g + ds * 0.08)
                p.closeSubpath()
            }
            c.metalFill(band, .gold)
            c.stroke(band, VCol.ink.alpha(0.85), 0.018)
        }
    }

    func shoe(at ankle: CGPoint, side: CGFloat) {
        let s = side >= 0 ? CGFloat(1) : CGFloat(-1)
        let k = abs(side)
        let heel = ankle + P(-0.10 * s, 0.13)
        let sole = buildPath { p in
            p.move(to: ankle + P(-0.09 * s, -0.04))
            p.addCurve(to: heel, control1: ankle + P(-0.14 * s, 0.02), control2: ankle + P(-0.14 * s, 0.12))
            p.addCurve(to: ankle + P(0.34 * s * k, 0.13), control1: ankle + P(0.05 * s, 0.16), control2: ankle + P(0.22 * s * k, 0.16))
            p.addCurve(to: ankle + P(0.50 * s * k, -0.10), control1: ankle + P(0.46 * s * k, 0.10), control2: ankle + P(0.54 * s * k, 0.0))
            p.addCurve(to: ankle + P(0.38 * s * k, -0.02), control1: ankle + P(0.46 * s * k, -0.14), control2: ankle + P(0.40 * s * k, -0.10))
            p.addCurve(to: ankle + P(0.08 * s, -0.06), control1: ankle + P(0.30 * s * k, 0.04), control2: ankle + P(0.16 * s, -0.02))
            p.closeSubpath()
        }
        inked(sole) { cel(sole, .shoe, depth: 0.2, rim: 0.9, bounce: 0.35) }
        // gold collar at the ankle
        let collar = buildPath { p in p.move(to: ankle + P(-0.10 * s, -0.035)); p.addQuadCurve(to: ankle + P(0.10 * s, -0.045), control: ankle + P(0, 0.02)) }
        c.stroke(collar, VCol.ink, 0.05)
        goldTrim(collar, 0.028)
        // little gold bell hanging from the curled toe
        bell(at: ankle + P(0.515 * s * k, -0.075), r: 0.062)
    }

    /// Puffed plum trunk hose over the hips with lighter slashed panes (keeps the red reserved for the lining).
    func breeches() {
        for left in [true, false] {
            let lp = left ? pose.legL : pose.legR
            let h = hip(left)
            let d = dirDown(lp.thigh)
            let nOut = left ? d.perp : d.perp * -1
            func Q(_ a: CGFloat, _ b: CGFloat) -> CGPoint { h + d * a + nOut * b }
            let shape = smoothPath([Q(-0.14, -0.17), Q(-0.14, 0.11), Q(-0.02, 0.30), Q(0.24, 0.35), Q(0.50, 0.29), Q(0.63, 0.19),
                                    Q(0.67, 0.02), Q(0.64, -0.14), Q(0.50, -0.21), Q(0.18, -0.23)], closed: true, tension: 0.9)
            let tone = Tone.plum
            let pane = Tone(light: hex(0xB57ACC), base: hex(0x7A3F92), shade: hex(0x4A1D5C), deep: hex(0x2A0E34))
            inked(shape) {
                cel(shape, tone, depth: 0.42, grain: 0.06)
                c.clip(shape) {
                    // two contrasting panes following the puff
                    for b in [CGFloat(0.13), -0.06] {
                        let strip = taperedPath([Q(-0.10, b * 0.9), Q(0.14, b * 1.3), Q(0.40, b * 1.25), Q(0.64, b * 0.8)], widths: [0.03, 0.11, 0.10, 0.03])
                        c.stroke(strip, VCol.ink.alpha(0.8), 0.022)
                        cel(strip, pane, depth: 0.1, rim: 0.6, bounce: 0, gloss: 0.3)
                    }
                    // gathered folds toward the band
                    for b in [CGFloat(0.24), 0.04, -0.14] {
                        c.stroke(smoothPath([Q(0.44, b * 1.05), Q(0.56, b * 0.9), Q(0.64, b * 0.72)], closed: false), tone.deep.alpha(0.55), 0.016)
                    }
                }
            }
            // gold band gathering the puff
            let band = taperedPath([Q(0.62, -0.17), Q(0.655, 0.02), Q(0.62, 0.20)], widths: [0.07, 0.075, 0.07], roundCaps: false)
            inked(band, width: 0.014) { c.metalFill(band, .gold) }
        }
    }

    // MARK: tails & torso
    func tails() {
        c.transform(upperT) {
            for side in [CGFloat(-1), 1] {
                let tail = buildPath { p in
                    p.move(to: P(0.18 * side, -0.40))
                    p.addCurve(to: P(0.64 * side, 1.36), control1: P(0.52 * side, 0.06), control2: P(0.70 * side, 0.80))
                    p.addCurve(to: P(0.30 * side, 0.30), control1: P(0.48 * side, 1.00), control2: P(0.34 * side, 0.70))
                    p.closeSubpath()
                }
                inked(tail) { cel(tail, .plum, depth: 0.36, grain: 0.06) }
                // crimson lining along the inner edge
                let lining = buildPath { p in
                    p.move(to: P(0.64 * side, 1.36))
                    p.addCurve(to: P(0.30 * side, 0.30), control1: P(0.48 * side, 1.00), control2: P(0.34 * side, 0.70))
                    p.addCurve(to: P(0.57 * side, 1.16), control1: P(0.43 * side, 0.64), control2: P(0.51 * side, 0.94))
                    p.closeSubpath()
                }
                c.clip(tail) { cel(lining, .red, depth: 0.1, rim: 0.5, bounce: 0, gloss: 0.3) }
                goldTrim(tail, 0.018)
            }
        }
    }

    /// Hem geometry: tips and valleys of the jester points (x, y).
    static let hemTips: [CGPoint] = [P(-0.47, 0.34), P(-0.235, 0.42), P(0, 0.46), P(0.235, 0.42), P(0.47, 0.34)]
    static let hemValleys: [CGPoint] = [P(-0.35, 0.08), P(-0.115, 0.12), P(0.115, 0.12), P(0.35, 0.08)]

    func torso() {
        let tips = Self.hemTips, vals = Self.hemValleys
        // crimson under-layer points (the lining side of the skirt) peeking between the plum points
        let under = buildPath { p in
            p.move(to: P(-0.50, -0.10))
            for (i, xv) in [CGFloat(-0.35), -0.115, 0.115, 0.35].enumerated() {
                p.addLine(to: P(xv - 0.10, 0.05))
                p.addLine(to: P(xv, i == 0 || i == 3 ? 0.36 : 0.39))
                p.addLine(to: P(xv + 0.10, 0.05))
            }
            p.addLine(to: P(0.50, -0.10)); p.closeSubpath()
        }
        inked(under) { cel(under, .red, depth: 0.3, rim: 0.4, gloss: 0.3) }
        // doublet body: fitted chest, belted waist, flared skirt with five jester points
        let half: [CGPoint] = [P(0.17, -1.60), P(0.52, -1.54), P(0.66, -1.40), P(0.60, -1.14), P(0.50, -0.86), P(0.40, -0.60), P(0.41, -0.46), P(0.49, -0.24), P(0.54, -0.02)]
        let body = buildPath { p in
            p.move(to: P(0, -1.63))
            addSmooth(p, [P(0, -1.63)] + half, closed: false, tension: 0.8, move: false)
            // hem (right to left), slightly bowed edges
            var prev = P(0.54, -0.02)
            let seq: [CGPoint] = [tips[4], vals[3], tips[3], vals[2], tips[2], vals[1], tips[1], vals[0], tips[0], P(-0.54, -0.02)]
            for q in seq {
                let m = prev.lerp(q, 0.5) + (q - prev).norm.perp * 0.012
                p.addQuadCurve(to: q, control: m)
                prev = q
            }
            addSmooth(p, half.reversed().map { P(-$0.x, $0.y) } + [P(0, -1.63)], closed: false, tension: 0.8, move: false)
            p.closeSubpath()
        }
        inked(body) { cel(body, .plum, depth: 1.0, rim: 0.8, bounce: 0.3, gloss: 0.5, grain: 0.08) }
        c.clip(body) {
            // chest tension folds from under the arms toward the belt
            for s in [CGFloat(-1), 1] {
                let f1 = smoothPath([P(0.56 * s, -1.12), P(0.40 * s, -0.94), P(0.26 * s, -0.66)], closed: false)
                let f2 = smoothPath([P(0.50 * s, -0.92), P(0.40 * s, -0.78), P(0.34 * s, -0.62)], closed: false)
                for f in [f1, f2] {
                    c.stroke(f, Tone.plum.deep.alpha(0.55), 0.026)
                    c.stroke(f.transformed(CGAffineTransform(translationX: -0.018, y: -0.01)), VCol.plumLight.alpha(0.45), 0.012)
                }
            }
            // skirt pleats: dark creases into each valley, light ridges down each point
            for v in vals {
                let top = P(v.x * 0.86, -0.42)
                c.stroke(smoothPath([top, top.lerp(v, 0.5) + P(0.01, 0), v], closed: false), Tone.plum.deep.alpha(0.6), 0.03)
            }
            for t in tips {
                let top = P(t.x * 0.8, -0.42)
                c.stroke(smoothPath([top + P(-0.03, 0), top.lerp(t, 0.5) + P(-0.035, 0), t + P(-0.02, -0.1)], closed: false), VCol.plumLight.alpha(0.28), 0.018)
            }
            // red lining turning out along the outer edge of each point
            for (i, t) in tips.enumerated() {
                let outerV: CGPoint = t.x < -0.01 ? (i > 0 ? vals[i - 1] : P(-0.54, -0.02)) : (i < vals.count ? vals[i] : P(0.54, -0.02))
                let e = outerV - t
                let inward = P(-e.y, e.x).norm * (t.x < -0.01 ? 1 : -1)
                let sliver = buildPath { p in
                    p.move(to: t)
                    p.addLine(to: t + e * 0.7)
                    p.addQuadCurve(to: t + inward * 0.015, control: t + e * 0.32 + inward * 0.11)
                    p.closeSubpath()
                }
                c.stroke(sliver, VCol.ink.alpha(0.7), 0.014)
                cel(sliver, .red, depth: 0.06, rim: 0.7, bounce: 0, gloss: 0.4)
            }
        }
        // gold trim along the hem
        let hem = buildPath { p in
            p.move(to: P(-0.54, -0.02))
            for q in [tips[0], vals[0], tips[1], vals[1], tips[2], vals[2], tips[3], vals[3], tips[4], P(0.54, -0.02)] { p.addLine(to: q) }
        }
        c.clip(body) { c.metalRim(hem, width: 0.05, metal: .gold) }
        // crimson V plastron with gold piping and buttons
        let vee = buildPath { p in
            p.move(to: P(-0.20, -1.60))
            p.addQuadCurve(to: P(0, -0.58), control: P(-0.13, -0.86))
            p.addQuadCurve(to: P(0.20, -1.60), control: P(0.13, -0.86))
            p.closeSubpath()
        }
        cel(vee, .red, depth: 0.3, rim: 0.6, bounce: 0.2, gloss: 0.4, grain: 0.05)
        goldTrim(vee, 0.024)
        for (i, y) in [CGFloat(-1.30), -1.06, -0.82].enumerated() {
            let b = circlePath(P(0, y), 0.046 - CGFloat(i) * 0.004)
            inked(b, width: 0.012) { c.glossy(b, light: hex(0xFFF6CC), base: hex(0xE6AE4C), dark: hex(0x6E3E10), spec: 1) }
        }
        // gold belt with a small buckle
        c.clip(body) {
            let belt = rectPath(CGRect(x: -0.7, y: -0.585, width: 1.4, height: 0.105))
            c.metalFill(belt, .gold, bbox: CGRect(x: -0.45, y: -0.7, width: 0.9, height: 0.3))
            c.stroke(polygonPath([P(-0.7, -0.585), P(0.7, -0.585)], closed: false), VCol.ink, 0.022)
            c.stroke(polygonPath([P(-0.7, -0.48), P(0.7, -0.48)], closed: false), VCol.ink, 0.022)
            c.stroke(polygonPath([P(-0.7, -0.565), P(0.7, -0.565)], closed: false), hex(0xFFF3C8, 0.8), 0.01)
        }
        let buckle = rrectPath(CGRect(x: -0.085, y: -0.605, width: 0.17, height: 0.145), 0.03)
        inked(buckle, width: 0.014) { c.metalPlate(buckle, .gold, bevel: 0.022) }
        let gem = polygonPath([P(0, -0.575), P(0.032, -0.532), P(0, -0.49), P(-0.032, -0.532)])
        c.stroke(gem, VCol.ink, 0.012)
        c.linear(gem, [(0, hex(0xFF7A8C)), (0.5, hex(0xC8102F)), (1, hex(0x4A0414))], P(-0.02, -0.57), P(0.02, -0.5))
        // small gold bells on the outer points and the centre point
        for i in [0, 4] { bell(at: tips[i] + P(0, 0.045), r: 0.048) }
    }

    // MARK: neck & collar
    func neckAndCollar() {
        let hc = headCenter
        let neckTop = hc + P(0, 0.30 * VellRig.headScale).rotated(deg(pose.lean + pose.headTilt))
        let base = up(P(0, -1.52))
        let neck = taperedPath([neckTop, base], widths: [0.27, 0.31], roundCaps: false)
        c.transform(upperT) { ruff(front: false) }
        inked(neck) {
            c.linear(neck, [(0, VCol.skinDeep), (0.5, VCol.skinShadow), (1, VCol.skinShadow.darker(0.1))], neckTop, base)
        }
        c.transform(upperT) { ruff(front: true) }
    }

    func ruff(front: Bool) {
        let cy: CGFloat = -1.58
        for layer in 0..<2 {
            let rx: CGFloat = layer == 0 ? 0.66 : 0.56, ry: CGFloat = layer == 0 ? 0.25 : 0.20
            let irx: CGFloat = 0.15, iry: CGFloat = 0.05
            let n = layer == 0 ? 18 : 16
            let off: CGFloat = layer == 0 ? 0.5 : 0
            let yc = cy + (layer == 0 ? -0.01 : 0.04)
            var lobes: [(CGPath, CGFloat)] = []
            for i in 0..<n {
                let a0 = (CGFloat(i) + off) / CGFloat(n) * 2 * .pi, a1 = (CGFloat(i + 1) + off) / CGFloat(n) * 2 * .pi
                let am = (a0 + a1) / 2
                if (sin(am) > 0) != front { continue }
                func E(_ a: CGFloat, _ sx: CGFloat, _ sy: CGFloat) -> CGPoint { P(cos(a) * sx, yc + sin(a) * sy) }
                let lobe = buildPath { p in
                    p.move(to: E(a0, irx, iry))
                    p.addLine(to: E(a0, rx, ry))
                    p.addCurve(to: E(a1, rx, ry), control1: E(a0 + (a1 - a0) * 0.1, rx * 1.16, ry * 1.22), control2: E(a1 - (a1 - a0) * 0.1, rx * 1.16, ry * 1.22))
                    p.addLine(to: E(a1, irx, iry))
                    p.closeSubpath()
                }
                lobes.append((lobe, am))
            }
            let order = lobes.sorted { sin($0.1) < sin($1.1) }
            for (lobe, am) in order {
                let facing = (sin(am) + 1) / 2        // 0 = back, 1 = front
                let lit = clamp01(0.5 - 0.45 * cos(am + 0.6))
                let baseC = VCol.ruff.mix(VCol.ruffShadow, 0.55 - 0.45 * facing)
                let outer = P(cos(am) * rx, yc + sin(am) * ry)
                c.stroke(lobe, VCol.ink.alpha(0.9), 0.024)
                c.linear(lobe, [(0, VCol.ruffShadow.darker(0.15)), (0.55, baseC), (1, baseC.lighter(0.5 * lit))], P(0, yc), outer)
                c.clip(lobe) {
                    c.stroke(polygonPath([P(cos(am) * irx, yc + sin(am) * iry), P(cos(am) * rx * 1.1, yc + sin(am) * ry * 1.1)], closed: false), VCol.ruffShadow.alpha(0.45), 0.016)
                }
            }
            if layer == 1 && front {
                c.blob(P(0.02, yc + 0.01), rx: 0.30, ry: 0.09, color: hex(0x7A4A40, 0.35))
            }
        }
    }

    // MARK: head
    func head() {
        let ear = { (s: CGFloat) in
            let e = rotatedEllipse(P(0.425 * s, 0.07), 0.08, 0.12, deg(-12 * s))
            self.inked(e) {
                self.c.fill(e, VCol.skin)
                self.c.radialEllipse(e, [(0, VCol.skinLight), (1, VCol.skinShadow)], center: P(0.41 * s, 0.04), rx: 0.1, ry: 0.13)
                self.c.fill(rotatedEllipse(P(0.44 * s, 0.08), 0.035, 0.07, deg(-12 * s)), VCol.skinDeep.alpha(0.55))
            }
        }
        ear(-1); ear(1)
        let face = smoothPath([P(0, -0.56), P(0.34, -0.49), P(0.425, -0.20), P(0.415, 0.05), P(0.36, 0.26), P(0.25, 0.44), P(0.10, 0.565), P(0, 0.585),
                               P(-0.10, 0.565), P(-0.25, 0.44), P(-0.36, 0.26), P(-0.415, 0.05), P(-0.425, -0.20), P(-0.34, -0.49)], closed: true, tension: 1)
        inked(face) {
            c.radial(face, [(0, VCol.skinLight), (0.55, VCol.skin), (1, VCol.skinShadow)], center: P(0.06, 0.02), radius: 0.62, focus: P(-0.16, -0.12))
            let L = c.lightDir()
            c.innerShadow(face, dx: L.dx * 0.10, dy: L.dy * 0.10, blur: 0.09, color: VCol.skinShadow.darker(0.1).alpha(0.75))
            c.innerShadow(face, dx: L.dx * 0.025, dy: L.dy * 0.025, blur: 0.02, color: VCol.rim.alpha(0.45))
            // hat shadow across the forehead
            c.clip(face) { c.blob(P(0, -0.42), rx: 0.55, ry: 0.16, color: VCol.skinDeep.alpha(0.6)) }
        }
        hair()
        // features (lowered and slightly compressed when the head is bowed forward)
        let hp = pose.headPitch
        c.transform(CGAffineTransform(translationX: 0, y: 0.075 * hp + 0.1).scaledBy(x: 1, y: 1 - 0.09 * hp).translatedBy(x: 0, y: -0.1)) {
            // cheeks
            for s in [CGFloat(-1), 1] { c.blob(P(0.235 * s, 0.215), rx: 0.085, ry: 0.05, color: VCol.blush.alpha(0.42)) }
            eyes()
            brows()
            nose()
            mustacheAndMouth()
            // chin highlight
            c.blob(P(-0.03, 0.50), rx: 0.06, ry: 0.025, color: VCol.skinLight.alpha(0.6))
        }
    }

    func hair() {
        // hair mass under the hat with neat sideburns, then a short wavy fringe of sweeping locks
        let mass: [CGPoint] = [
            P(-0.47, -0.46), P(-0.455, -0.26), P(-0.44, -0.05), P(-0.39, -0.10), P(-0.38, -0.27),
            P(-0.20, -0.31), P(0.0, -0.32), P(0.20, -0.31),
            P(0.38, -0.27), P(0.39, -0.10), P(0.44, -0.05), P(0.455, -0.26), P(0.47, -0.46), P(0, -0.52),
        ]
        let massP = smoothPath(mass, closed: true, tension: 0.85)
        let hairFill = { (p: CGPath) in self.fabric(p, light: VCol.hairLight, base: VCol.hair, dark: hex(0x12050E), rim: 0.25, extent: 0.5) }
        inked(massP, width: 0.016) {
            hairFill(massP)
            c.clip(massP) { c.stroke(smoothPath([P(-0.43, -0.40), P(-0.425, -0.22), P(-0.43, -0.10)], closed: false), VCol.hairLight.alpha(0.5), 0.014) }
        }
        let locks: [(CGPoint, CGPoint, CGFloat)] = [
            (P(-0.37, -0.40), P(-0.28, -0.175), 0.20),
            (P(0.10, -0.41), P(0.225, -0.18), 0.21),
            (P(-0.14, -0.42), P(-0.02, -0.16), 0.23),
            (P(0.31, -0.39), P(0.37, -0.215), 0.13),
        ]
        for (root, tip, w) in locks {
            let mid = root.lerp(tip, 0.55) + P(-0.035, 0.0)
            let spine = [root, mid, tip, tip + P(0.045, -0.035)]
            let lock = taperedPath(spine, widths: [w, w * 0.8, w * 0.35, w * 0.12])
            inked(lock, width: 0.014) {
                hairFill(lock)
                c.clip(lock) { c.stroke(smoothPath([root.lerp(mid, 0.3) + P(-0.02, 0), mid + P(-0.015, 0.01), tip.lerp(mid, 0.3)], closed: false), VCol.hairLight.lighter(0.3).alpha(0.6), 0.016) }
            }
        }
    }

    func eyes() {
        for s in [CGFloat(-1), 1] {
            let ec = P(0.168 * s, 0.03)
            if pose.happyEyes {
                let arc = smoothPath([ec + P(-0.085, 0.03), ec + P(0, -0.045), ec + P(0.085, 0.03)], closed: false)
                c.stroke(arc, VCol.ink, 0.034)
                // lash flick
                c.stroke(polygonPath([ec + P(0.083 * s, 0.028), ec + P(0.115 * s, 0.0)], closed: false), VCol.ink, 0.018)
                continue
            }
            let white = rotatedEllipse(ec, 0.090, 0.112, deg(5 * s))
            c.fill(white, VCol.ink)
            let whiteIn = rotatedEllipse(ec, 0.081, 0.103, deg(5 * s))
            c.radialEllipse(whiteIn, [(0, hex(0xFFFFFF)), (0.8, hex(0xF4ECF4)), (1, hex(0xD8C8D8))], center: ec + P(-0.01, 0.01), rx: 0.08, ry: 0.1)
            c.clip(whiteIn) {
                let ic = ec + P(pose.look.x * 0.025, 0.012 + pose.look.y * 0.02)
                let iris = circlePath(ic, 0.070)
                c.radial(iris, [(0, hex(0xE8AC58)), (0.55, hex(0xA8622A)), (1, hex(0x3E1808))], center: ic, radius: 0.070, focus: ic + P(0, 0.025))
                c.stroke(iris, hex(0x2A0E06), 0.012)
                c.fill(circlePath(ic + P(0.002, 0.004), 0.034), hex(0x160608))
                // lid shadow on the eyeball
                c.linear(whiteIn, [(0, hex(0x5A2A40, 0.40)), (0.40, hex(0x5A2A40, 0))], ec + P(0, -0.10), ec + P(0, 0.06))
                c.fill(circlePath(ic + P(-0.024, -0.026), 0.022), RGBA.white)
                c.fill(circlePath(ic + P(0.026, 0.026), 0.011), RGBA.white.alpha(0.9))
                // upper lid (skin) according to lid amount
                let lidY = ec.y - 0.10 + pose.lid * 0.16
                let lidP = buildPath { p in
                    p.move(to: ec + P(-0.12, -0.2)); p.addLine(to: ec + P(0.12, -0.2))
                    p.addLine(to: P(ec.x + 0.12, lidY + 0.012 * s))
                    p.addQuadCurve(to: P(ec.x - 0.12, lidY - 0.012 * s), control: P(ec.x, lidY - 0.04))
                    p.closeSubpath()
                }
                c.fill(lidP, VCol.skin.mix(VCol.skinShadow, 0.35))
            }
            // lash line along the lid edge, with an outer flick
            let lidY = ec.y - 0.10 + pose.lid * 0.16
            let lash = buildPath { p in
                p.move(to: P(ec.x - 0.082 * s, lidY + 0.035 - 0.012 * s * s))
                p.addQuadCurve(to: P(ec.x + 0.080 * s, lidY + 0.02), control: P(ec.x, lidY - 0.035))
                p.addLine(to: P(ec.x + 0.108 * s, lidY + 0.012))
            }
            c.stroke(lash, VCol.ink, 0.026)
            // soft lower lid line
            c.stroke(buildPath { p in p.addArc(center: ec + P(0, -0.02), radius: 0.10, startAngle: deg(60), endAngle: deg(120), clockwise: false) }, VCol.skinDeep.alpha(0.6), 0.008)
        }
    }

    func brows() {
        for s in [CGFloat(-1), 1] {
            let raise = (s < 0 ? pose.browL : pose.browR) * 0.1
            let bi = pose.browInner * 0.035
            let b = [P(0.075 * s, -0.172 - raise * 0.9 - bi), P(0.17 * s, -0.200 - raise - bi * 0.35), P(0.275 * s, -0.170 - raise * 0.7 + bi * 0.3)]
            let path = taperedPath(b, widths: [0.050, 0.044, 0.016])
            c.fill(path, VCol.hair)
            c.clip(path) { c.stroke(smoothPath(b.map { $0 + P(-0.005, -0.012) }, closed: false), VCol.hairLight.alpha(0.6), 0.012) }
        }
    }

    func nose() {
        let n = buildPath { p in
            p.move(to: P(0.012, 0.07))
            p.addCurve(to: P(0.045, 0.215), control1: P(0.03, 0.12), control2: P(0.058, 0.18))
            p.addCurve(to: P(-0.03, 0.225), control1: P(0.03, 0.245), control2: P(-0.01, 0.245))
        }
        c.blob(P(0.03, 0.225), rx: 0.06, ry: 0.03, color: VCol.skinDeep.alpha(0.45))
        c.stroke(n, VCol.skinDeep.darker(0.1), 0.014)
        c.blob(P(-0.004, 0.185), rx: 0.024, ry: 0.018, color: RGBA.white.alpha(0.55))
    }

    func mustacheAndMouth() {
        // mouth
        let sm = pose.smile
        let mL = P(-0.11, 0.345 - 0.012 * sm), mR = P(0.11, 0.345 - 0.012 * sm)
        let mC = P(0, 0.372 + 0.02 * sm)
        if pose.mouthOpen > 0 {
            let open = pose.mouthOpen
            let m = buildPath { p in
                p.move(to: mL)
                p.addQuadCurve(to: mR, control: P(0, mC.y - 0.02))
                p.addQuadCurve(to: mL, control: P(0, mC.y + 0.09 * open))
                p.closeSubpath()
            }
            c.fill(m, hex(0x5E0F1E))
            c.clip(m) {
                c.fill(ellipsePath(P(0.0, mC.y + 0.06 * open), 0.07, 0.04), hex(0xE06A78))
                c.fill(buildPath { p in
                    p.move(to: mL + P(0.01, -0.02)); p.addQuadCurve(to: mR + P(-0.01, -0.02), control: P(0, mC.y - 0.035))
                    p.addQuadCurve(to: mL + P(0.01, -0.02), control: P(0, mC.y + 0.02))
                }, hex(0xFFF8F0))
            }
            c.stroke(m, VCol.ink.mix(hex(0x5E0F1E), 0.3), 0.014)
        } else {
            let m = smoothPath([mL, P(-0.05, mC.y - 0.004), mC, P(0.05, mC.y - 0.004), mR], closed: false, tension: 0.8)
            c.stroke(m, hex(0x5A1822), 0.018)
            c.blob(P(0, mC.y + 0.035), rx: 0.05, ry: 0.016, color: hex(0xD8706E, 0.45))
        }
        // dimple curls at mouth corners
        for (pt, s) in [(mL, CGFloat(-1)), (mR, CGFloat(1))] {
            c.stroke(buildPath { p in p.move(to: pt + P(-0.012 * s, 0.012)); p.addQuadCurve(to: pt + P(0.012 * s, -0.022), control: pt + P(0.016 * s, 0.006)) }, hex(0x5A1822, 0.8), 0.012)
        }
        // small curled mustache line
        for s in [CGFloat(-1), 1] {
            let pts = [P(0.010 * s, 0.272), P(0.058 * s, 0.284), P(0.104 * s, 0.276), P(0.136 * s, 0.252), P(0.138 * s, 0.226), P(0.119 * s, 0.228)]
            let m = taperedPath(pts, widths: [0.030, 0.027, 0.019, 0.012, 0.008, 0.005])
            c.fill(m, VCol.hair)
            c.clip(m) { c.stroke(smoothPath(pts.map { $0 + P(0, -0.008) }, closed: false), VCol.hairLight.alpha(0.55), 0.008) }
        }
    }

    // MARK: hat — three unequal points (red / plum / red), gold band, gold bells
    struct HatPoint { let spine: [CGPoint]; let widths: [CGFloat]; let red: Bool }
    var hatPoints: [HatPoint] {
        if pose.hatStyle == .portrait {
            // tight bust framing: side points flop down over the ears (left longer), centre point folds right
            return [
                HatPoint(spine: [P(-0.26, -0.49), P(-0.46, -0.58), P(-0.60, -0.44), P(-0.64, -0.16), P(-0.60, 0.10)],
                         widths: [0.50, 0.37, 0.25, 0.15, 0.05], red: true),
                HatPoint(spine: [P(0.26, -0.49), P(0.45, -0.56), P(0.58, -0.42), P(0.61, -0.20), P(0.57, 0.0)],
                         widths: [0.50, 0.35, 0.23, 0.14, 0.05], red: true),
                HatPoint(spine: [P(0.0, -0.46), P(0.03, -0.60), P(0.14, -0.68), P(0.27, -0.70), P(0.34, -0.695)],
                         widths: [0.52, 0.30, 0.20, 0.12, 0.05], red: false),
            ]
        }
        let sw = pose.hatSwing
        let d = pose.hatDroop
        func mixS(_ a: [CGPoint], _ b: [CGPoint]) -> [CGPoint] { zip(a, b).map { $0.lerp($1, d) } }
        return [
            HatPoint(spine: mixS([P(-0.27, -0.50), P(-0.42, -0.95), P(-0.80, -1.13), P(-1.10, -0.94 + sw * 0.08), P(-1.20, -0.60 + sw * 0.14)],
                                 [P(-0.27, -0.50), P(-0.44, -0.88), P(-0.74, -0.92), P(-0.90, -0.66), P(-0.88, -0.30)]),
                     widths: [0.56, 0.46, 0.30, 0.16, 0.05], red: true),
            HatPoint(spine: mixS([P(0.27, -0.50), P(0.44, -0.92), P(0.76, -1.05), P(1.00, -0.86 + sw * 0.08), P(1.07, -0.62 + sw * 0.12)],
                                 [P(0.27, -0.50), P(0.46, -0.86), P(0.72, -0.88), P(0.86, -0.64), P(0.84, -0.40)]),
                     widths: [0.56, 0.44, 0.28, 0.14, 0.05], red: true),
            HatPoint(spine: mixS([P(0.0, -0.50), P(0.0, -1.02), P(0.10, -1.40), P(0.34, -1.58 + sw * 0.05), P(0.58, -1.45 + sw * 0.1)],
                                 [P(0.0, -0.50), P(0.03, -0.88), P(0.22, -1.10), P(0.48, -1.10), P(0.62, -0.90)]),
                     widths: [0.58, 0.44, 0.30, 0.16, 0.05], red: false),
        ]
    }

    func hat() {
        for hp in hatPoints {
            let spineS = flatten(smoothPath(hp.spine, closed: false), step: 0.02).first!
            // widths along the resampled spine
            let n = spineS.count
            var ws: [CGFloat] = []
            for i in 0..<n {
                let t = CGFloat(i) / CGFloat(n - 1) * CGFloat(hp.widths.count - 1)
                let i0 = min(hp.widths.count - 2, Int(t))
                ws.append(lerp(hp.widths[i0], hp.widths[i0 + 1], t - CGFloat(i0)))
            }
            let sub = stride(from: 0, to: n, by: max(1, n / 24)).map { $0 } + [n - 1]
            let path = taperedPath(sub.map { spineS[$0] }, widths: sub.map { ws[$0] })
            let (li, ba, da) = hp.red ? (VCol.redLight, VCol.red, VCol.redDark) : (VCol.plumLight, VCol.plum, VCol.plumDark)
            inked(path) {
                fabric(path, light: li, base: ba, dark: da, rim: 0.5, extent: 0.5)
                c.clip(path) {
                    c.fabricGrain(path, alpha: 0.10)
                    // fold creases following the spine
                    let crease = sub.map { spineS[$0] }.enumerated().map { (i, p) -> CGPoint in
                        let a = spineS[max(0, sub[i] - 1)], b = spineS[min(n - 1, sub[i] + 1)]
                        return p + (b - a).norm.perp * (ws[sub[i]] * 0.18)
                    }
                    c.stroke(smoothPath(Array(crease.dropLast(2)), closed: false), da.alpha(0.45), 0.03)
                    let sheen = sub.map { spineS[$0] }.enumerated().map { (i, p) -> CGPoint in
                        let a = spineS[max(0, sub[i] - 1)], b = spineS[min(n - 1, sub[i] + 1)]
                        return p - (b - a).norm.perp * (ws[sub[i]] * 0.22)
                    }
                    c.stroke(smoothPath(Array(sheen.dropLast(2)), closed: false), li.lighter(0.3).alpha(0.5), 0.022)
                }
            }
            goldTrim(path, 0.022)
            let tip = spineS[n - 1]
            let dir = (spineS[n - 1] - spineS[max(0, n - 4)]).norm
            bell(at: tip + dir * 0.07, r: 0.095)
        }
        // band (curves around the head, rounded ends)
        let band = buildPath { p in
            p.move(to: P(-0.50, -0.57))
            p.addQuadCurve(to: P(0.50, -0.57), control: P(0, -0.46))
            p.addQuadCurve(to: P(0.47, -0.40), control: P(0.54, -0.47))
            p.addQuadCurve(to: P(-0.47, -0.40), control: P(0, -0.27))
            p.addQuadCurve(to: P(-0.50, -0.57), control: P(-0.54, -0.47))
            p.closeSubpath()
        }
        inked(band) {
            fabric(band, light: VCol.plumLight, base: VCol.plum, dark: VCol.plumDark, rim: 0.2)
        }
        c.clip(band) {
            let top = buildPath { p in p.move(to: P(-0.52, -0.57)); p.addQuadCurve(to: P(0.52, -0.57), control: P(0, -0.46)) }
            let bot = buildPath { p in p.move(to: P(-0.49, -0.40)); p.addQuadCurve(to: P(0.49, -0.40), control: P(0, -0.27)) }
            c.metalRim(top, width: 0.065, metal: .gold)
            c.metalRim(bot, width: 0.065, metal: .gold)
        }
        // diamond studs on the band
        for (x, sc) in [(CGFloat(-0.29), CGFloat(0.78)), (0, 1.0), (0.29, 0.78)] {
            let y = -0.435 - abs(x) * 0.17
            let d = polygonPath([P(x, y - 0.05 * sc), P(x + 0.035 * sc, y), P(x, y + 0.05 * sc), P(x - 0.035 * sc, y)])
            inked(d, width: 0.01) { c.metalFill(d, .gold) }
        }
    }

    /// Small gold jingle bell.
    func bell(at p: CGPoint, r: CGFloat) {
        let b = circlePath(p, r)
        inked(b, width: 0.016) {
            c.glossy(b, light: hex(0xFFF7CF), base: hex(0xF0B64E), dark: hex(0x7A4410), bounce: hex(0xC0304A, 0.5), spec: 1, specSize: 1.1)
        }
        // slit
        c.stroke(buildPath { q in q.move(to: p + P(-r * 0.55, r * 0.35)); q.addQuadCurve(to: p + P(r * 0.55, r * 0.35), control: p + P(0, r * 0.55)) }, hex(0x3A1A06), r * 0.16)
        c.fill(circlePath(p + P(0, r * 0.62), r * 0.16), hex(0x3A1A06))
    }

    // MARK: arms & hands
    func drawArm(left: Bool, _ a: ArmPose) {
        let s = shoulder(left)
        let du = dirDown(a.upper), df = dirDown(a.fore)
        let elbow = s + du * 0.90
        let wrist = elbow + df * 0.80
        let o: CGFloat = left ? 1 : -1
        let m1 = s.lerp(elbow, 0.5) + du.perp * (0.03 * o)
        let m2 = elbow.lerp(wrist, 0.5) + df.perp * (0.02 * o)
        let bend = abs(angleDiff(a.fore, a.upper))
        var sleeve: CGPath
        if bend < 50 {
            let lb = limb([s, m1, elbow, m2, wrist], t0: 0, t1: 1, outer: Self.armOuter, inner: Self.armInner, outerLeft: left)
            inked(lb.path) { cel(lb.path, .plum, depth: 0.22, grain: 0.06) }
            sleeve = lb.path
        } else {
            let upperL = limb([s, m1, elbow], t0: 0, t1: 0.53, outer: Self.armOuter, inner: Self.armInner, outerLeft: left, capEnd: true)
            let foreL = limb([elbow, m2, wrist], t0: 0.53, t1: 1, outer: Self.armOuter, inner: Self.armInner, outerLeft: left, capStart: true)
            for l in (a.foreOnTop ? [upperL, foreL] : [foreL, upperL]) { inked(l.path) { cel(l.path, .plum, depth: 0.22, grain: 0.06) } }
            sleeve = combine([upperL.path, foreL.path])
        }
        elbowFolds(s, elbow, wrist, bend, clip: sleeve)
        shoulderPuff(s, a.upper)
        handGroup(wrist, a, left: left)
    }

    /// Sleeve wrinkles in the crook of the elbow and a touch of light on the elbow point.
    func elbowFolds(_ s: CGPoint, _ e: CGPoint, _ w: CGPoint, _ bend: CGFloat, clip: CGPath) {
        guard bend > 12 else { return }
        let u = (e - s).norm, v = (w - e).norm
        let cr = u.x * v.y - u.y * v.x
        let crook = (u.perp + v.perp).norm * (cr > 0 ? 1 : -1)
        let along = (u + v).norm
        c.clip(clip) {
            for k in 0..<2 {
                let off = along * (CGFloat(k) * 0.055 - 0.03)
                let p0 = e + crook * 0.10 + off
                let p1 = e + crook * 0.015 + off * 0.5 + along * 0.02
                let f = buildPath { p in p.move(to: p0); p.addQuadCurve(to: p1, control: e + crook * 0.05 + off + along * 0.035) }
                c.stroke(f, Tone.plum.deep.alpha(0.8), 0.02)
                c.stroke(f.transformed(CGAffineTransform(translationX: -0.011, y: -0.012)), VCol.plumLight.alpha(0.55), 0.009)
            }
            c.blob(e - crook * 0.075, rx: 0.06, ry: 0.06, color: VCol.plumLight.alpha(0.4))
        }
    }

    func shoulderPuff(_ s: CGPoint, _ upper: CGFloat) {
        let du = dirDown(upper)
        let pc = s + du * 0.10
        let rot = deg(-upper)
        let puff = rotatedEllipse(pc, 0.20, 0.24, rot)
        inked(puff) {
            cel(puff, .plum, depth: 0.4, grain: 0.06)
            c.clip(puff) {
                for k in -1...1 {
                    let nrm = du.perp
                    let q0 = pc + nrm * (CGFloat(k) * 0.10) - du * 0.24, q1 = pc + nrm * (CGFloat(k) * 0.12) + du * 0.24
                    let slash = taperedPath([q0, pc + nrm * (CGFloat(k) * 0.135), q1], widths: [0.02, 0.066, 0.02])
                    c.stroke(slash, VCol.ink.alpha(0.6), 0.012)
                    cel(slash, .red, depth: 0.06, rim: 0.6, bounce: 0, gloss: 0.4)
                }
            }
        }
        // gold piping where the puff gathers into the sleeve
        let band = buildPath { p in
            for i in 0...16 {
                let t = deg(38 + CGFloat(i) / 16 * 104)
                let q = pc + P(cos(t) * 0.20, sin(t) * 0.24).rotated(rot)
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
        }
        c.stroke(band, VCol.ink, 0.05)
        goldTrim(band, 0.03)
    }

    func handGroup(_ wrist: CGPoint, _ a: ArmPose, left: Bool) {
        let cd = dirDown(a.fore)
        let isFist = a.hand == .fist || a.hand == .baton || a.hand == .point
        let mirror = isFist ? left : (left ? a.palm : !a.palm)
        var theta = a.handAngle ?? a.fore
        var side: CGFloat = 0
        if a.hand == .baton {
            // orient the fist so the baton leaves between thumb and index (or out of the little-finger side)
            var bestD = CGFloat.greatestFiniteMagnitude
            for e in [CGFloat(1), -1] {
                let th = pose.batonAngle - e * (90 - pose.batonTilt)
                let d = abs(angleDiff(th, a.fore))
                if d < bestD { bestD = d; theta = th; side = e * (mirror ? -1 : 1) }
            }
        }
        let hsz: CGFloat = 1.24   // cartoon glove scale
        let t = CGAffineTransform(translationX: wrist.x, y: wrist.y).rotated(by: -deg(theta)).scaledBy(x: mirror ? -hsz : hsz, y: hsz)
        c.transform(t) {
            switch a.hand {
            case .open: openHand(a, flat: false)
            case .flat: openHand(a, flat: true)
            case .fist: fist(baton: 0)
            case .baton: fist(baton: side)
            case .point: pointHand()
            }
        }
        wristRuffle(wrist, cd)
        cuff(wrist, cd)
    }

    private func glovePart(_ p: CGPath, _ w: CGFloat) {
        inked(p, width: 0.015) { cel(p, .glove, depth: w, rim: 0.75, bounce: 0.14, gloss: 0.35) }
    }

    /// Cartoon glove, open: three fingers + thumb. Local frame: wrist at origin, fingers along +y, thumb on +x.
    func openHand(_ a: ArmPose, flat: Bool) {
        let spread = flat ? 0.15 : a.spread
        let bases = [P(0.088, 0.196), P(0.0, 0.214), P(-0.087, 0.196)]
        let angs: [CGFloat] = [4 + 13 * spread, 1 + 2 * spread, -4 - 14 * spread]
        let lens: [CGFloat] = [0.232, 0.258, 0.214]
        var fingers: [CGPath] = [], creases: [CGPath] = []
        for k in 0..<3 {
            let d = dirDown(angs[k])
            let cu = a.curl[k]
            let L = lens[k] * (1 - 0.42 * cu)
            let b = bases[k]
            let spine = [b - d * 0.05, b + d * (L * 0.45), b + d * (L * 0.82), b + d * L]
            fingers.append(taperedPath(spine, widths: [0.088, 0.08, 0.083, 0.074]))
            if cu > 0.2 {
                let m = b + d * (L * 0.55)
                creases.append(buildPath { p in p.move(to: m + d.perp * 0.03); p.addQuadCurve(to: m - d.perp * 0.03, control: m + d * 0.016) })
            }
        }
        let palmP = smoothPath([P(-0.095, -0.03), P(-0.135, 0.07), P(-0.145, 0.17), P(-0.10, 0.232), P(0, 0.248), P(0.10, 0.232),
                                P(0.145, 0.16), P(0.14, 0.06), P(0.10, -0.03)], closed: true, tension: 0.9)
        let piv = P(0.09, 0.075)
        let ts = [P(0.09, 0.075), P(0.165, 0.10), P(0.232, 0.15), P(0.262, 0.215)].map { $0.rotated(deg(a.thumb), about: piv) }
        let thumbP = taperedPath(ts, widths: [0.115, 0.104, 0.094, 0.082])
        for f in fingers.reversed() { glovePart(f, 0.09) }
        for cr in creases { c.stroke(cr, Tone.glove.deep, 0.011) }
        if a.palm {
            glovePart(palmP, 0.27)
            c.clip(palmP) {
                c.blob(P(-0.015, 0.125), rx: 0.09, ry: 0.07, color: Tone.glove.shade.alpha(0.9))
                c.stroke(smoothPath([P(0.075, 0.205), P(0.02, 0.13), P(0.055, 0.03)], closed: false), Tone.glove.deep.alpha(0.85), 0.011)
                c.stroke(smoothPath([P(-0.125, 0.185), P(-0.035, 0.168), P(0.025, 0.19)], closed: false), Tone.glove.deep.alpha(0.6), 0.009)
            }
            glovePart(thumbP, 0.1)
        } else {
            glovePart(thumbP, 0.1)
            glovePart(palmP, 0.27)
            for x in [CGFloat(-0.055), 0, 0.055] {
                c.stroke(polygonPath([P(x * 1.1, 0.035), P(x * 1.25, 0.15)], closed: false), Tone.glove.deep.alpha(0.85), 0.012)
            }
        }
    }

    /// Fist seen from the palm side: fingers wrap in front of the grip, thumb over the top.
    /// `baton` = local side (+1 thumb side / −1 little-finger side) the baton tip leaves from, 0 = empty fist.
    func fist(baton s: CGFloat) {
        let grip = P(0, 0.155)
        let gam = deg(pose.batonTilt)
        let d = P(s * cos(gam), sin(gam))
        if s != 0 {
            let fer = taperedPath([grip - d * 0.15, grip - d * 0.205], widths: [0.07, 0.066], roundCaps: false)
            inked(fer, width: 0.012) { c.metalFill(fer, .gold) }
            let bulb = rotatedEllipse(grip - d * 0.27, 0.075, 0.095, atan2(d.y, d.x) + .pi / 2)
            inked(bulb, width: 0.014) { c.glossy(bulb, light: hex(0xFFFFF4), base: hex(0xF2E4C6), dark: hex(0xA88C66), spec: 1) }
        }
        let palmP = rrectPath(CGRect(x: -0.14, y: -0.035, width: 0.28, height: 0.25), 0.1)
        glovePart(palmP, 0.27)
        if s != 0 { batonShaft(grip - d * 0.12, d, length: 1.02) }
        let xs: [CGFloat] = [-0.088, 0.0, 0.089], tops: [CGFloat] = [0.29, 0.315, 0.305], ws: [CGFloat] = [0.086, 0.094, 0.094]
        for k in 0..<3 {
            let r = CGRect(x: xs[k] - ws[k] / 2, y: 0.062, width: ws[k], height: tops[k] - 0.062)
            let roll = rrectPath(r, ws[k] / 2)
            glovePart(roll, 0.09)
            c.stroke(buildPath { p in p.move(to: P(xs[k] - ws[k] * 0.36, 0.125)); p.addQuadCurve(to: P(xs[k] + ws[k] * 0.36, 0.125), control: P(xs[k], 0.108)) }, Tone.glove.deep.alpha(0.85), 0.011)
        }
        let thumb = taperedPath([P(0.125, -0.005), P(0.178, 0.08), P(0.158, 0.172), P(0.078, 0.214)], widths: [0.112, 0.102, 0.094, 0.082])
        glovePart(thumb, 0.1)
    }

    /// Fist with the index finger extended.
    func pointHand() {
        let palmP = rrectPath(CGRect(x: -0.14, y: -0.035, width: 0.28, height: 0.25), 0.1)
        let index = taperedPath([P(0.089, 0.16), P(0.089, 0.30), P(0.089, 0.42)], widths: [0.092, 0.086, 0.078])
        glovePart(index, 0.09)
        glovePart(palmP, 0.27)
        for (x, top, w) in [(CGFloat(-0.088), CGFloat(0.29), CGFloat(0.086)), (0.0, 0.305, 0.094)] {
            glovePart(rrectPath(CGRect(x: x - w / 2, y: 0.062, width: w, height: top - 0.062), w / 2), 0.09)
        }
        glovePart(taperedPath([P(0.125, -0.005), P(0.178, 0.08), P(0.158, 0.172), P(0.078, 0.214)], widths: [0.112, 0.102, 0.094, 0.082]), 0.1)
    }

    /// Golden conductor's baton shaft from `start` along `d`, with a controlled sparkle at the tip.
    func batonShaft(_ start: CGPoint, _ d: CGPoint, length: CGFloat) {
        let tip = start + d * length
        let shaft = taperedPath([start, start + d * 0.4, start.lerp(tip, 0.7), tip], widths: [0.064, 0.056, 0.042, 0.026])
        inked(shaft, width: 0.015) {
            c.metalFill(shaft, .gold, extent: 0.2)
            c.stroke(polygonPath([start + d * 0.3 + d.perp * -0.009, tip - d * 0.06], closed: false), hex(0xFFFBE8, 0.9), 0.012)
        }
        c.layer(blend: .screen) { c.blob(tip, rx: 0.14, ry: 0.14, color: hex(0xFFE39A, 0.55)) }
        c.fill(circlePath(tip, 0.024), hex(0xFFFBEA))
    }

    /// Small cream lace frill between the sleeve cuff and the glove (echoes the neck ruff).
    func wristRuffle(_ w: CGPoint, _ d: CGPoint) {
        let n = d.perp
        let k = 6
        let hw: CGFloat = 0.17
        let path = buildPath { p in
            p.move(to: w - d * 0.03 + n * hw)
            p.addLine(to: w - d * 0.03 - n * hw)
            for i in 0..<k {
                let x0 = -hw + CGFloat(i) * 2 * hw / CGFloat(k), x1 = x0 + 2 * hw / CGFloat(k)
                p.addLine(to: w + d * 0.062 + n * x0)
                p.addQuadCurve(to: w + d * 0.062 + n * x1, control: w + d * 0.108 + n * ((x0 + x1) / 2))
            }
            p.closeSubpath()
        }
        inked(path, width: 0.013) { cel(path, .ruff, depth: 0.08, rim: 0.5, bounce: 0.1, gloss: 0.2) }
        for i in 1..<k {
            let x = -hw + CGFloat(i) * 2 * hw / CGFloat(k)
            c.stroke(polygonPath([w + d * 0.015 + n * x, w + d * 0.062 + n * x], closed: false), VCol.ruffShadow, 0.009)
        }
    }

    /// Flared crimson sleeve cuff with a gold lip.
    func cuff(_ w: CGPoint, _ d: CGPoint) {
        let n = d.perp
        let back = w - d * 0.19, front = w + d * 0.035
        let path = buildPath { p in
            p.move(to: back + n * 0.115)
            p.addLine(to: front + n * 0.19)
            p.addQuadCurve(to: front - n * 0.19, control: front + d * 0.07)
            p.addLine(to: back - n * 0.115)
            p.addQuadCurve(to: back + n * 0.115, control: back - d * 0.02)
            p.closeSubpath()
        }
        inked(path) { cel(path, .red, depth: 0.2, rim: 0.7, grain: 0.05) }
        let lip = buildPath { q in q.move(to: front + n * 0.19); q.addQuadCurve(to: front - n * 0.19, control: front + d * 0.07) }
        c.stroke(lip, VCol.ink, 0.062)
        goldTrim(lip, 0.036)
    }
}

// MARK: - Poses & renders

enum VellArt {
    static func render(_ c: Canvas, pose: VellPose, origin: CGPoint, U: CGFloat) -> VellRig {
        let rig = VellRig(c: c, pose: pose)
        c.transform(CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: U, y: U)) { rig.draw() }
        return rig
    }

    /// VC04: welcoming contrapposto — weight on the screen-left leg (hip up, shoulders counter-tilted),
    /// relaxed right leg with a bent knee, open welcoming palm, baton raised in a wrapped fist.
    static var idlePose: VellPose {
        var p = VellPose()
        p.headTilt = -5
        p.look = P(-0.15, 0)
        p.lid = 0.02
        p.browL = 0.5; p.browR = 0.25
        p.smile = 1.25
        p.mouthOpen = 0.75
        p.lean = -5
        p.hipTilt = 8
        p.armL = ArmPose(upper: -58, fore: -100, hand: .open, handAngle: -124, spread: 0.9, curl: [0, 0.05, 0.18], thumb: -8)
        p.armR = ArmPose(upper: 22, fore: 140, hand: .baton)
        p.batonAngle = 172
        p.legL = LegPose(thigh: 5, shin: 1, toe: 1)
        p.legR = LegPose(thigh: 3, shin: 14, toe: 1)
        return p
    }

    static func idle(_ c: Canvas) {
        c.blob(P(522, 1400), rx: 250, ry: 30, color: hex(0x12040E, 0.40))
        _ = render(c, pose: idlePose, origin: P(578, 912), U: 178)
    }

    /// VC05: theatrical bow — torso bent forward from the hips (foreshortened), head lowered, one arm sweeping
    /// open to the audience, the baton hand tucked behind the back, back leg crossed behind.
    static func celebrate(_ c: Canvas) {
        var p = VellPose()
        p.pitch = 46
        p.lean = -13
        p.hipTilt = -4
        p.headTilt = -10
        p.headShift = P(-0.12, 0.56)
        p.headPitch = 1
        p.hatDroop = 0.4
        p.happyEyes = true
        p.smile = 1.3
        p.mouthOpen = 0.45
        p.browL = 0.6; p.browR = 0.6
        p.armL = ArmPose(upper: -66, fore: -52, hand: .open, handAngle: -58, spread: 0.75, curl: [0.0, 0.12, 0.32], thumb: -14)
        p.armR = ArmPose(upper: 26, fore: -62, hand: .baton, front: false)
        p.batonAngle = 116
        p.legL = LegPose(thigh: 9, shin: -5, toe: 1)
        p.legR = LegPose(thigh: -7, shin: -17, toe: 0.8, behind: true)
        p.hatSwing = 1.5
        c.blob(P(520, 1400), rx: 250, ry: 30, color: hex(0x12040E, 0.40))
        _ = render(c, pose: p, origin: P(600, 930), U: 178)
    }

    /// VC06: thoughtful warm smile, head tilt, supportive open palm toward the viewer; baton lowered at the side.
    static func encourage(_ c: Canvas) {
        var p = VellPose()
        p.lean = 4
        p.hipTilt = -7
        p.headTilt = 9
        p.look = P(0.15, 0.2)
        p.lid = 0.16
        p.browL = 0.35; p.browR = 0.35
        p.browInner = 0.8
        p.smile = 1.0
        p.mouthOpen = 0.3
        p.armL = ArmPose(upper: -8, fore: 6, hand: .baton)
        p.batonAngle = -40
        p.armR = ArmPose(upper: 30, fore: 112, hand: .open, handAngle: 136, spread: 0.6, curl: [0, 0.06, 0.16], thumb: -4)
        p.legL = LegPose(thigh: -2, shin: -13, toe: 1)
        p.legR = LegPose(thigh: -4, shin: 0, toe: 1)
        c.blob(P(512, 1400), rx: 250, ry: 30, color: hex(0x12040E, 0.40))
        _ = render(c, pose: p, origin: P(470, 912), U: 178)
    }

    /// VC37: separate bust drawing. The face is framed much larger than in VC04; in this tight framing the
    /// soft hat points flop down over the ears (left longer, right shorter) and the centre point folds over
    /// to the right, so all three points, their bells and the collar stay inside the square frame.
    static let portraitFace: CGFloat = 0.53     // target skin-oval width / frame width
    static func portrait(_ c: Canvas) {
        var p = VellPose()
        p.bust = true
        p.hatStyle = .portrait
        p.look = .zero
        p.lid = 0.02
        p.browL = 0.5; p.browR = 0.3
        p.smile = 1.2
        p.mouthOpen = 0.6
        p.armL = ArmPose(upper: -8, fore: -4, hand: .open)
        p.armR = ArmPose(upper: 8, fore: 4, hand: .open)
        let hs = portraitFace * 768 / 0.85
        let U = hs / VellRig.headScale
        let hcY: CGFloat = 392
        let origin = P(384, hcY + 2.29 * U)
        c.layer {
            c.transform(CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: U, y: U)) {
                // baton rising beside the right shoulder (the hand is below the frame), behind the figure
                VellRig(c: c, pose: p).batonShaft(P(0.78, -0.86), dirDown(188), length: 1.12)
            }
            _ = render(c, pose: p, origin: origin, U: U)
            // fade the shoulders out below the collar so nothing is hard-clipped at the frame edge
            c.ctx.setBlendMode(.destinationOut)
            c.linear(nil, [(0, RGBA.black.alpha(0)), (1, RGBA.black)], P(0, 724), P(0, 764))
        }
        let hc = P(origin.x, hcY)
        // skin face oval: x ±0.425, from hat band (-0.40) to chin (+0.585), in head units
        let face = CGRect(x: hc.x - 0.425 * hs, y: hc.y - 0.40 * hs, width: 0.85 * hs, height: 0.985 * hs)
        MetaStore.shared.set("VC37", "faceRectWithEars", normRect(CGRect(x: hc.x - 0.505 * hs, y: hc.y - 0.40 * hs, width: 1.01 * hs, height: 0.985 * hs), 768, 768))
        MetaStore.shared.set("VC37", "faceRect", normRect(face, 768, 768))
    }
}
