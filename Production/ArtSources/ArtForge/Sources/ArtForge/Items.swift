// Items.swift — specials, board objects/overlays, curtains, spotlight beam, app icon and UI items.
// Canvas for 512-px items is 512 design units rendered at 2×.
import Foundation
import CoreGraphics

enum Items {
    static let C = P(256, 256)

    /// Standalone Vell hat (same parametric hat as the character) centred at `c0`, `s` = head-unit size in px.
    static func vellHat(_ c: Canvas, at c0: CGPoint, size s: CGFloat, droop: CGFloat = 0, inside: Bool = true) {
        var pose = VellPose()
        pose.hatDroop = droop
        let rig = VellRig(c: c, pose: pose)
        c.transform(CGAffineTransform(translationX: c0.x, y: c0.y).scaledBy(x: s, y: s)) {
            if inside {
                // dark hat interior visible under the band
                let inner = buildPath { p in
                    p.move(to: P(-0.47, -0.40)); p.addQuadCurve(to: P(0.47, -0.40), control: P(0, -0.27))
                    p.addQuadCurve(to: P(-0.47, -0.40), control: P(0, -0.20)); p.closeSubpath()
                }
                c.fill(inner, hex(0x14060F))
            }
            rig.hat()
        }
    }

    // MARK: VC12 Stage Burst
    static func burst(_ c: Canvas) {
        let cc = P(246, 284), R: CGFloat = 150
        let sphere = circlePath(cc, R)
        c.dropShadow(sphere, dx: 8, dy: 12, blur: 18, alpha: 0.45)
        // fuse (behind the socket)
        let fuse = [cc + P(92, -118), cc + P(122, -150), cc + P(116, -178), cc + P(140, -196)]
        c.stroke(smoothPath(fuse, closed: false), hex(0x1A0A06), 20)
        c.stroke(smoothPath(fuse, closed: false), hex(0x8A5A2A), 12)
        c.stroke(smoothPath(fuse, closed: false), hex(0xE8C080, 0.6), 4)
        for k in 0..<5 { // twine wraps
            let t = CGFloat(k) / 5
            let p = fuse[0].lerp(fuse[3], t)
            c.stroke(polygonPath([p + P(-6, 3), p + P(6, -3)], closed: false), hex(0x3A2410, 0.7), 2.5)
        }
        // body: plum metal
        c.stroke(sphere, hex(0x12040E), 12)
        c.glossy(sphere, light: hex(0x9A62B0), base: hex(0x4A1E5A), dark: hex(0x14061C), bounce: hex(0xC0304A, 0.55), spec: 0.9, specSize: 1.3)
        // gold ribs (meridians + equator)
        c.clip(sphere) {
            for f in [CGFloat(0.42), 0.82] {
                let m = ellipsePath(cc, R * f, R * 1.02)
                c.stroke(m, hex(0x2A1606, 0.9), 18)
                c.metalRim(m, width: 11, metal: .gold, bbox: sphere.bbox)
            }
            let eq = ellipsePath(cc + P(0, 18), R * 1.02, R * 0.34)
            c.stroke(eq, hex(0x2A1606, 0.9), 22)
            c.metalRim(eq, width: 14, metal: .gold, bbox: sphere.bbox)
        }
        c.metalRim(sphere, width: 8, metal: .gold)
        // socket for the fuse
        let sock = rotatedEllipse(cc + P(84, -110), 30, 20, deg(-38))
        c.stroke(sock, hex(0x2A1606), 8); c.metalPlate(sock, .gold, bevel: 6)
        // red crystal on the front
        let gc = cc + P(-6, 30)
        let oct = (0..<8).map { k -> CGPoint in let a = CGFloat(k) / 8 * 2 * .pi + .pi / 8; return gc + P(cos(a), sin(a)) * 62 }
        let crystal = roundedPolygon(oct, radius: 6)
        c.stroke(crystal, hex(0x2A020C), 20)
        var st = GemStyle(); st.rim = 10; st.tableScale = 0.5
        c.facetedGem(shape: crystal, outer: oct, tableCenter: gc, colors: .crimsonCrystal, style: st)
        c.gemSpecular(crystal, at: gc + P(-26, -28), size: 20)
        // glowing spark at the fuse tip (controlled glow)
        let tip = fuse[3]
        c.layer(blend: .screen) {
            c.blob(tip, rx: 64, ry: 64, color: hex(0xFFB040, 0.55))
            c.blob(tip, rx: 30, ry: 30, color: hex(0xFFE08A, 0.9))
        }
        c.glint(tip, size: 34, color: hex(0xFFF6D8), angle: deg(12))
        c.fill(circlePath(tip, 9), RGBA.white)
        c.glint(P(96, 196), size: 16, color: hex(0xFFF0C0))
    }

    // MARK: VC13 Prism
    static func prism(_ c: Canvas) {
        let cc = P(256, 262), R: CGFloat = 176
        let outer = (0..<5).map { k -> CGPoint in let a = -CGFloat.pi / 2 + CGFloat(k) / 5 * 2 * .pi; return cc + P(cos(a), sin(a)) * R }
        let setting = roundedPolygon(outer.map { cc + ($0 - cc) * 1.10 }, radius: 30)
        c.dropShadow(setting, dx: 8, dy: 12, blur: 18, alpha: 0.45)
        c.layer(blend: .screen) { c.blob(cc, rx: 230, ry: 230, color: hex(0xFFF0E0, 0.18)) }
        c.stroke(setting, Metal.brass.edge, 10)
        c.metalPlate(setting, .brass, bevel: 10)
        let gem = roundedPolygon(outer, radius: 16)
        c.stroke(gem, hex(0x1A0A10), 10)
        let cols: [GemColors] = [.ruby, .amber, .emerald, .sapphire, .amethyst]
        let inner = scalePoints(outer, about: cc, 0.46)
        c.clip(gem) {
            for i in 0..<5 {
                let j = (i + 1) % 5
                let g = cols[i]
                let quad = polygonPath([cc + (outer[i] - cc) * 1.1, cc + (outer[j] - cc) * 1.1, inner[j], inner[i]])
                let mid = (outer[i] + outer[j]) * 0.5
                var o = (outer[j] - outer[i]).perp.norm
                if o.dot(mid - cc) < 0 { o = o * -1 }
                let n = V3(o.x * sin(deg(44)), o.y * sin(deg(44)), cos(deg(44))).norm
                let base = facetColor(n, g, gain: 1.15)
                c.linear(quad, [(0, base.lighter(0.25)), (1, base.darker(0.05))], (inner[i] + inner[j]) * 0.5, mid)
                // split each facet with a kite line for extra sparkle
                c.stroke(polygonPath([(inner[i] + inner[j]) * 0.5, mid], closed: false), g.glint.alpha(0.35), 2)
            }
            // table: iridescent white with pastel rays
            let table = polygonPath(inner)
            c.radial(table, [(0, hex(0xFFFFFF)), (0.5, hex(0xF4ECFF)), (1, hex(0xD8E8FF))], center: cc + P(-20, -24), radius: 110)
            for i in 0..<5 {
                let j = (i + 1) % 5
                c.fill(polygonPath([cc, inner[i], inner[j]]), cols[i].light.alpha(0.28))
            }
            for i in 0..<5 { c.stroke(polygonPath([outer[i], inner[i]], closed: false), RGBA.white.alpha(0.5), 2) }
            c.stroke(table, RGBA.white.alpha(0.8), 3)
        }
        c.metalRim(gem, width: 9, metal: .gold)
        // prongs
        for p in outer {
            let pr = circlePath(cc + (p - cc) * 1.02, 17)
            c.stroke(pr, Metal.gold.edge, 6)
            c.glossy(pr, light: hex(0xFFF6D0), base: hex(0xE0A84A), dark: hex(0x6A3E10), spec: 1)
        }
        c.glint(cc + P(-34, -40), size: 34)
        c.glint(cc + P(70, 52), size: 16)
    }

    // MARK: VC14 Stage Key
    static func key(_ c: Canvas) {
        c.transform(CGAffineTransform(translationX: 256, y: 256).rotated(by: deg(-45)).translatedBy(x: -256, y: -256)) {
            let bowC = P(256, 108)
            let bowOuter = circlePath(bowC, 96)
            let bowInner = circlePath(bowC, 54)
            let shaft = rrectPath(CGRect(x: 234, y: 190, width: 44, height: 250), 14)
            let bit = buildPath { p in
                // two bold teeth on the right side of the shaft end
                p.addRect(CGRect(x: 262, y: 350, width: 84, height: 36))
                p.addRect(CGRect(x: 262, y: 404, width: 70, height: 36))
                p.addRect(CGRect(x: 300, y: 386, width: 30, height: 18))
            }
            let collar = rrectPath(CGRect(x: 222, y: 196, width: 68, height: 28), 10)
            let tip = rrectPath(CGRect(x: 226, y: 430, width: 60, height: 22), 9)
            let whole = combine([bowOuter, shaft, bit, collar, tip])
            c.dropShadow(whole, dx: 0, dy: 16, blur: 18, alpha: 0.45)
            c.stroke(whole, Metal.gold.edge, 14)
            c.fill(whole, hex(0xD9A04A))
            for part in [shaft, bit, tip] {
                c.metalPlate(part, .gold, bevel: 9)
            }
            c.metalPlate(collar, .gold, bevel: 7)
            c.stroke(collar, Metal.gold.edge.alpha(0.7), 3)
            // bow ring
            let ring = combine([bowOuter, bowInner])
            c.save {
                c.ctx.addPath(ring); c.ctx.clip(using: .evenOdd)
                c.metalFill(bowOuter, .gold)
                let L = c.lightDir()
                c.innerShadow(bowOuter, dx: -L.dx * 10, dy: -L.dy * 10, blur: 8, color: hex(0xFFF8DC, 0.85))
                c.innerShadow(bowOuter, dx: L.dx * 10, dy: L.dy * 10, blur: 8, color: Metal.gold.edge.alpha(0.7))
            }
            c.stroke(circlePath(bowC, 75), hex(0x6A4010, 0.5), 3)
            // plum enamel inset
            c.stroke(bowInner, Metal.gold.edge, 6)
            c.glossy(bowInner, light: hex(0xA868C0), base: hex(0x55226A), dark: hex(0x1E0828), bounce: hex(0xD04060, 0.4), spec: 0.9)
            let dia = polygonPath([bowC + P(0, -22), bowC + P(16, 0), bowC + P(0, 22), bowC + P(-16, 0)])
            c.stroke(dia, Metal.gold.edge, 4); c.metalFill(dia, .gold)
            // engraved lines on the shaft
            c.stroke(polygonPath([P(256, 236), P(256, 330)], closed: false), hex(0x7A4A14, 0.6), 3)
        }
        c.glint(P(150, 150), size: 22)
    }

    // MARK: VC15 Exit Port
    static func exitPort(_ c: Canvas) {
        let archOuter = buildPath { p in
            p.move(to: P(80, 470)); p.addLine(to: P(80, 230))
            p.addArc(center: P(256, 230), radius: 176, startAngle: .pi, endAngle: 0, clockwise: false)
            p.addLine(to: P(432, 470)); p.closeSubpath()
        }
        let opening = buildPath { p in
            p.move(to: P(126, 452)); p.addLine(to: P(126, 236))
            p.addArc(center: P(256, 236), radius: 130, startAngle: .pi, endAngle: 0, clockwise: false)
            p.addLine(to: P(386, 452)); p.closeSubpath()
        }
        c.dropShadow(archOuter, dx: 6, dy: 12, blur: 16, alpha: 0.45)
        c.stroke(archOuter, Metal.brass.edge, 12)
        c.save {
            c.ctx.addPath(combine([archOuter, opening])); c.ctx.clip(using: .evenOdd)
            c.metalFill(archOuter, .gold)
            let L = c.lightDir()
            c.innerShadow(archOuter, dx: -L.dx * 10, dy: -L.dy * 10, blur: 8, color: hex(0xFFF8DC, 0.8))
            c.innerShadow(archOuter, dx: L.dx * 10, dy: L.dy * 10, blur: 10, color: Metal.gold.edge.alpha(0.7))
            // arch voussoir lines
            for k in 1..<8 {
                let a = CGFloat.pi + CGFloat(k) / 8 * .pi
                c.stroke(polygonPath([P(256, 230) + P(cos(a), sin(a)) * 132, P(256, 230) + P(cos(a), sin(a)) * 174], closed: false), hex(0x6A4010, 0.55), 3)
            }
        }
        // warm depth
        c.radialEllipse(opening, [(0, hex(0xFFE9A8)), (0.3, hex(0xFFB84A)), (0.7, hex(0x9A3A18)), (1, hex(0x2A0808))], center: P(256, 300), rx: 150, ry: 210)
        // a darker inner doorway far back for depth
        let back = buildPath { p in
            p.move(to: P(206, 452)); p.addLine(to: P(206, 300))
            p.addArc(center: P(256, 300), radius: 50, startAngle: .pi, endAngle: 0, clockwise: false)
            p.addLine(to: P(306, 452)); p.closeSubpath()
        }
        c.layer(blend: .screen) { c.blob(P(256, 340), rx: 90, ry: 130, color: hex(0xFFF2C8, 0.55)) }
        c.stroke(back, hex(0xB0561A, 0.45), 4)
        let L = c.lightDir()
        c.innerShadow(opening, dx: -L.dx * 22, dy: -L.dy * 22, blur: 20, color: hex(0x1A0404, 0.8))
        // arched velvet swag across the top of the opening + drawn-back side drapes
        c.clip(opening) {
            let swag = buildPath { p in
                p.move(to: P(110, 110)); p.addLine(to: P(402, 110)); p.addLine(to: P(402, 236))
                p.addQuadCurve(to: P(256, 196), control: P(360, 196))
                p.addQuadCurve(to: P(110, 236), control: P(152, 196)); p.closeSubpath()
            }
            c.shadowOnly(swag, dx: 0, dy: 8, blur: 10, color: hex(0x1A0206, 0.7))
            c.linear(swag, [(0, hex(0x6A0A20)), (0.6, hex(0xB52643)), (1, hex(0x7A0E26))], P(0, 110), P(0, 236))
            c.stroke(buildPath { p in p.move(to: P(126, 226)); p.addQuadCurve(to: P(256, 206), control: P(170, 208)); p.addQuadCurve(to: P(386, 226), control: P(342, 208)) }, hex(0xFF8098, 0.5), 3)
            for s2 in [CGFloat(-1), 1] {
                let x0: CGFloat = s2 < 0 ? 126 : 386
                let drape = buildPath { p in
                    p.move(to: P(x0, 150))
                    p.addLine(to: P(x0 - s2 * 64, 150))
                    p.addCurve(to: P(x0 - s2 * 30, 330), control1: P(x0 - s2 * 70, 230), control2: P(x0 - s2 * 40, 300))
                    p.addCurve(to: P(x0 - s2 * 58, 452), control1: P(x0 - s2 * 30, 380), control2: P(x0 - s2 * 60, 420))
                    p.addLine(to: P(x0, 452)); p.closeSubpath()
                }
                c.shadowOnly(drape, dx: -s2 * 8, dy: 6, blur: 10, color: hex(0x1A0206, 0.7))
                c.linear(drape, [(0, hex(0x5A0A1C)), (0.45, hex(0xB52643)), (0.8, hex(0xE0506A)), (1, hex(0x8A1430))], P(x0, 0), P(x0 - s2 * 64, 0))
                c.clip(drape) {
                    c.stroke(smoothPath([P(x0 - s2 * 44, 150), P(x0 - s2 * 22, 330), P(x0 - s2 * 38, 452)], closed: false), hex(0x5A0A1C, 0.55), 6)
                    c.stroke(smoothPath([P(x0 - s2 * 54, 150), P(x0 - s2 * 28, 330), P(x0 - s2 * 50, 452)], closed: false), hex(0xFF8098, 0.4), 3)
                }
                let tieC = P(x0 - s2 * 24, 330)
                c.stroke(rotatedEllipse(tieC, 24, 9, deg(-20 * s2)), Metal.gold.edge, 6)
                c.metalRim(rotatedEllipse(tieC, 24, 9, deg(-20 * s2)), width: 6, metal: .gold)
            }
        }
        // threshold step
        let step = rrectPath(CGRect(x: 104, y: 446, width: 304, height: 34), 10)
        c.stroke(step, Metal.brass.edge, 8)
        c.metalPlate(step, .brass, bevel: 7)
        // keystone gem
        let ks = polygonPath([P(256, 40), P(282, 66), P(256, 92), P(230, 66)])
        c.stroke(ks, hex(0x2A020C), 6)
        c.linear(ks, [(0, hex(0xFF7A8C)), (0.5, hex(0xC8102F)), (1, hex(0x4A0414))], P(236, 46), P(276, 88))
        c.glint(P(248, 60), size: 10)
    }

    // MARK: VC16 Crate
    static func crate(_ c: Canvas) {
        let r = CGRect(x: 18, y: 18, width: 476, height: 476)
        let box = rrectPath(r, 26)
        c.dropShadow(box, dx: 0, dy: 6, blur: 8, alpha: 0.35)
        c.stroke(box, hex(0x120604), 10)
        c.wood(box, base: hex(0x3E2216), light: hex(0x6A3C24), dark: hex(0x1C0C06), seed: 5)
        // inner recessed boards
        let inner = rrectPath(r.insetBy(dx: 58, dy: 58), 8)
        c.clip(inner) {
            c.wood(inner, base: hex(0x33190F), light: hex(0x5A3320), dark: hex(0x150804), grainAngle: .pi / 2, seed: 9)
            for k in 1..<4 {
                let x = r.minX + 58 + CGFloat(k) * (r.width - 116) / 4
                c.stroke(polygonPath([P(x, 0), P(x, 512)], closed: false), hex(0x0E0604, 0.8), 5)
                c.stroke(polygonPath([P(x + 3, 0), P(x + 3, 512)], closed: false), hex(0x8A5A36, 0.3), 1.5)
            }
            c.innerShadow(inner, dx: 14, dy: 16, blur: 14, color: hex(0x000000, 0.75))
        }
        c.stroke(inner, hex(0x120604), 5)
        // diagonal brace plank
        let diag = buildPath { p in
            p.move(to: P(r.minX + 60, r.maxY - 94)); p.addLine(to: P(r.maxX - 94, r.minY + 60))
            p.addLine(to: P(r.maxX - 60, r.minY + 94)); p.addLine(to: P(r.minX + 94, r.maxY - 60)); p.closeSubpath()
        }
        c.shadowOnly(diag, dx: 8, dy: 10, blur: 10, color: hex(0x000000, 0.7))
        c.stroke(diag, hex(0x120604), 6)
        c.wood(diag, base: hex(0x4E2C1C), light: hex(0x80502E), dark: hex(0x22100A), grainAngle: -.pi / 4, seed: 12)
        let L = c.lightDir()
        c.innerShadow(diag, dx: -L.dx * 6, dy: -L.dy * 6, blur: 4, color: hex(0xD8A070, 0.5))
        c.innerShadow(diag, dx: L.dx * 6, dy: L.dy * 6, blur: 5, color: hex(0x0A0402, 0.7))
        // frame bevel
        c.save {
            c.ctx.addPath(combine([box, inner])); c.ctx.clip(using: .evenOdd)
            c.innerShadow(box, dx: -L.dx * 8, dy: -L.dy * 8, blur: 6, color: hex(0xD8A070, 0.45))
            c.innerShadow(box, dx: L.dx * 10, dy: L.dy * 10, blur: 8, color: hex(0x0A0402, 0.7))
        }
        // nails
        for (x, y) in [(CGFloat(120), CGFloat(44)), (256, 44), (392, 44), (120, 468), (256, 468), (392, 468), (44, 256), (468, 256)] {
            c.glossy(circlePath(P(x, y), 6), light: hex(0xD8D0C8), base: hex(0x6A6058), dark: hex(0x1A1410), spec: 0.8)
        }
        // brass corner brackets
        for (cx, cy) in [(r.minX, r.minY), (r.maxX, r.minY), (r.minX, r.maxY), (r.maxX, r.maxY)] {
            let sx: CGFloat = cx == r.minX ? 1 : -1, sy: CGFloat = cy == r.minY ? 1 : -1
            let br = buildPath { p in
                p.move(to: P(cx + 6 * sx, cy + 30 * sy))
                p.addQuadCurve(to: P(cx + 30 * sx, cy + 6 * sy), control: P(cx + 6 * sx, cy + 6 * sy))
                p.addLine(to: P(cx + 104 * sx, cy + 6 * sy)); p.addLine(to: P(cx + 104 * sx, cy + 42 * sy))
                p.addLine(to: P(cx + 42 * sx, cy + 42 * sy)); p.addLine(to: P(cx + 42 * sx, cy + 104 * sy))
                p.addLine(to: P(cx + 6 * sx, cy + 104 * sy)); p.closeSubpath()
            }
            c.shadowOnly(br, dx: 4, dy: 6, blur: 6, color: hex(0x000000, 0.6))
            c.stroke(br, Metal.brass.edge, 6)
            c.metalPlate(br, .brass, bevel: 6)
            for (dx, dy) in [(CGFloat(24), CGFloat(24)), (72, 24), (24, 72)] {
                c.glossy(circlePath(P(cx + dx * sx, cy + dy * sy), 7), light: hex(0xFFF0C8), base: hex(0xB07A3A), dark: hex(0x3A220A), spec: 1)
            }
        }
    }

    // MARK: VC17 Ice overlay (transparent centre)
    static func ice(_ c: Canvas) {
        let r = CGRect(x: 16, y: 16, width: 480, height: 480)
        let shell = rrectPath(r, 44)
        let hole = rrectPath(r.insetBy(dx: 70, dy: 70), 60)
        // frosted rim fading toward a clear centre
        c.layer {
            c.fill(shell, hex(0xCDEEFF, 0.72))
            c.blurred(radius: 34, blend: .destinationOut) { off in off.fill(hole, RGBA.black.alpha(0.9)) }
        }
        let L = c.lightDir()
        c.layer(alpha: 0.9) {
            c.innerShadow(shell, dx: -L.dx * 16, dy: -L.dy * 16, blur: 12, color: hex(0xFFFFFF, 0.9))
            c.innerShadow(shell, dx: L.dx * 18, dy: L.dy * 18, blur: 16, color: hex(0x3A86D8, 0.75))
        }
        c.stroke(shell, hex(0x2C6CB8, 0.85), 6)
        c.stroke(rrectPath(r.insetBy(dx: 6, dy: 6), 38), hex(0xFFFFFF, 0.55), 3)
        // thin blue cracks from the corners and edges
        var rng = RNG(31)
        let starts: [CGPoint] = [P(40, 60), P(470, 90), P(450, 460), P(70, 440), P(256, 24), P(488, 280), P(30, 250)]
        for s in starts {
            var p = s
            var dir = (P(256, 256) - s).norm.rotated(rng.range(-0.5, 0.5))
            var pts = [p]
            let steps = Int(rng.range(4, 7))
            for _ in 0..<steps {
                p = p + dir * rng.range(16, 30)
                dir = dir.rotated(rng.range(-0.5, 0.5))
                pts.append(p)
            }
            c.stroke(polygonPath(pts, closed: false), hex(0x1C5CA8, 0.85), 3.2, cap: .round, join: .miter)
            c.stroke(polygonPath(pts.map { $0 + P(-1.5, -1.5) }, closed: false), hex(0xFFFFFF, 0.75), 1.4)
            // a branch
            if pts.count > 3 {
                var q = pts[2]; var d2 = dir.rotated(rng.unit() < 0.5 ? 0.9 : -0.9)
                var br = [q]
                for _ in 0..<3 { q = q + d2 * rng.range(12, 20); d2 = d2.rotated(rng.range(-0.4, 0.4)); br.append(q) }
                c.stroke(polygonPath(br, closed: false), hex(0x1C5CA8, 0.7), 2.2)
            }
        }
        // specular streaks on the upper-left bevel
        c.stroke(buildPath { p in p.move(to: P(60, 150)); p.addQuadCurve(to: P(150, 60), control: P(64, 64)) }, hex(0xFFFFFF, 0.9), 8)
        c.stroke(buildPath { p in p.move(to: P(58, 200)); p.addLine(to: P(58, 172)) }, hex(0xFFFFFF, 0.7), 5)
        for _ in 0..<8 { c.glint(P(rng.range(40, 470), rng.range(40, 470)).applying(.identity), size: rng.range(6, 12), color: hex(0xEFFBFF)) }
    }

    // MARK: VC18 Chain overlay
    static func chains(_ c: Canvas) {
        c.layer {
            c.shadowOnly(combine([polygonPath([P(70, 70), P(442, 442)], closed: false).stroked(40), polygonPath([P(442, 70), P(70, 442)], closed: false).stroked(40)]), dx: 6, dy: 10, blur: 12, color: hex(0x05010A, 0.5))
        }
        c.chain(from: P(62, 62), to: P(450, 450), link: 50, metal: .bronze)
        c.chain(from: P(450, 62), to: P(62, 450), link: 50, metal: .bronze)
        // round clasp
        let ring = circlePath(P(256, 256), 46)
        c.stroke(ring, Metal.bronze.edge, 30)
        c.metalRim(ring, width: 22, metal: .gold)
        let plate = circlePath(P(256, 256), 30)
        c.stroke(plate, Metal.gold.edge, 5)
        c.glossy(plate, light: hex(0xFFF4C8), base: hex(0xD49A48), dark: hex(0x5A3410), spec: 1)
        c.fill(circlePath(P(256, 252), 7), hex(0x2A1606))
        c.fill(polygonPath([P(252, 254), P(260, 254), P(263, 272), P(249, 272)]), hex(0x2A1606))
        // end anchors
        for p in [P(62, 62), P(450, 62), P(62, 450), P(450, 450)] {
            let a = circlePath(p, 20)
            c.stroke(a, Metal.bronze.edge, 6)
            c.glossy(a, light: hex(0xFFE0C0), base: hex(0xA86A3C), dark: hex(0x3A1A08), spec: 1)
        }
    }

    // MARK: VC19 Shutter (closed)
    static func shutter(_ c: Canvas) {
        let r = CGRect(x: 20, y: 20, width: 472, height: 472)
        let frame = rrectPath(r, 22)
        c.dropShadow(frame, dx: 0, dy: 8, blur: 10, alpha: 0.4)
        c.stroke(frame, Metal.brass.edge, 10)
        c.metalPlate(frame, .brass, bevel: 9)
        // housing on top
        let housing = rrectPath(CGRect(x: r.minX, y: r.minY, width: r.width, height: 74), 22)
        c.stroke(housing, Metal.brass.edge, 6)
        c.linear(housing, [(0, hex(0xFFE9B8)), (0.3, hex(0xD9A45A)), (0.7, hex(0x8E5A26)), (1, hex(0x5A3410))], P(0, r.minY), P(0, r.minY + 74))
        for x in stride(from: CGFloat(70), through: 440, by: 74) {
            c.glossy(circlePath(P(x, r.minY + 37), 8), light: hex(0xFFF0C8), base: hex(0xB07A3A), dark: hex(0x3A220A), spec: 1)
        }
        // crimson slats between the guide rails
        let inner = CGRect(x: r.minX + 52, y: r.minY + 74, width: r.width - 104, height: r.height - 74 - 52)
        c.fill(rectPath(inner), hex(0x2A0610))
        let n = 7
        let sh = inner.height / CGFloat(n)
        for k in 0..<n {
            let sr = CGRect(x: inner.minX, y: inner.minY + CGFloat(k) * sh, width: inner.width, height: sh - 3)
            let slat = rrectPath(sr, 6)
            c.linear(slat, [(0, hex(0xF26A80)), (0.18, hex(0xD8304E)), (0.6, hex(0xA51F3E)), (1, hex(0x520A1E))], P(0, sr.minY), P(0, sr.maxY))
            c.linear(slat, [(0, RGBA.white.alpha(0.18)), (0.5, RGBA.clear), (1, RGBA.black.alpha(0.2))], P(sr.minX, 0), P(sr.maxX, 0))
            c.stroke(polygonPath([P(sr.minX + 4, sr.minY + 3), P(sr.maxX - 4, sr.minY + 3)], closed: false), hex(0xFFC0C8, 0.55), 2)
        }
        c.innerShadow(rectPath(inner), dx: 0, dy: 14, blur: 14, color: hex(0x000000, 0.6))
        // guide rails
        for gx in [r.minX + 26, r.maxX - 26] {
            let rail = rrectPath(CGRect(x: gx - 16, y: r.minY + 70, width: 32, height: r.height - 116), 10)
            c.stroke(rail, Metal.brass.edge, 6)
            c.metalPlate(rail, .brass, bevel: 6)
            c.stroke(polygonPath([P(gx, r.minY + 80), P(gx, r.maxY - 56)], closed: false), hex(0x3A220A, 0.7), 5)
        }
        // bottom bar with handle
        let bar = rrectPath(CGRect(x: r.minX + 40, y: r.maxY - 58, width: r.width - 80, height: 40), 12)
        c.stroke(bar, Metal.brass.edge, 6)
        c.metalPlate(bar, .gold, bevel: 7)
        let handle = rrectPath(CGRect(x: 216, y: r.maxY - 50, width: 80, height: 22), 11)
        c.stroke(handle, Metal.gold.edge, 5)
        c.glossy(handle, light: hex(0xFFF6D0), base: hex(0xD8A04A), dark: hex(0x5A3410), spec: 1)
    }

    // MARK: VC20 Switch pedal
    static func switchPedal(_ c: Canvas) {
        let r = CGRect(x: 56, y: 56, width: 400, height: 400)
        let niche = rrectPath(r, 48)
        c.dropShadow(niche, dx: 0, dy: 6, blur: 8, alpha: 0.35)
        c.stroke(niche, Metal.brass.edge, 10)
        c.metalRim(niche, width: 12, metal: .brass)
        c.velvet(niche.transformed(.identity), base: hex(0x3A1848), sheen: hex(0x7A4690), deep: hex(0x12061A), sheenWidth: 40, texture: 0.14)
        c.innerShadow(niche, dx: 14, dy: 18, blur: 20, color: hex(0x000000, 0.75))
        c.metalRim(niche, width: 12, metal: .brass)
        let pc = P(256, 256)
        let ringP = circlePath(pc, 132)
        c.shadowOnly(ringP, dx: 8, dy: 14, blur: 14, color: hex(0x000000, 0.7))
        c.stroke(ringP, Metal.brass.edge, 8)
        c.metalPlate(ringP, .brass, bevel: 10)
        let pad = circlePath(pc, 100)
        c.stroke(pad, Metal.brass.edge.alpha(0.8), 5)
        c.glossy(pad, light: hex(0xFFEFC0), base: hex(0xC8903E), dark: hex(0x5A3412), spec: 0.9, specSize: 1.2, occlusion: 0.5)
        c.clip(pad) {
            for rr in stride(from: CGFloat(24), through: 90, by: 16) { c.stroke(circlePath(pc, rr), hex(0x6A4012, 0.35), 2.5) }
        }
        let boss = circlePath(pc, 24)
        c.stroke(boss, Metal.brass.edge, 4)
        c.glossy(boss, light: hex(0xFFF6D8), base: hex(0xE0A84A), dark: hex(0x6A3E10), spec: 1)
        for k in 0..<4 {
            let a = CGFloat(k) * .pi / 2 + .pi / 4
            c.glossy(circlePath(pc + P(cos(a), sin(a)) * 118, 7), light: hex(0xFFF0C8), base: hex(0xB07A3A), dark: hex(0x3A220A), spec: 1)
        }
    }

    // MARK: VC21 Baffle
    static func baffle(_ c: Canvas) {
        let r = CGRect(x: 18, y: 18, width: 476, height: 476)
        let plate = rrectPath(r, 30)
        c.dropShadow(plate, dx: 0, dy: 8, blur: 10, alpha: 0.4)
        c.stroke(plate, hex(0x05020A), 10)
        c.metalPlate(plate, .darkPlumMetal, bevel: 14, soften: 0.8)
        // quiet embossed cross-brace
        let inset = r.insetBy(dx: 64, dy: 64)
        let ip = rrectPath(inset, 16)
        c.stroke(ip, hex(0x0A040E, 0.9), 6)
        c.stroke(ip.transformed(CGAffineTransform(translationX: -2, y: -2)), hex(0x7A5A88, 0.35), 2)
        c.clip(ip) {
            for (a, b) in [(P(inset.minX, inset.minY), P(inset.maxX, inset.maxY)), (P(inset.maxX, inset.minY), P(inset.minX, inset.maxY))] {
                c.stroke(polygonPath([a, b], closed: false), hex(0x0A040E, 0.8), 30)
                c.stroke(polygonPath([a + P(-3, -3), b + P(-3, -3)], closed: false), hex(0x5A4066, 0.45), 20)
                c.stroke(polygonPath([a, b], closed: false), hex(0x2A1A30), 18)
            }
        }
        c.fabricGrain(plate, alpha: 0.08, fibre: 0)
        // gold rivets
        for (x, y) in [(CGFloat(48), CGFloat(48)), (256, 44), (464, 48), (44, 256), (468, 256), (48, 464), (256, 468), (464, 464)] {
            let rv = circlePath(P(x, y), 12)
            c.stroke(rv, hex(0x1A0A06), 4)
            c.glossy(rv, light: hex(0xFFF4C8), base: hex(0xD49A48), dark: hex(0x5A3410), spec: 1)
        }
    }

    // MARK: VC22 Velvet plate (floor tile under gems)
    static func velvetPlate(_ c: Canvas) {
        let r = CGRect(x: 14, y: 14, width: 484, height: 484)
        let tile = rrectPath(r, 34)
        c.dropShadow(tile, dx: 0, dy: 4, blur: 6, alpha: 0.30)
        c.velvet(tile, base: hex(0x4A1D58), sheen: hex(0x8E4EA6), deep: hex(0x220A2C), sheenWidth: 56, texture: 0.2)
        // red piping (rope) around the border
        let piping = rrectPath(r.insetBy(dx: 16, dy: 16), 22)
        c.stroke(piping, hex(0x2A0410), 22)
        let (a, b) = c.lightAxis(r)
        c.linear(piping.stroked(15), [(0, hex(0xFF7088)), (0.35, hex(0xD02846)), (0.7, hex(0x8A1030)), (1, hex(0x4A0418))], a, b)
        c.clip(piping.stroked(15)) {
            let flat = flatten(piping, step: 10).first ?? []
            for (k, p) in flat.enumerated() where k % 1 == 0 {
                c.stroke(polygonPath([p + P(-4, -4), p + P(4, 4)], closed: false), hex(0x5A0A1E, 0.55), 2.2)
            }
        }
        c.stroke(piping.transformed(CGAffineTransform(translationX: -2, y: -2)), hex(0xFFB0C0, 0.35), 2)
        // one neat gold diamond stitch at the centre
        let d = [P(256, 196), P(300, 256), P(256, 316), P(212, 256)]
        let dia = polygonPath(d)
        c.save {
            c.ctx.setLineDash(phase: 0, lengths: [14, 8])
            c.stroke(dia, hex(0x2A1606, 0.8), 8, cap: .round, join: .round)
            c.ctx.setLineDash(phase: 0, lengths: [14, 8])
            c.stroke(dia, hex(0xF0C060), 5, cap: .round, join: .round)
        }
        // stitch dimple
        c.blob(P(256, 256), rx: 40, ry: 40, color: hex(0x12040E, 0.35))
        c.glossy(circlePath(P(256, 256), 9), light: hex(0xFFF4C8), base: hex(0xD49A48), dark: hex(0x5A3410), spec: 1)
    }

    // MARK: VC24/25 Curtains (768×2048, alpha)
    static func curtain(_ c: Canvas, right: Bool) {
        let body = {
            // heading: gathered top on rings
            let d = Drape(rect: CGRect(x: -20, y: 44, width: 700, height: 1880), colors: .crimson, folds: 9, outerLeft: true, pinchY: nil, sway: 0, seed: 77, hemDepth: 40, tassel: false, lightFromTop: 0.25)
            let sil = c.drape(d)
            _ = sil
            // gold fringe down the leading (inner) edge
            let edgeX: CGFloat = 680
            let fr = buildPath { p in p.move(to: P(edgeX - 2, 60)); p.addLine(to: P(edgeX + 4, 1930)) }
            c.stroke(fr, hex(0x2A1606), 26)
            c.metalRim(fr, width: 18, metal: .gold, bbox: CGRect(x: edgeX - 20, y: 60, width: 40, height: 400))
            // rod rings
            for k in 0..<7 {
                let x = 30 + CGFloat(k) * 104
                let ring = ellipsePath(P(x, 44), 20, 16)
                c.stroke(ring, hex(0x2A1606), 12)
                c.metalRim(ring, width: 7, metal: .brass)
            }
            // rope & tassel hanging at the leading edge
            let rope = buildPath { p in p.move(to: P(edgeX - 14, 980)); p.addCurve(to: P(edgeX - 40, 1270), control1: P(edgeX + 30, 1060), control2: P(edgeX - 50, 1180)) }
            c.stroke(rope, hex(0x2A1606), 22)
            c.metalRim(rope, width: 15, metal: .gold)
            c.tassel(at: P(edgeX - 40, 1262), size: 200)
        }
        c.layer {
            if right {
                // mirror the fabric geometry, keep light from the upper-left (lightDir() follows the CTM)
                c.transform(CGAffineTransform(translationX: 768, y: 0).scaledBy(x: -1, y: 1)) { body() }
            } else { body() }
            // keep the top corners transparent (gathered heading)
            c.ctx.setBlendMode(.destinationOut)
            for x in stride(from: CGFloat(-52), through: 820, by: 104) {
                c.fill(ellipsePath(P(x, 0), 44, 38), RGBA.black)
            }
            // fade the soft cast shadow out before the bottom edge
            c.linear(rectPath(CGRect(x: 0, y: 1990, width: 768, height: 58)), [(0, RGBA.black.alpha(0)), (0.6, RGBA.black), (1, RGBA.black)], P(0, 1990), P(0, 2048))
        }
    }

    // MARK: VC26 Spotlight beam
    static func spotlightBeam(_ c: Canvas) {
        let apex = P(512, 40)
        let bottomY: CGFloat = 940
        let halfW: CGFloat = 330
        let cone = polygonPath([apex + P(-26, 0), apex + P(26, 0), P(512 + halfW, bottomY), P(512 - halfW, bottomY)])
        c.blurred(radius: 26) { off in
            // warm diffuse volume, brighter toward the rims, clearer centre
            off.linear(cone, [(0, hex(0xFFE6A8, 0.75)), (0.5, hex(0xFFD26E, 0.38)), (1, hex(0xFFC060, 0.0))], apex, P(512, bottomY))
            off.clip(cone) {
                off.ctx.setBlendMode(.destinationOut)
                off.linear(nil, [(0, RGBA.black.alpha(0)), (0.35, RGBA.black.alpha(0.55)), (0.5, RGBA.black.alpha(0.62)), (0.65, RGBA.black.alpha(0.55)), (1, RGBA.black.alpha(0))], P(512 - halfW, 0), P(512 + halfW, 0))
            }
            // pool of light on the floor
            off.radialEllipse(nil, [(0, hex(0xFFD98A, 0.40)), (1, hex(0xFFD98A, 0))], center: P(512, bottomY - 30), rx: halfW * 1.05, ry: 60)
        }
        // dust motes
        var rng = RNG(404)
        for _ in 0..<140 {
            let t = rng.range(0.1, 0.95)
            let s = rng.range(-0.9, 0.9)
            let y = apex.y + (bottomY - apex.y) * t
            let x = 512 + s * (26 + (halfW - 26) * t)
            let rr = rng.range(1.2, 4.2)
            let a = rng.range(0.25, 0.85) * (1 - t * 0.5)
            c.blob(P(x, y), rx: rr * 2.4, ry: rr * 2.4, color: hex(0xFFE9B0, a * 0.45))
            c.fill(circlePath(P(x, y), rr * 0.55), hex(0xFFF6DC, a))
        }
    }

    // MARK: VC36 App icon (1024 RGB, full bleed)
    static func appIcon(_ c: Canvas) {
        let W: CGFloat = 1024
        c.radial(rectPath(c.bounds), [(0, hex(0x5A2468)), (0.55, hex(0x2E1238)), (1, hex(0x14061C))], center: P(460, 420), radius: 760)
        c.fabricGrain(nil, alpha: 0.12, fibre: 0.4)
        // soft spotlight
        c.layer(blend: .screen) { c.radialEllipse(nil, [(0, hex(0xFFD26E, 0.28)), (1, hex(0xFFD26E, 0))], center: P(512, 560), rx: 460, ry: 460) }
        // quarter-turn golden arc around the diamond (lower-right quadrant), tapered tail, bright head
        let ac = P(512, 712), ar: CGFloat = 284
        let arcPts = (0...40).map { k -> CGPoint in let a = deg(-10) + CGFloat(k) / 40 * deg(100); return ac + P(cos(a), sin(a)) * ar }
        let widths = (0...40).map { k -> CGFloat in 14 + 50 * pow(1 - CGFloat(k) / 40, 0.8) }
        let arc = taperedPath(arcPts, widths: widths, roundCaps: true)
        c.shadowOnly(arc, dx: 10, dy: 16, blur: 22, color: hex(0x05010A, 0.8))
        c.stroke(arc, Metal.gold.edge, 12)
        c.metalFill(arc, .gold, bbox: CGRect(x: ac.x - ar, y: ac.y - ar, width: 2 * ar, height: 2 * ar))
        c.clip(arc) { c.stroke(smoothPath(arcPts.map { ac + ($0 - ac) * 0.985 }, closed: false), hex(0xFFF8DC, 0.7), 7) }
        // mirrored counter arc (upper-left) completes the "turn" read
        let arcPts2 = (0...40).map { k -> CGPoint in let a = deg(170) + CGFloat(k) / 40 * deg(100); return ac + P(cos(a), sin(a)) * ar }
        let arc2 = taperedPath(arcPts2, widths: widths, roundCaps: true)
        c.shadowOnly(arc2, dx: 10, dy: 16, blur: 22, color: hex(0x05010A, 0.8))
        c.stroke(arc2, Metal.gold.edge, 12)
        c.metalFill(arc2, .gold, bbox: CGRect(x: ac.x - ar, y: ac.y - ar, width: 2 * ar, height: 2 * ar))
        // sapphire diamond
        c.layer(blend: .screen) { c.blob(ac, rx: 250, ry: 250, color: hex(0x369FEE, 0.32)) }
        Gems.diamond(c, center: ac + P(0, 14), scale: 210, shadow: true)
        // big Vell hat above, crowning the diamond
        vellHat(c, at: P(W / 2 + 8, 598), size: 282)
        _ = W
    }

    // MARK: VC38 Hint ticket
    static func ticket(_ c: Canvas) {
        let r = CGRect(x: 44, y: 128, width: 424, height: 256)
        let t = buildPath { p in
            let rr: CGFloat = 22, notch: CGFloat = 30
            p.move(to: P(r.minX + rr, r.minY))
            p.addLine(to: P(r.maxX - rr, r.minY)); p.addQuadCurve(to: P(r.maxX, r.minY + rr), control: P(r.maxX, r.minY))
            p.addLine(to: P(r.maxX, r.midY - notch))
            p.addArc(center: P(r.maxX, r.midY), radius: notch, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
            p.addLine(to: P(r.maxX, r.maxY - rr)); p.addQuadCurve(to: P(r.maxX - rr, r.maxY), control: P(r.maxX, r.maxY))
            p.addLine(to: P(r.minX + rr, r.maxY)); p.addQuadCurve(to: P(r.minX, r.maxY - rr), control: P(r.minX, r.maxY))
            p.addLine(to: P(r.minX, r.midY + notch))
            p.addArc(center: P(r.minX, r.midY), radius: notch, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
            p.addLine(to: P(r.minX, r.minY + rr)); p.addQuadCurve(to: P(r.minX + rr, r.minY), control: P(r.minX, r.minY))
            p.closeSubpath()
        }
        c.stroke(t, hex(0x5A3A1A), 8)
        let (a, b) = c.lightAxis(r)
        c.linear(t, [(0, hex(0xFFFBEE)), (0.5, hex(0xFFF0D4)), (1, hex(0xE8D2AE))], a, b)
        c.fabricGrain(t, alpha: 0.10, fibre: 0.1)
        let L = c.lightDir()
        c.innerShadow(t, dx: L.dx * 10, dy: L.dy * 10, blur: 12, color: hex(0x8A6A40, 0.45))
        c.innerShadow(t, dx: -L.dx * 5, dy: -L.dy * 5, blur: 4, color: hex(0xFFFFFF, 0.8))
        // thin gold border (inset), following the notches
        let inset = buildPath { p in
            let q = r.insetBy(dx: 22, dy: 22), notch: CGFloat = 46
            p.move(to: P(q.minX, q.minY)); p.addLine(to: P(q.maxX, q.minY)); p.addLine(to: P(q.maxX, q.midY - notch * 0.6))
            p.addArc(center: P(r.maxX, r.midY), radius: notch, startAngle: -.pi * 0.72, endAngle: .pi * 0.72, clockwise: true)
            p.addLine(to: P(q.maxX, q.maxY)); p.addLine(to: P(q.minX, q.maxY)); p.addLine(to: P(q.minX, q.midY + notch * 0.6))
            p.addArc(center: P(r.minX, r.midY), radius: notch, startAngle: .pi * 0.28, endAngle: -.pi * 0.28, clockwise: true)
            p.closeSubpath()
        }
        c.stroke(inset, hex(0x5A3410, 0.5), 7)
        c.metalRim(inset, width: 4.5, metal: .gold)
        // embossed sapphire star
        let sc = P(256, 256)
        let sp = starPoints(sc, outer: 70, inner: 34)
        let star = roundedPolygon(sp, radius: 6)
        c.shadowOnly(star, dx: 3, dy: 5, blur: 6, color: hex(0x3A2A18, 0.45))
        c.stroke(star, hex(0x0A2250), 6)
        c.clip(star) {
            c.fill(star, GemColors.sapphire.deep)
            for i in 0..<sp.count {
                let j = (i + 1) % sp.count
                let a3 = V3(sp[i].x, sp[i].y, 0), b3 = V3(sp[j].x, sp[j].y, 0), apex = V3(sc.x, sc.y, 40)
                var n = (b3 - a3).cross(apex - a3).norm
                if n.z < 0 { n = V3(-n.x, -n.y, -n.z) }
                c.fill(polygonPath([sc, scalePoints([sp[i]], about: sc, 1.2)[0], scalePoints([sp[j]], about: sc, 1.2)[0]]), facetColor(n, .sapphire))
            }
        }
        c.metalRim(star, width: 5, metal: .gold)
        c.glint(sc + P(-18, -24), size: 12)
        // perforation dots near the stub (no text)
        for k in 0..<7 { c.fill(circlePath(P(r.maxX - 84, r.minY + 36 + CGFloat(k) * 31), 3.5), hex(0xB89A70, 0.8)) }
    }

    // MARK: VC39 Result crest (1024×512)
    static func crest(_ c: Canvas) {
        let cc = P(512, 236)
        // laurel branches (behind the cartouche)
        for s in [CGFloat(-1), 1] {
            let stem = (0...30).map { k -> CGPoint in
                let t = CGFloat(k) / 30
                let a = deg(100 + 150 * t * 0.9)
                return cc + P(s * cos(a) * -340 * (1 - 0.08 * t), sin(a) * 170 + 60)
            }
            c.stroke(smoothPath(stem, closed: false), Metal.gold.edge, 14)
            c.metalRim(smoothPath(stem, closed: false), width: 8, metal: .gold)
            for k in stride(from: 2, to: 30, by: 2) {
                let p = stem[k]
                let d = (stem[min(30, k + 1)] - stem[k - 1]).norm
                for side in [CGFloat(-1), 1] {
                    let ang = atan2(d.y, d.x) + side * deg(40)
                    let lc = p + P(cos(ang), sin(ang)) * 30
                    let leaf = rotatedEllipse(lc, 32, 13, ang)
                    c.stroke(leaf, Metal.gold.edge, 5)
                    c.metalFill(leaf, .gold, bbox: leaf.bbox.insetBy(dx: -30, dy: -30))
                    c.stroke(polygonPath([p, lc + P(cos(ang), sin(ang)) * 24], closed: false), hex(0x6A4012, 0.6), 2)
                }
            }
        }
        // cartouche
        let cart = buildPath { p in
            p.move(to: P(cc.x - 250, cc.y))
            p.addCurve(to: P(cc.x, cc.y - 150), control1: P(cc.x - 250, cc.y - 110), control2: P(cc.x - 150, cc.y - 150))
            p.addCurve(to: P(cc.x + 250, cc.y), control1: P(cc.x + 150, cc.y - 150), control2: P(cc.x + 250, cc.y - 110))
            p.addCurve(to: P(cc.x, cc.y + 150), control1: P(cc.x + 250, cc.y + 110), control2: P(cc.x + 150, cc.y + 150))
            p.addCurve(to: P(cc.x - 250, cc.y), control1: P(cc.x - 150, cc.y + 150), control2: P(cc.x - 250, cc.y + 110))
            p.closeSubpath()
        }
        c.dropShadow(cart, dx: 6, dy: 12, blur: 18, alpha: 0.5)
        c.stroke(cart, Metal.brass.edge, 12)
        c.metalPlate(cart, .brass, bevel: 12)
        // scroll ends
        for s in [CGFloat(-1), 1] {
            let sc = P(cc.x + s * 262, cc.y)
            let scroll = buildPath { p in p.addArc(center: sc, radius: 30, startAngle: 0, endAngle: .pi * 1.7, clockwise: s < 0) }
            c.stroke(scroll, Metal.brass.edge, 20)
            c.metalRim(scroll, width: 13, metal: .brass)
            c.glossy(circlePath(sc, 11), light: hex(0xFFF0C8), base: hex(0xC08840), dark: hex(0x5A3412), spec: 1)
        }
        // crest top ornament (gem, no symbols)
        let top = polygonPath([P(cc.x, cc.y - 186), P(cc.x + 30, cc.y - 150), P(cc.x, cc.y - 118), P(cc.x - 30, cc.y - 150)])
        c.stroke(top, hex(0x2A020C), 6)
        c.linear(top, [(0, hex(0xFF7A8C)), (0.5, hex(0xC8102F)), (1, hex(0x4A0414))], P(cc.x - 26, cc.y - 180), P(cc.x + 26, cc.y - 122))
        c.metalRim(top, width: 5, metal: .gold)
        // empty dark-plum field
        let field = buildPath { p in
            p.move(to: P(cc.x - 206, cc.y))
            p.addCurve(to: P(cc.x, cc.y - 118), control1: P(cc.x - 206, cc.y - 86), control2: P(cc.x - 120, cc.y - 118))
            p.addCurve(to: P(cc.x + 206, cc.y), control1: P(cc.x + 120, cc.y - 118), control2: P(cc.x + 206, cc.y - 86))
            p.addCurve(to: P(cc.x, cc.y + 118), control1: P(cc.x + 206, cc.y + 86), control2: P(cc.x + 120, cc.y + 118))
            p.addCurve(to: P(cc.x - 206, cc.y), control1: P(cc.x - 120, cc.y + 118), control2: P(cc.x - 206, cc.y + 86))
            p.closeSubpath()
        }
        c.stroke(field, Metal.brass.edge, 8)
        c.velvet(field, base: hex(0x2E1238), sheen: hex(0x5E3070), deep: hex(0x12061A), sheenWidth: 34, texture: 0.12)
        c.innerShadow(field, dx: 8, dy: 12, blur: 14, color: hex(0x000000, 0.7))
        c.metalRim(field, width: 7, metal: .gold)
        // red ribbon below
        let rib = buildPath { p in
            p.move(to: P(cc.x - 230, cc.y + 132))
            p.addQuadCurve(to: P(cc.x + 230, cc.y + 132), control: P(cc.x, cc.y + 196))
            p.addLine(to: P(cc.x + 226, cc.y + 184))
            p.addQuadCurve(to: P(cc.x - 226, cc.y + 184), control: P(cc.x, cc.y + 248))
            p.closeSubpath()
        }
        for s in [CGFloat(-1), 1] {
            let tail = buildPath { p in
                p.move(to: P(cc.x + s * 210, cc.y + 128)); p.addLine(to: P(cc.x + s * 320, cc.y + 150))
                p.addLine(to: P(cc.x + s * 292, cc.y + 176)); p.addLine(to: P(cc.x + s * 328, cc.y + 206))
                p.addLine(to: P(cc.x + s * 214, cc.y + 188)); p.closeSubpath()
            }
            c.stroke(tail, hex(0x2A020C), 8)
            c.linear(tail, [(0, hex(0x7A0A22)), (1, hex(0xB52643))], P(cc.x + s * 320, 0), P(cc.x + s * 210, 0))
        }
        c.stroke(rib, hex(0x2A020C), 8)
        c.linear(rib, [(0, hex(0xF06078)), (0.4, hex(0xC8243F)), (1, hex(0x6A0A20))], P(0, cc.y + 132), P(0, cc.y + 240))
        c.clip(rib) { c.stroke(buildPath { p in p.move(to: P(cc.x - 220, cc.y + 146)); p.addQuadCurve(to: P(cc.x + 220, cc.y + 146), control: P(cc.x, cc.y + 208)) }, hex(0xFFB0C0, 0.5), 3) }
    }

    // MARK: VC40 Turn crown
    static func turnCrown(_ c: Canvas) {
        // brass quarter-turn arc (upper quadrant) with the mini hat resting on it; open space below for the live gauge
        let ac = P(256, 452), ar: CGFloat = 196
        let arcPath = buildPath { p in p.addArc(center: ac, radius: ar, startAngle: deg(225), endAngle: deg(315), clockwise: false) }
        c.shadowOnly(arcPath.stroked(38), dx: 6, dy: 10, blur: 12, color: hex(0x05010A, 0.5))
        c.stroke(arcPath, Metal.brass.edge, 46, cap: .round)
        c.metalFill(arcPath.stroked(36, cap: .round), .brass, bbox: CGRect(x: ac.x - ar, y: ac.y - ar, width: 2 * ar, height: 2 * ar))
        c.stroke(buildPath { p in p.addArc(center: ac, radius: ar - 8, startAngle: deg(228), endAngle: deg(312), clockwise: false) }, hex(0xFFF0C8, 0.75), 5)
        c.stroke(buildPath { p in p.addArc(center: ac, radius: ar + 10, startAngle: deg(228), endAngle: deg(312), clockwise: false) }, hex(0x3A220A, 0.5), 3)
        for a in [deg(247.5), deg(292.5)] {
            let p0 = ac + P(cos(a), sin(a)) * (ar - 16), p1 = ac + P(cos(a), sin(a)) * (ar + 16)
            c.stroke(polygonPath([p0, p1], closed: false), hex(0x3A220A, 0.8), 5)
        }
        for a in [deg(225), deg(315)] {
            let cap = circlePath(ac + P(cos(a), sin(a)) * ar, 25)
            c.stroke(cap, Metal.brass.edge, 6)
            c.glossy(cap, light: hex(0xFFF0C8), base: hex(0xC89038), dark: hex(0x5A3412), spec: 1)
        }
        // mini hat (same three unequal points, colours and bells) sitting on the crest of the arc
        vellHat(c, at: P(252, 292), size: 104)
    }
}
