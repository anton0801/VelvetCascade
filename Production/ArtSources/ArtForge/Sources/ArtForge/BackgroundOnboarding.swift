// BackgroundOnboarding.swift — VC01 Welcome, VC02 Match tutorial, VC03 Rotation tutorial.
// Hero Vell is drawn with the same parametric rig as VC04–VC06/VC37.
import Foundation
import CoreGraphics

extension Backgrounds {

    /// Big round brass stage frame (full ring) with a warm glowing interior.
    static func stageRing(_ c: Canvas, center c0: CGPoint, radius R: CGFloat, width w: CGFloat, glow: RGBA = hex(0xFFC870), rotation: CGFloat = 0) {
        c.layer(blend: .screen) { c.blob(c0, rx: R * 1.05, ry: R * 1.05, color: glow.alpha(0.20)) }
        c.radial(circlePath(c0, R - w / 2), [(0, hex(0x5A2A40, 0.55)), (0.7, hex(0x2A1230, 0.35)), (1, hex(0x12060E, 0.7))], center: c0 - P(R * 0.2, R * 0.25), radius: R)
        let ring = circlePath(c0, R)
        c.shadowOnly(ring.stroked(w), dx: 14, dy: 22, blur: 30, color: hex(0x05010A, 0.85))
        c.stroke(ring, Metal.brass.edge, w + 10)
        c.metalFill(ring.stroked(w), .brass, bbox: CGRect(x: c0.x - R, y: c0.y - R, width: 2 * R, height: 2 * R))
        for (off, col, lw) in [(-w * 0.30, hex(0x3A220A, 0.7), CGFloat(4)), (-w * 0.25, hex(0xFFE6B0, 0.45), 2), (w * 0.28, hex(0x3A220A, 0.7), 4)] {
            c.stroke(circlePath(c0, R + off), col, lw)
        }
        let (a, b) = c.lightAxis(CGRect(x: c0.x - R, y: c0.y - R, width: 2 * R, height: 2 * R))
        c.linear(circlePath(c0, R - w * 0.1).stroked(w * 0.12), [(0, RGBA.white.alpha(0.75)), (0.35, RGBA.white.alpha(0)), (1, RGBA.clear)], a, b)
        for k in 0..<24 {
            let ang = rotation + CGFloat(k) / 24 * 2 * .pi
            let pc = c0 + P(cos(ang), sin(ang)) * R
            let bolt = circlePath(pc, w * 0.09)
            c.stroke(bolt, hex(0x2A1606, 0.9), 3)
            c.glossy(bolt, light: hex(0xFFF0C8), base: hex(0xC08840), dark: hex(0x5A3412), spec: 0.9)
        }
        // quarter-turn index marks (gold chevrons at N/E/S/W)
        for k in 0..<4 {
            let ang = rotation + CGFloat(k) * .pi / 2 - .pi / 2
            let pc = c0 + P(cos(ang), sin(ang)) * (R + w * 0.5 + 6)
            let d = P(cos(ang), sin(ang)), n = d.perp
            let tri = polygonPath([pc + d * 26, pc + n * 22, pc - n * 22])
            c.stroke(tri, Metal.gold.edge, 5); c.metalFill(tri, .gold)
        }
    }

    /// Round brass turntable seen in slight perspective (stage floor disc).
    static func turntable(_ c: Canvas, center c0: CGPoint, rx: CGFloat, ry: CGFloat) {
        let top = ellipsePath(c0, rx, ry)
        let side = buildPath { p in
            p.move(to: P(c0.x - rx, c0.y)); p.addLine(to: P(c0.x - rx, c0.y + 46))
            p.addArc(center: P(c0.x, c0.y + 46), radius: rx, startAngle: .pi, endAngle: 0, clockwise: true)
            p.addLine(to: P(c0.x + rx, c0.y)); p.closeSubpath()
        }
        let sideE = buildPath { p in
            p.addEllipse(in: CGRect(x: c0.x - rx, y: c0.y + 46 - ry, width: 2 * rx, height: 2 * ry))
            p.addRect(CGRect(x: c0.x - rx, y: c0.y, width: 2 * rx, height: 46))
        }
        _ = side
        c.shadowOnly(sideE, dx: 0, dy: 30, blur: 40, color: hex(0x05010A, 0.9))
        c.stroke(sideE, Metal.brass.edge, 8)
        c.linear(sideE, [(0, hex(0xE0A858)), (0.3, hex(0xA86E30)), (0.7, hex(0x5A3614)), (1, hex(0x3A200A))], P(c0.x - rx, 0), P(c0.x + rx, 0))
        c.stroke(top, Metal.brass.edge, 8)
        c.velvet(top, base: hex(0x4A1A40), sheen: hex(0x9A4A8A), deep: hex(0x1E0818), sheenWidth: 60, texture: 0.14)
        for (k, f) in [0.78, 0.52].enumerated() {
            c.stroke(ellipsePath(c0, rx * CGFloat(f), ry * CGFloat(f)), hex(0xAF783B, 0.55 - CGFloat(k) * 0.15), 5)
        }
        c.metalRim(top, width: 22, metal: .brass)
    }

    // MARK: VC01 Welcome
    static func onboardingWelcome(_ c: Canvas) {
        let look = WorldLook(centerGlow: hex(0x6A2A40), drape: .ruby, valance: .burgundy)
        base(c, look)
        c.stageFloor(top: H * 0.66, vanish: P(W / 2, H * 0.30), color: hex(0x1E0D1A), lineColor: hex(0x3A1E2E, 0.30))
        // round brass stage behind the hero
        stageRing(c, center: P(W / 2, 1030), radius: 470, width: 52)
        c.lightCone(apex: P(W / 2, -80), toward: P(W / 2, 1650), spread: deg(26), color: hex(0xFFD26E), alpha: 0.20, dust: 80, seed: 7)
        turntable(c, center: P(W / 2, 1640), rx: 470, ry: 110)
        // gems floating in the upper half (kept clear of the title band)
        // left curtain (already open) and valance
        c.drape(Drape(rect: CGRect(x: -30, y: 130, width: 230, height: H - 90), colors: .ruby, folds: 6, outerLeft: true, pinchY: 1500, pinch: 0.45, seed: 3))
        // right curtain, being drawn aside by Vell
        c.drape(Drape(rect: CGRect(x: 900, y: 130, width: 420, height: H - 90), colors: .crimson, folds: 8, outerLeft: false, pinchY: 1120, pinch: 0.30, sway: 50, seed: 5, tassel: false))
        c.valance(bandHeight: 110, swagDepth: 170, swags: 4, colors: .burgundy)
        // gems floating in the upper half, in front of the drapes (kept clear of the title band)
        let gems: [(Int, CGPoint, CGFloat, CGFloat)] = [(0, P(215, 640), 74, -12), (1, P(1085, 560), 72, 10), (4, P(1120, 900), 58, -8), (2, P(170, 1000), 60, 8), (3, P(905, 470), 50, 6)]
        for (kind, p, sc, rot) in gems { floatingGem(c, kind: kind, at: p, scale: sc, rotation: deg(rot)) }
        // Vell steps out, gripping the curtain edge
        var p = VellPose()
        p.lid = 0.02; p.browL = 0.55; p.browR = 0.35; p.smile = 1.25; p.mouthOpen = 0.7
        p.headTilt = -5; p.look = P(-0.15, 0)
        p.armL = ArmPose(upper: -48, fore: -122, hand: .baton, handAngle: -150)
        p.batonAngle = -150
        p.armR = ArmPose(upper: 78, fore: 92, hand: .fist, handAngle: 80)
        p.hipTilt = -6; p.lean = 3
        p.legL = LegPose(thigh: -3, shin: -12, toe: 1)
        p.legR = LegPose(thigh: -4, shin: 0, toe: 1)
        c.blob(P(610, 1690), rx: 230, ry: 34, color: hex(0x0A020A, 0.55))
        _ = VellArt.render(c, pose: p, origin: P(605, 1215), U: 168)
        finish(c, vignette: 0.55)
    }

    static func floatingGem(_ c: Canvas, kind: Int, at p: CGPoint, scale: CGFloat, rotation: CGFloat) {
        c.layer(blend: .screen) { c.blob(p, rx: scale * 1.7, ry: scale * 1.7, color: [hex(0xFF4A62), hex(0x4DB4FF), hex(0x46D9A0), hex(0xFFC54F), hex(0xB883F7)][kind].alpha(0.28)) }
        c.transform(CGAffineTransform(translationX: p.x, y: p.y).rotated(by: rotation).translatedBy(x: -p.x, y: -p.y)) {
            switch kind {
            case 0: Gems.heart(c, center: p, scale: scale, shadow: false)
            case 1: Gems.diamond(c, center: p, scale: scale, shadow: false)
            case 2: Gems.clover(c, center: p, scale: scale, shadow: false)
            case 3: Gems.bell(c, center: p, scale: scale, shadow: false)
            default: Gems.star(c, center: p, scale: scale, shadow: false)
            }
        }
    }

    // MARK: VC02 Match tutorial
    static func onboardingMatch(_ c: Canvas) {
        // macro velvet: a few huge soft folds filling the frame
        c.fill(rectPath(c.bounds), hex(0x1E0C24))
        c.drape(Drape(rect: CGRect(x: -140, y: -60, width: W + 280, height: H + 120), colors: DrapeColors(deep: hex(0x12061A), base: hex(0x3A1848), sheen: hex(0x7A3C8E)), folds: 5, outerLeft: true, pinchY: nil, sway: 0, seed: 17, hemDepth: 0, tassel: false, lightFromTop: 0.15))
        // calm the centre and lower part
        c.radialEllipse(nil, [(0, hex(0x1C0A22, 0.75)), (0.6, hex(0x1C0A22, 0.45)), (1, hex(0x1C0A22, 0))], center: P(W / 2, H * 0.52), rx: W * 0.55, ry: H * 0.34)
        c.fabricGrain(nil, alpha: 0.10, fibre: 0.5)
        // thin gold cables with five big gems along the upper edges
        let gems: [(Int, CGPoint, CGFloat)] = [(0, P(165, 600), 112), (1, P(385, 330), 104), (2, P(160, 1010), 96), (4, P(1125, 600), 112), (3, P(905, 330), 100)]
        for (_, p, sc) in gems {
            let cable = buildPath { q in q.move(to: P(p.x - 8, -20)); q.addQuadCurve(to: p + P(0, -sc * 0.95), control: P(p.x + 14, p.y * 0.5)) }
            c.stroke(cable, hex(0x2A1606, 0.9), 7)
            c.metalRim(cable, width: 4.5, metal: .gold)
            let ring = circlePath(p + P(0, -sc * 1.02), 11)
            c.stroke(ring, hex(0x2A1606), 9); c.metalRim(ring, width: 6, metal: .gold)
        }
        for (kind, p, sc) in gems { floatingGem(c, kind: kind, at: p, scale: sc, rotation: 0) }
        // soft warm light from the top edge
        c.layer(blend: .screen) { c.radialEllipse(nil, [(0, hex(0xFFD26E, 0.16)), (1, hex(0xFFD26E, 0))], center: P(W / 2, -100), rx: W * 0.9, ry: 700) }
        finish(c, vignette: 0.55)
    }

    // MARK: VC03 Rotation tutorial
    static func onboardingRotate(_ c: Canvas) {
        let look = WorldLook(centerGlow: hex(0x55243E), drape: .ruby, valance: .burgundy)
        base(c, look)
        c.stageFloor(top: H * 0.70, vanish: P(W / 2, H * 0.32), color: hex(0x1E0D1A), lineColor: hex(0x3A1E2E, 0.30))
        // golden spotlight from the right
        c.lightCone(apex: P(W + 60, 200), toward: P(700, 1500), spread: deg(26), color: hex(0xFFD26E), alpha: 0.30, dust: 90, seed: 13)
        // curtains swept by the motion of the turn
        c.drape(Drape(rect: CGRect(x: -30, y: 130, width: 210, height: H - 90), colors: .ruby, folds: 5, outerLeft: true, pinchY: nil, sway: 150, seed: 23, tassel: false))
        c.drape(Drape(rect: CGRect(x: W - 190, y: 130, width: 220, height: H - 90), colors: .ruby, folds: 5, outerLeft: false, pinchY: nil, sway: 120, seed: 29, tassel: false))
        c.valance(bandHeight: 110, swagDepth: 160, swags: 4, colors: .burgundy)
        // empty rotating brass frame with motion arcs
        let fc = P(760, 1330)
        rotatingFrame(c, center: fc, size: 520, angle: deg(-14))
        // Vell, upper-left, pointing the baton at the frame
        var p = VellPose()
        p.lid = 0.05; p.browL = 0.6; p.browR = 0.4; p.smile = 1.15; p.mouthOpen = 0.5
        p.headTilt = 6; p.look = P(0.5, 0.35)
        p.lean = 4
        p.armR = ArmPose(upper: 70, fore: 104, hand: .baton, handAngle: 120)
        p.batonAngle = 118
        p.armL = ArmPose(upper: -28, fore: -58, hand: .open, handAngle: -80)
        p.legL = LegPose(thigh: -5, shin: 2, toe: 1)
        p.legR = LegPose(thigh: 7, shin: 0, toe: 1)
        c.blob(P(300, 1275), rx: 150, ry: 22, color: hex(0x0A020A, 0.55))
        // small balcony ledge he stands on
        let ledge = rrectPath(CGRect(x: 150, y: 1268, width: 300, height: 40), 12)
        c.stroke(ledge, Metal.brass.edge, 8); c.metalPlate(ledge, .brass, bevel: 8)
        _ = VellArt.render(c, pose: p, origin: P(300, 930), U: 118)
        finish(c, vignette: 0.55)
    }

    static func rotatingFrame(_ c: Canvas, center fc: CGPoint, size s: CGFloat, angle: CGFloat) {
        // motion arcs behind
        c.layer(blend: .screen) {
            for k in 0..<3 {
                let r = s * (0.80 + CGFloat(k) * 0.07)
                let arc = buildPath { p in p.addArc(center: fc, radius: r, startAngle: deg(-60) + angle, endAngle: deg(10) + angle, clockwise: false) }
                c.stroke(arc, hex(0xFFD26E, 0.28 - CGFloat(k) * 0.07), 10 - CGFloat(k) * 2)
                let arc2 = buildPath { p in p.addArc(center: fc, radius: r, startAngle: deg(120) + angle, endAngle: deg(190) + angle, clockwise: false) }
                c.stroke(arc2, hex(0xFFD26E, 0.28 - CGFloat(k) * 0.07), 10 - CGFloat(k) * 2)
            }
        }
        stageRing(c, center: fc, radius: s * 0.72, width: 40, glow: hex(0xFFC870), rotation: angle)
        c.transform(CGAffineTransform(translationX: fc.x, y: fc.y).rotated(by: angle)) {
            let half = s * 0.46
            let outer = rrectPath(CGRect(x: -half, y: -half, width: 2 * half, height: 2 * half), 26)
            let inner = rrectPath(CGRect(x: -half + 34, y: -half + 34, width: 2 * half - 68, height: 2 * half - 68), 14)
            let frame = combine([outer, inner])
            c.shadowOnly(frame, dx: 12, dy: 20, blur: 26, color: hex(0x05010A, 0.85))
            c.fill(inner, hex(0x1A0A1E, 0.85))
            c.innerShadow(inner, dx: 10, dy: 14, blur: 20, color: hex(0x000000, 0.6))
            c.save {
                c.ctx.addPath(frame); c.ctx.clip(using: .evenOdd)
                c.metalFill(outer, .brass)
                let L = c.lightDir()
                c.innerShadow(outer, dx: -L.dx * 8, dy: -L.dy * 8, blur: 6, color: hex(0xFFF0C8, 0.7))
                c.innerShadow(outer, dx: L.dx * 10, dy: L.dy * 10, blur: 8, color: hex(0x2A1606, 0.7))
            }
            c.stroke(inner, Metal.brass.edge, 5)
            c.stroke(outer, Metal.brass.edge, 6)
            for (x, y) in [(-half + 17, -half + 17), (half - 17, -half + 17), (-half + 17, half - 17), (half - 17, half - 17)] {
                c.glossy(circlePath(P(x, y), 8), light: hex(0xFFF0C8), base: hex(0xC08840), dark: hex(0x5A3412), spec: 1)
            }
        }
    }
}
