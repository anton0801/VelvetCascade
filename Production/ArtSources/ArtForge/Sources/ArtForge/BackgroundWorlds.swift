// BackgroundWorlds.swift — worlds 02–09 and their edge props.
import Foundation
import CoreGraphics

extension Backgrounds {

    // MARK: 02 Keyhole Wings
    static func keyholeWings(_ c: Canvas) {
        let look = WorldLook(wallTop: hex(0x241030), centerGlow: hex(0x4A2350), drape: .plum, valance: .deepPlum)
        base(c, look)
        c.stageFloor(top: H * 0.74, vanish: P(W / 2, H * 0.30), color: hex(0x1B0C1E), lineColor: hex(0x3A1E3A, 0.35))
        c.lightCone(apex: P(W / 2, -60), toward: P(W / 2, 1650), spread: deg(34), color: look.key, alpha: 0.13, seed: 12)
        sideDrapes(c, colors: look.drape, width: 120, pinchY: nil, seed: 31, folds: 4)
        keyholeColumn(c, x: 70, width: 190, top: 360, bottom: 2350, keyholes: [760, 1330], seed: 1)
        keyholeColumn(c, x: W - 260, width: 190, top: 360, bottom: 2350, keyholes: [760, 1330], seed: 2)
        c.valance(bandHeight: 110, swagDepth: 170, swags: 5, colors: look.valance)
        finish(c)
    }

    static func keyholeColumn(_ c: Canvas, x: CGFloat, width w: CGFloat, top: CGFloat, bottom: CGFloat, keyholes: [CGFloat], seed: UInt64) {
        let cx = x + w / 2
        let body = buildPath { p in
            p.move(to: P(x, bottom)); p.addLine(to: P(x, top + w / 2))
            p.addArc(center: P(cx, top + w / 2), radius: w / 2, startAngle: .pi, endAngle: 0, clockwise: false)
            p.addLine(to: P(x + w, bottom)); p.closeSubpath()
        }
        c.shadowOnly(body, dx: 16, dy: 20, blur: 36, color: hex(0x05010A, 0.85))
        c.stroke(body, hex(0x0C040E), 8)
        // lacquered dark plum wood
        c.linear(body, [(0, hex(0x5A2E62)), (0.25, hex(0x3C1C46)), (0.6, hex(0x28122F)), (1, hex(0x1A0A1E))], P(x, 0), P(x + w, 0))
        c.clip(body) {
            c.wood(body, base: hex(0x33183A), light: hex(0x5A3264), dark: hex(0x160818), grainAngle: .pi / 2, seed: seed, grainScale: 1.4)
            c.layer(blend: .multiply) { c.linear(body, [(0, hex(0xE8D0F0)), (0.5, RGBA.white), (1, hex(0x9A7AA0))], P(x, 0), P(x + w, 0)) }
        }
        // inset gold beading
        let inset = buildPath { p in
            let i: CGFloat = 22
            p.move(to: P(x + i, bottom - 60)); p.addLine(to: P(x + i, top + w / 2))
            p.addArc(center: P(cx, top + w / 2), radius: w / 2 - i, startAngle: .pi, endAngle: 0, clockwise: false)
            p.addLine(to: P(x + w - i, bottom - 60)); p.closeSubpath()
        }
        c.stroke(inset, hex(0x1A0A06), 10)
        c.metalRim(inset, width: 6, metal: .gold)
        // capital & plinth mouldings
        for (y, h) in [(top + w * 0.95, CGFloat(34)), (bottom - 70, CGFloat(46))] {
            let m = rrectPath(CGRect(x: x - 14, y: y, width: w + 28, height: h), 8)
            c.stroke(m, hex(0x1A0A06), 8)
            c.metalPlate(m, .brass, bevel: 7)
        }
        // keyhole cut-outs glowing with warm backstage light
        for ky in keyholes {
            let r = w * 0.19
            let hole = buildPath { p in
                p.addArc(center: P(cx, ky), radius: r, startAngle: deg(118), endAngle: deg(62), clockwise: false)
                p.addLine(to: P(cx + r * 0.62, ky + r * 2.7))
                p.addQuadCurve(to: P(cx - r * 0.62, ky + r * 2.7), control: P(cx, ky + r * 2.85))
                p.closeSubpath()
            }
            let plate = buildPath { p in
                p.addPath(ellipsePath(P(cx, ky + r * 0.9), r * 1.75, r * 2.6))
            }
            c.stroke(plate, hex(0x1A0A06), 8)
            c.metalPlate(plate, .gold, bevel: 8)
            // engraved ring on the escutcheon
            c.stroke(ellipsePath(P(cx, ky + r * 0.9), r * 1.45, r * 2.25), hex(0x6A4010, 0.6), 3)
            c.radial(hole, [(0, hex(0xFFF1C0)), (0.35, hex(0xFFC45A)), (0.8, hex(0xB0561A)), (1, hex(0x4A1606))], center: P(cx + r * 0.2, ky + r * 0.9), radius: r * 2.6)
            let L = c.lightDir()
            c.innerShadow(hole, dx: -L.dx * 14, dy: -L.dy * 14, blur: 10, color: hex(0x2A0A04, 0.95))
            c.stroke(hole, hex(0x2A1206), 4)
            c.layer(blend: .screen) { c.blob(P(cx, ky + r), rx: r * 3.2, ry: r * 3.6, color: hex(0xFFB84A, 0.22)) }
        }
    }

    // MARK: 03 Prop Workshop
    static func propWorkshop(_ c: Canvas) {
        let look = WorldLook(wallTop: hex(0x2A1426), centerGlow: hex(0x4E2530), drape: .burgundy, valance: .burgundy)
        base(c, look)
        c.stageFloor(top: H * 0.74, vanish: P(W / 2, H * 0.30), color: hex(0x22100E), lineColor: hex(0x4A2A1E, 0.35))
        c.lightCone(apex: P(260, -40), toward: P(420, 1300), spread: deg(20), color: hex(0xFFC878), alpha: 0.16, seed: 21)
        c.lightCone(apex: P(W - 260, -40), toward: P(W - 420, 1300), spread: deg(20), color: hex(0xFFC878), alpha: 0.16, seed: 22)
        sideDrapes(c, colors: look.drape, width: 110, pinchY: nil, seed: 41, folds: 4)
        propRack(c, left: true)
        propRack(c, left: false)
        c.valance(bandHeight: 100, swagDepth: 150, swags: 5, colors: look.valance)
        finish(c)
    }

    static func propRack(_ c: Canvas, left: Bool) {
        let x0: CGFloat = left ? 36 : W - 286, x1: CGFloat = x0 + 250
        let shelves: [CGFloat] = [700, 1160, 1640, 2120]
        let postW: CGFloat = 34
        // back posts & shelves
        for px in [x0, x1 - postW] {
            let post = rectPath(CGRect(x: px, y: 330, width: postW, height: 2100))
            c.shadowOnly(post, dx: 12, dy: 14, blur: 22, color: hex(0x05010A, 0.8))
            c.stroke(post, hex(0x120806), 6)
            c.wood(post, grainAngle: .pi / 2, seed: UInt64(px))
            let L = c.lightDir()
            c.innerShadow(post, dx: L.dx * 8, dy: L.dy * 8, blur: 8, color: hex(0x0A0402, 0.7))
        }
        var rng = RNG(left ? 7 : 8)
        for (si, sy) in shelves.enumerated() {
            // items on the shelf
            var cx = x0 + 26
            let items = si == 3 ? 1 : 2
            for k in 0..<items {
                let wBox = rng.range(80, 118) * (items == 1 ? 1.2 : 1)
                let hBox = rng.range(70, 110)
                let r = CGRect(x: cx, y: sy - hBox, width: wBox, height: hBox)
                if (k + si) % 2 == 0 { woodCrate(c, r, seed: UInt64(si * 10 + k)) } else { brassBox(c, r) }
                cx += wBox + 14
            }
            let plank = rectPath(CGRect(x: x0 - 16, y: sy, width: x1 - x0 + 32, height: 26))
            c.shadowOnly(plank, dx: 6, dy: 16, blur: 18, color: hex(0x05010A, 0.85))
            c.stroke(plank, hex(0x120806), 6)
            c.wood(plank, base: hex(0x5A3420), light: hex(0x8A5836), dark: hex(0x2A140A), seed: UInt64(sy))
            // brass bracket
            for bx in [x0 + 4, x1 - 30] {
                let br = polygonPath([P(bx, sy + 26), P(bx + 26, sy + 26), P(bx + 26, sy + 30), P(bx + 4, sy + 62)])
                c.stroke(br, hex(0x1A0A04), 4); c.metalFill(br, .brass)
            }
        }
    }

    static func woodCrate(_ c: Canvas, _ r: CGRect, seed: UInt64) {
        let box = rectPath(r)
        c.shadowOnly(box, dx: 8, dy: 6, blur: 12, color: hex(0x05010A, 0.7))
        c.stroke(box, hex(0x120806), 6)
        c.wood(box, base: hex(0x4A2A1A), light: hex(0x7A4A2C), dark: hex(0x22100A), seed: seed)
        c.stroke(polygonPath([P(r.minX + 8, r.maxY - 8), P(r.maxX - 8, r.minY + 8)], closed: false), hex(0x2A160C), 12)
        c.stroke(polygonPath([P(r.minX + 8, r.maxY - 8), P(r.maxX - 8, r.minY + 8)], closed: false), hex(0x7A4A2C, 0.8), 6)
        let L = c.lightDir()
        c.innerShadow(box, dx: -L.dx * 6, dy: -L.dy * 6, blur: 4, color: hex(0xC08A5A, 0.5))
        c.innerShadow(box, dx: L.dx * 8, dy: L.dy * 8, blur: 6, color: hex(0x0A0402, 0.7))
        for (px, py) in [(r.minX, r.minY), (r.maxX, r.minY), (r.minX, r.maxY), (r.maxX, r.maxY)] {
            let sx: CGFloat = px == r.minX ? 1 : -1, sy: CGFloat = py == r.minY ? 1 : -1
            let corner = polygonPath([P(px, py), P(px + 22 * sx, py), P(px, py + 22 * sy)])
            c.metalFill(corner, .brass)
            c.stroke(corner, hex(0x2A1606), 2)
        }
    }

    static func brassBox(_ c: Canvas, _ r: CGRect) {
        let box = rrectPath(r, 8)
        c.shadowOnly(box, dx: 8, dy: 6, blur: 12, color: hex(0x05010A, 0.7))
        c.stroke(box, hex(0x1A0A04), 6)
        c.metalPlate(box, .brass, bevel: 8)
        let lid = rectPath(CGRect(x: r.minX, y: r.minY + r.height * 0.28, width: r.width, height: 6))
        c.fill(lid, hex(0x3A220A, 0.8))
        let lock = rrectPath(CGRect(x: r.midX - 9, y: r.minY + r.height * 0.28 - 4, width: 18, height: 22), 4)
        c.stroke(lock, hex(0x2A1606), 3); c.metalFill(lock, .gold)
        for (px, py) in [(r.minX + 10, r.minY + 10), (r.maxX - 10, r.minY + 10), (r.minX + 10, r.maxY - 10), (r.maxX - 10, r.maxY - 10)] {
            c.glossy(circlePath(P(px, py), 4.5), light: hex(0xFFF0C8), base: hex(0xB07A3A), dark: hex(0x4A2A0E), spec: 0.8)
        }
    }

    // MARK: 04 Frosted Gallery
    static func frostedGallery(_ c: Canvas) {
        let look = WorldLook(wallTop: hex(0x21122E), wallMid: hex(0x25132D), centerGlow: hex(0x55283A), drape: .plum, valance: .deepPlum, accent: hex(0x7CC8FF))
        base(c, look)
        // warm centre vs cold edges
        c.layer(blend: .screen) {
            c.linear(nil, [(0, hex(0x3A7AC8, 0.32)), (0.2, hex(0x3A7AC8, 0.0)), (0.8, hex(0x3A7AC8, 0.0)), (1, hex(0x3A7AC8, 0.32))], P(0, 0), P(W, 0))
        }
        c.stageFloor(top: H * 0.74, vanish: P(W / 2, H * 0.30), color: hex(0x1A0C20), lineColor: hex(0x3A2A48, 0.35))
        c.lightCone(apex: P(W / 2, -60), toward: P(W / 2, 1500), spread: deg(30), color: hex(0xFFCF80), alpha: 0.15, seed: 41)
        sideDrapes(c, colors: look.drape, width: 120, pinchY: nil, seed: 51, folds: 4)
        for (y, s) in [(CGFloat(640), CGFloat(1.0)), (1320, 1.1)] {
            galleryBalcony(c, y: y, left: true, scale: s, seed: UInt64(y))
            galleryBalcony(c, y: y, left: false, scale: s, seed: UInt64(y) + 3)
        }
        c.valance(bandHeight: 100, swagDepth: 150, swags: 5, colors: look.valance)
        // frost sparkle at the edges
        var rng = RNG(77)
        c.layer(blend: .screen) {
            for _ in 0..<70 {
                let left = rng.unit() < 0.5
                let x = left ? rng.range(0, 260) : rng.range(W - 260, W)
                let y = rng.range(300, 1900)
                c.glint(P(x, y), size: rng.range(4, 11), color: hex(0xCFF0FF), angle: deg(rng.range(0, 45)))
            }
        }
        finish(c)
    }

    static func galleryBalcony(_ c: Canvas, y: CGFloat, left: Bool, scale s: CGFloat, seed: UInt64) {
        let wB: CGFloat = 270 * s, hB: CGFloat = 230 * s
        let x0: CGFloat = left ? -20 : W - wB + 20
        let outer: CGFloat = left ? x0 : x0 + wB
        let inner: CGFloat = left ? x0 + wB : x0
        let dir: CGFloat = left ? 1 : -1
        let front = buildPath { p in
            p.move(to: P(outer, y + 50 * s))
            p.addLine(to: P(inner - 40 * dir, y + 50 * s))
            p.addQuadCurve(to: P(inner - 30 * dir, y + hB), control: P(inner + 20 * dir, y + hB * 0.55))
            p.addLine(to: P(outer, y + hB * 1.1))
            p.closeSubpath()
        }
        c.shadowOnly(front, dx: 14, dy: 22, blur: 34, color: hex(0x04010A, 0.85))
        c.stroke(front, hex(0x0C040E), 8)
        c.velvet(front, base: hex(0x4A1E4E), sheen: hex(0x9A5AA8), deep: hex(0x1C0A20), sheenWidth: 50, texture: 0.14)
        // gold mouldings
        c.clip(front) {
            for (yy, w) in [(y + 62 * s, CGFloat(14)), (y + hB - 28 * s, CGFloat(10))] {
                let m = buildPath { p in p.move(to: P(outer, yy)); p.addLine(to: P(inner + 40 * dir, yy)) }
                c.stroke(m, hex(0x1A0A06), w + 6); c.metalRim(m, width: w, metal: .gold)
            }
        }
        // balusters between the front's top moulding and the handrail
        var bx = outer + dir * 30
        while (bx - (inner - 50 * dir)) * dir < 0 {
            let bal = buildPath { p in
                p.move(to: P(bx - 7, y + 2)); p.addQuadCurve(to: P(bx - 7, y + 48 * s), control: P(bx - 16, y + 25 * s))
                p.addLine(to: P(bx + 7, y + 48 * s)); p.addQuadCurve(to: P(bx + 7, y + 2), control: P(bx + 16, y + 25 * s)); p.closeSubpath()
            }
            c.stroke(bal, hex(0x1A0A06), 4); c.metalFill(bal, .brass)
            bx += dir * 34
        }
        // brass handrail with frost
        let rail = buildPath { p in p.move(to: P(outer - 20 * dir, y - 4)); p.addLine(to: P(inner - 36 * dir, y - 4)) }
        c.stroke(rail, hex(0x1A0A06), 28)
        c.metalRim(rail, width: 22, metal: .brass)
        c.stroke(rail.transformed(CGAffineTransform(translationX: 0, y: -8)), hex(0xE8F8FF, 0.8), 5)
        // ice crystal clusters along the rail
        var rng = RNG(seed)
        let n = 3
        for k in 0..<n {
            let bx = outer + dir * (40 + CGFloat(k) * (wB - 90) / CGFloat(n - 1) * 0.9)
            let base = P(bx, y - 10)
            let count = 3 + Int(rng.next() % 3)
            for j in 0..<count {
                let ang = deg(rng.range(-38, 38)) + (j == 0 ? 0 : 0)
                let len = rng.range(50, 120) * s * (j == 0 ? 1.25 : 1)
                iceCrystal(c, base: base + P(rng.range(-14, 14), 0), angle: ang, length: len, width: len * rng.range(0.24, 0.32))
            }
        }
    }

    static func iceCrystal(_ c: Canvas, base: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat) {
        let d = P(sin(angle), -cos(angle))
        let n = d.perp
        let tip = base + d * length
        let pts = [base + n * (width * 0.35), base + d * (length * 0.18) + n * (width * 0.5), tip - d * (length * 0.22) + n * (width * 0.5), tip,
                   tip - d * (length * 0.22) - n * (width * 0.5), base + d * (length * 0.18) - n * (width * 0.5), base - n * (width * 0.35)]
        let shape = polygonPath(pts)
        c.layer(blend: .screen) { c.shadowOnly(shape, blur: 18, color: hex(0x7CC8FF, 0.55)) }
        c.stroke(shape, hex(0x0E2A48, 0.9), 3)
        let leftFace = polygonPath([pts[0], pts[1], pts[2], pts[3], base + d * (length * 0.95), base])
        let rightFace = polygonPath([pts[3], pts[4], pts[5], pts[6], base, base + d * (length * 0.95)])
        let L = c.lightDir()
        let litLeft = n.dot(P(L.dx, L.dy)) > 0
        c.linear(leftFace, [(0, hex(0xF2FCFF, 0.95)), (1, hex(0x8FD6FF, 0.75))], base, tip)
        c.linear(rightFace, [(0, hex(0x5AA8E8, 0.85)), (1, hex(0x2A5FA8, 0.75))], base, tip)
        if !litLeft {
            c.layer(blend: .multiply) { c.fill(leftFace, hex(0xB0C8E8)) }
        }
        c.stroke(polygonPath([base, base + d * (length * 0.95)], closed: false), hex(0xFFFFFF, 0.8), 2)
        c.stroke(shape, hex(0xE8FAFF, 0.5), 1.4)
        c.glint(tip - d * (length * 0.1), size: width * 0.35, color: hex(0xF4FDFF))
    }

    // MARK: 05 Chain Loft
    static func chainLoft(_ c: Canvas) {
        let look = WorldLook(wallTop: hex(0x1E0E26), centerGlow: hex(0x4A2240), drape: .ruby, valance: .plum)
        base(c, look)
        c.stageFloor(top: H * 0.74, vanish: P(W / 2, H * 0.30), color: hex(0x1C0C1C), lineColor: hex(0x3A1E30, 0.35))
        // loft truss across the very top
        let truss = rectPath(CGRect(x: -10, y: 150, width: W + 20, height: 44))
        c.shadowOnly(truss, dx: 0, dy: 16, blur: 20, color: hex(0x05010A, 0.8))
        c.stroke(truss, hex(0x0C0406), 6); c.metalPlate(truss, .bronze, bevel: 8)
        var x: CGFloat = 20
        while x < W { c.glossy(circlePath(P(x, 172), 7), light: hex(0xFFE0C0), base: hex(0x9A5A2C), dark: hex(0x3A1A08), spec: 0.8); x += 60 }
        c.lightCone(apex: P(330, 150), toward: P(560, 1400), spread: deg(18), color: look.key, alpha: 0.16, seed: 51)
        c.lightCone(apex: P(W - 330, 150), toward: P(W - 560, 1400), spread: deg(18), color: look.key, alpha: 0.16, seed: 52)
        sideDrapes(c, colors: look.drape, width: 190, top: 190, pinchY: 1700, seed: 61, folds: 5)
        // chains and hoists along the upper edges
        let chainsL: [(CGFloat, CGFloat, Bool)] = [(70, 980, true), (170, 640, false), (262, 460, true)]
        for (cx, len, weight) in chainsL {
            hoist(c, x: cx, length: len, weight: weight)
            hoist(c, x: W - cx, length: len * (weight ? 0.92 : 1.1), weight: !weight)
        }
        // velvet valance behind the chains' pulleys only at edges
        c.valance(top: 0, bandHeight: 110, swagDepth: 120, swags: 5, colors: look.valance, fringe: true)
        finish(c)
    }

    static func hoist(_ c: Canvas, x: CGFloat, length: CGFloat, weight: Bool) {
        let top: CGFloat = 200
        c.chain(from: P(x, top + 40), to: P(x, top + length), link: 30)
        // pulley block
        let wheel = circlePath(P(x, top + 20), 34)
        c.shadowOnly(wheel, dx: 8, dy: 12, blur: 14, color: hex(0x05010A, 0.8))
        c.stroke(wheel, Metal.bronze.edge, 8)
        c.metalFill(wheel, .bronze)
        c.stroke(circlePath(P(x, top + 20), 22), Metal.bronze.edge.alpha(0.7), 4)
        c.glossy(circlePath(P(x, top + 20), 9), light: hex(0xFFE4C4), base: hex(0xA86A3C), dark: hex(0x3A1A08), spec: 1)
        let end = P(x, top + length + 10)
        if weight {
            let wgt = rrectPath(CGRect(x: x - 30, y: end.y, width: 60, height: 110), 12)
            c.shadowOnly(wgt, dx: 10, dy: 14, blur: 16, color: hex(0x05010A, 0.8))
            c.stroke(wgt, Metal.brass.edge, 6)
            c.metalPlate(wgt, .brass, bevel: 8)
            for yy in [end.y + 28, end.y + 82] { c.stroke(polygonPath([P(x - 30, yy), P(x + 30, yy)], closed: false), hex(0x3A220A, 0.7), 4) }
        } else {
            let hook = buildPath { p in
                p.move(to: end)
                p.addLine(to: end + P(0, 40))
                p.addArc(center: end + P(-20, 40), radius: 20, startAngle: 0, endAngle: .pi * 0.95, clockwise: false)
            }
            c.stroke(hook, Metal.bronze.edge, 16)
            c.metalRim(hook, width: 10, metal: .bronze)
        }
    }

    // MARK: 06 Clockwork Curtains
    static func clockworkCurtains(_ c: Canvas) {
        let look = WorldLook(wallTop: hex(0x26122A), centerGlow: hex(0x502634), drape: .crimson, valance: .burgundy)
        base(c, look)
        c.stageFloor(top: H * 0.74, vanish: P(W / 2, H * 0.30), color: hex(0x1E0D18), lineColor: hex(0x3A1E2C, 0.35))
        c.lightCone(apex: P(200, -40), toward: P(520, 1450), spread: deg(22), color: look.key, alpha: 0.17, seed: 61)
        c.lightCone(apex: P(W - 200, -40), toward: P(W - 520, 1450), spread: deg(22), color: look.key, alpha: 0.17, seed: 62)
        sideDrapes(c, colors: look.drape, width: 150, top: 160, pinchY: nil, seed: 71, folds: 4)
        // gears in front of the drapes, cut by the frame edge
        c.gear(center: P(-60, 1060), radius: 250, teeth: 22, rotation: 0.1)
        c.gear(center: P(178, 1368), radius: 112, teeth: 12, rotation: 0.3, metal: .brass, spokes: 4)
        c.gear(center: P(W + 50, 1240), radius: 240, teeth: 20, rotation: 0.25)
        c.gear(center: P(W - 170, 936), radius: 104, teeth: 12, rotation: 0.05, metal: .brass, spokes: 4)
        // stage shutters (louvred panels) at the upper edges
        shutterPanel(c, rect: CGRect(x: 20, y: 300, width: 210, height: 420))
        shutterPanel(c, rect: CGRect(x: W - 230, y: 300, width: 210, height: 420))
        c.gear(center: P(120, 2010), radius: 96, teeth: 10, rotation: 0.2, metal: .bronze, spokes: 4)
        c.gear(center: P(W - 120, 2060), radius: 84, teeth: 10, rotation: 0.4, metal: .bronze, spokes: 4)
        c.valance(bandHeight: 110, swagDepth: 160, swags: 4, colors: look.valance)
        finish(c)
    }

    static func shutterPanel(_ c: Canvas, rect r: CGRect) {
        let frame = rrectPath(r, 12)
        c.shadowOnly(frame, dx: 12, dy: 18, blur: 26, color: hex(0x05010A, 0.85))
        c.stroke(frame, Metal.brass.edge, 8)
        c.metalPlate(frame, .brass, bevel: 9)
        let inner = r.insetBy(dx: 18, dy: 18)
        c.fill(rectPath(inner), hex(0x12060C))
        let slats = 9
        let sh = inner.height / CGFloat(slats)
        for k in 0..<slats {
            let sr = CGRect(x: inner.minX, y: inner.minY + CGFloat(k) * sh, width: inner.width, height: sh * 0.86)
            let slat = polygonPath([P(sr.minX, sr.minY), P(sr.maxX, sr.minY), P(sr.maxX, sr.maxY), P(sr.minX, sr.maxY - 4)])
            c.linear(slat, [(0, hex(0xE0506A)), (0.35, hex(0xA51F3E)), (1, hex(0x4A0A1C))], P(0, sr.minY), P(0, sr.maxY))
            c.stroke(polygonPath([P(sr.minX, sr.minY + 1), P(sr.maxX, sr.minY + 1)], closed: false), hex(0xFFB0B8, 0.5), 2)
        }
        // guide rails
        for gx in [inner.minX + 4, inner.maxX - 4] {
            let g = polygonPath([P(gx, inner.minY), P(gx, inner.maxY)], closed: false)
            c.stroke(g, Metal.brass.edge, 10); c.metalRim(g, width: 6, metal: .brass)
        }
    }

    // MARK: 07 Split Stage
    static func splitStage(_ c: Canvas) {
        let look = WorldLook(wallTop: hex(0x26122C), centerGlow: hex(0x4C2438), drape: .ruby, valance: .plum)
        base(c, look)
        // brass floor (warm metal planks, still calm)
        c.stageFloor(top: H * 0.70, vanish: P(W / 2, H * 0.28), color: hex(0x3A2412), lineColor: hex(0x8A5A2A, 0.35), planks: 22)
        c.layer(blend: .screen) {
            c.radialEllipse(nil, [(0, hex(0xC08040, 0.18)), (1, hex(0xC08040, 0))], center: P(W / 2, H * 0.80), rx: W * 0.7, ry: 300)
        }
        c.lightCone(apex: P(W / 2, -60), toward: P(W / 2, 1800), spread: deg(30), color: look.key, alpha: 0.14, seed: 71)
        pavilion(c, left: true)
        pavilion(c, left: false)
        c.valance(bandHeight: 100, swagDepth: 140, swags: 5, colors: look.valance)
        finish(c, vignette: 0.55)
    }

    static func pavilion(_ c: Canvas, left: Bool) {
        let x0: CGFloat = left ? -40 : W - 300, x1 = x0 + 340
        let floorY: CGFloat = 1760, roofY: CGFloat = 640, capY: CGFloat = 880
        // inner curtain inside the pavilion
        let inner = CGRect(x: x0 + 40, y: capY, width: x1 - x0 - 80, height: floorY - capY)
        c.drape(Drape(rect: inner, colors: .crimson, folds: 4, outerLeft: left, pinchY: 1260, pinch: 0.5, seed: left ? 5 : 6, hemDepth: 0, tassel: true))
        // platform
        let plat = rrectPath(CGRect(x: x0, y: floorY, width: x1 - x0, height: 70), 10)
        c.shadowOnly(plat, dx: 10, dy: 20, blur: 24, color: hex(0x05010A, 0.85))
        c.stroke(plat, Metal.brass.edge, 8)
        c.metalPlate(plat, .brass, bevel: 10)
        // columns
        for cx in [x0 + 40, x1 - 40] {
            let col = rectPath(CGRect(x: cx - 22, y: capY, width: 44, height: floorY - capY))
            c.shadowOnly(col, dx: 10, dy: 10, blur: 16, color: hex(0x05010A, 0.7))
            c.stroke(col, Metal.gold.edge, 6)
            c.metalFill(col, .gold, bbox: CGRect(x: cx - 30, y: capY, width: 60, height: 60))
            c.clip(col) {
                for k in -1...1 { c.stroke(polygonPath([P(cx + CGFloat(k) * 12, capY), P(cx + CGFloat(k) * 12, floorY)], closed: false), hex(0x6A4010, 0.55), 3) }
            }
            let cap = rrectPath(CGRect(x: cx - 34, y: capY - 26, width: 68, height: 30), 6)
            c.stroke(cap, Metal.gold.edge, 5); c.metalPlate(cap, .gold, bevel: 6)
        }
        // canopy roof: scalloped velvet dome with gold trim
        let roof = buildPath { p in
            p.move(to: P(x0 - 30, capY - 20))
            p.addCurve(to: P((x0 + x1) / 2, roofY), control1: P(x0 - 10, capY - 160), control2: P((x0 + x1) / 2 - 90, roofY + 10))
            p.addCurve(to: P(x1 + 30, capY - 20), control1: P((x0 + x1) / 2 + 90, roofY + 10), control2: P(x1 + 10, capY - 160))
            // scalloped lower edge
            let n = 6
            for k in 0..<n {
                let xa = x1 + 30 - CGFloat(k) * (x1 - x0 + 60) / CGFloat(n)
                let xb = x1 + 30 - CGFloat(k + 1) * (x1 - x0 + 60) / CGFloat(n)
                p.addQuadCurve(to: P(xb, capY - 20), control: P((xa + xb) / 2, capY + 26))
            }
            p.closeSubpath()
        }
        c.shadowOnly(roof, dx: 12, dy: 20, blur: 26, color: hex(0x05010A, 0.85))
        c.stroke(roof, hex(0x0C040E), 8)
        c.velvet(roof, base: hex(0x5A2468), sheen: hex(0xA868BE), deep: hex(0x220A2A), sheenWidth: 40, texture: 0.14)
        c.clip(roof) {
            for k in 1..<6 {
                let xx = x0 - 30 + CGFloat(k) * (x1 - x0 + 60) / 6
                c.stroke(smoothPath([P((x0 + x1) / 2, roofY), P(lerp((x0 + x1) / 2, xx, 0.6), capY - 90), P(xx, capY - 10)], closed: false), hex(0xFFD26E, 0.55), 5)
            }
        }
        c.metalRim(roof, width: 8, metal: .gold)
        let finial = circlePath(P((x0 + x1) / 2, roofY - 18), 20)
        c.stroke(finial, Metal.gold.edge, 5)
        c.glossy(finial, light: hex(0xFFF6CC), base: hex(0xE0A84A), dark: hex(0x6E4012), spec: 1)
        // little lamps on the columns
        for cx in [x0 + 40, x1 - 40] { c.bulb(P(cx + (left ? 34 : -34), 1180), r: 13) }
    }

    // MARK: 08 Moonlit Rotation
    static func moonlitRotation(_ c: Canvas) {
        let look = WorldLook(wallTop: hex(0x1A0E28), wallMid: hex(0x221230), centerGlow: hex(0x45203E), drape: .burgundy, valance: .burgundy, accent: hex(0x5A8CFF))
        base(c, look)
        // theatre roof: night-sky skylight between dark trusses
        let sky = buildPath { p in
            p.move(to: P(0, 0)); p.addLine(to: P(W, 0)); p.addLine(to: P(W, 520))
            p.addQuadCurve(to: P(0, 520), control: P(W / 2, 250))
            p.closeSubpath()
        }
        c.linear(sky, [(0, hex(0x070C2A)), (0.6, hex(0x111C44)), (1, hex(0x1E1840))], P(0, 0), P(0, 520))
        var rng = RNG(88)
        c.clip(sky) {
            for _ in 0..<90 {
                let p = P(rng.range(0, W), rng.range(0, 480))
                c.fill(circlePath(p, rng.range(0.8, 2.4)), hex(0xDDE8FF, rng.range(0.3, 0.9)))
            }
            // small moon, top-right
            let mc = P(W - 250, 250)
            c.layer(blend: .screen) { c.blob(mc, rx: 190, ry: 190, color: hex(0x9EC0FF, 0.35)) }
            let moon = circlePath(mc, 62)
            c.radial(moon, [(0, hex(0xFFFBEA)), (0.7, hex(0xE8E6D8)), (1, hex(0xB8BCD0))], center: mc - P(18, 18), radius: 80)
            for (o, r) in [(P(14, 10), CGFloat(12)), (P(-20, 22), 8), (P(8, -26), 7)] { c.fill(circlePath(mc + o, r), hex(0xC8C8C0, 0.55)) }
        }
        // trusses / mullions
        for k in 0...8 {
            let x = W * CGFloat(k) / 8
            let beam = polygonPath([P(W / 2 + (x - W / 2) * 0.35, 0), P(x, 540)], closed: false)
            c.stroke(beam, hex(0x08040C), 14)
            c.stroke(beam, hex(0x3A2A50, 0.45), 3)
        }
        for y in [CGFloat(150), 320] {
            let arc = buildPath { p in p.move(to: P(0, y + 250)); p.addQuadCurve(to: P(W, y + 250), control: P(W / 2, y - 20)) }
            c.stroke(arc, hex(0x08040C), 14)
            c.stroke(arc, hex(0x4A3A66, 0.4), 2.5)
        }
        let rim = buildPath { p in p.move(to: P(0, 520)); p.addQuadCurve(to: P(W, 520), control: P(W / 2, 250)) }
        c.stroke(rim, hex(0x08040C), 40)
        c.metalRim(rim, width: 26, metal: .bronze)
        // moonlight shafts (cold, edges only) + warm stage light in the centre
        c.lightCone(apex: P(W - 250, 260), toward: P(W - 60, 1700), spread: deg(16), color: hex(0x8FB4FF), alpha: 0.18, dust: 40, seed: 81)
        c.lightCone(apex: P(250, 260), toward: P(60, 1600), spread: deg(14), color: hex(0x8FB4FF), alpha: 0.14, dust: 30, seed: 82)
        c.lightCone(apex: P(W / 2, 330), toward: P(W / 2, 1650), spread: deg(26), color: hex(0xFFCB78), alpha: 0.12, dust: 40, seed: 83)
        c.stageFloor(top: H * 0.74, vanish: P(W / 2, H * 0.30), color: hex(0x180C20), lineColor: hex(0x2E2248, 0.35))
        c.brassRingFragments(center: P(W / 2, H * 0.47), radius: 600, width: 52, calmHalfWidth: 340, fadeWidth: 140, bolts: 30)
        sideDrapes(c, colors: look.drape, width: 200, top: 480, pinchY: 1620, seed: 91, folds: 5)
        // blue night rim light only along the edges
        c.layer(blend: .screen) {
            c.linear(nil, [(0, hex(0x3A6AE8, 0.40)), (0.12, hex(0x3A6AE8, 0.0)), (0.88, hex(0x3A6AE8, 0.0)), (1, hex(0x3A6AE8, 0.40))], P(0, 0), P(W, 0))
        }
        finish(c)
    }

    // MARK: 09 Grand Cascade
    static func grandCascade(_ c: Canvas) {
        let look = WorldLook(wallTop: hex(0x2A1228), centerGlow: hex(0x5A2A36), drape: .crimson, valance: .ruby)
        base(c, look)
        c.stageFloor(top: H * 0.74, vanish: P(W / 2, H * 0.30), color: hex(0x221012), lineColor: hex(0x4A2622, 0.35))
        c.lightCone(apex: P(330, 380), toward: P(560, 1600), spread: deg(20), color: look.key, alpha: 0.18, seed: 91)
        c.lightCone(apex: P(W - 330, 380), toward: P(W - 560, 1600), spread: deg(20), color: look.key, alpha: 0.18, seed: 92)
        // layered red curtains: deep back layer, then the main tied-back layer
        sideDrapes(c, colors: .burgundy, width: 250, top: 300, pinchY: nil, seed: 101, folds: 6)
        sideDrapes(c, colors: look.drape, width: 215, top: 300, pinchY: 1500, seed: 103, folds: 5)
        c.valance(top: 250, bandHeight: 60, swagDepth: 150, swags: 4, colors: look.valance, fringe: true)
        goldenPortal(c)
        finish(c, vignette: 0.5)
    }

    static func goldenPortal(_ c: Canvas) {
        let pw: CGFloat = 96
        // dark coffered ceiling above the arch
        let ceiling = buildPath { p in
            p.move(to: P(-20, -20)); p.addLine(to: P(W + 20, -20)); p.addLine(to: P(W + 20, 440))
            p.addCurve(to: P(W / 2, 150), control1: P(W + 20, 230), control2: P(W / 2 + 420, 150))
            p.addCurve(to: P(-20, 440), control1: P(W / 2 - 420, 150), control2: P(-20, 230))
            p.closeSubpath()
        }
        c.linear(ceiling, [(0, hex(0x12060E)), (1, hex(0x2A1024))], P(0, 0), P(0, 440))
        c.clip(ceiling) {
            for k in 0..<7 {
                let r = rrectPath(CGRect(x: CGFloat(k) * 200 - 60, y: 10, width: 170, height: 110), 14)
                c.fill(r, hex(0x08030A, 0.6))
                c.stroke(r, hex(0xAF783B, 0.25), 3)
            }
        }
        let arch = buildPath { p in
            p.move(to: P(-20, 440))
            p.addCurve(to: P(W / 2, 150), control1: P(-20, 230), control2: P(W / 2 - 420, 150))
            p.addCurve(to: P(W + 20, 440), control1: P(W / 2 + 420, 150), control2: P(W + 20, 230))
            p.addLine(to: P(W + 20, 560))
            p.addLine(to: P(W - pw, 560))
            p.addCurve(to: P(W / 2, 300), control1: P(W - pw, 360), control2: P(W / 2 + 330, 300))
            p.addCurve(to: P(pw, 560), control1: P(W / 2 - 330, 300), control2: P(pw, 360))
            p.addLine(to: P(-20, 560)); p.closeSubpath()
        }
        let pilL = rectPath(CGRect(x: -20, y: 540, width: pw + 20, height: H - 520))
        let pilR = rectPath(CGRect(x: W - pw, y: 540, width: pw + 20, height: H - 520))
        let portal = combine([arch, pilL, pilR])
        c.shadowOnly(portal, dx: 0, dy: 24, blur: 40, color: hex(0x05010A, 0.9))
        c.stroke(portal, Metal.gold.edge, 10)
        c.metalFill(portal, .gold, bbox: CGRect(x: 0, y: 0, width: W, height: 700))
        c.clip(portal) {
            // shade pilasters with their own horizontal gradient + fluting
            for r in [CGRect(x: -20, y: 540, width: pw + 20, height: H), CGRect(x: W - pw, y: 540, width: pw + 20, height: H)] {
                c.linear(rectPath(r), [(0, hex(0xFFE9A8)), (0.35, hex(0xE0A650)), (0.7, hex(0x9A6428)), (1, hex(0x5A3410))], P(r.minX, 0), P(r.maxX, 0))
                for k in 1...3 {
                    let fx = r.minX + r.width * CGFloat(k) / 4
                    c.stroke(polygonPath([P(fx, 600), P(fx, H)], closed: false), hex(0x5A3410, 0.55), 6)
                    c.stroke(polygonPath([P(fx - 4, 600), P(fx - 4, H)], closed: false), hex(0xFFF2C8, 0.45), 2)
                }
            }
            // ornamental channel along the arch
            let band = buildPath { p in
                p.move(to: P(pw - 45, 560))
                p.addCurve(to: P(W / 2, 228), control1: P(pw - 45, 300), control2: P(W / 2 - 380, 228))
                p.addCurve(to: P(W - pw + 45, 560), control1: P(W / 2 + 380, 228), control2: P(W - pw + 45, 300))
            }
            c.stroke(band, hex(0x5A3410, 0.6), 18)
            c.stroke(band.transformed(CGAffineTransform(translationX: -2, y: -3)), hex(0xFFF3C8, 0.5), 3)
            let L = c.lightDir()
            c.innerShadow(portal, dx: L.dx * 14, dy: L.dy * 14, blur: 14, color: hex(0x3A1E06, 0.75))
            c.innerShadow(portal, dx: -L.dx * 8, dy: -L.dy * 8, blur: 8, color: hex(0xFFF8DC, 0.7))
        }
        // rosettes along the arch
        let inner = buildPath { p in
            p.move(to: P(pw, 560))
            p.addCurve(to: P(W / 2, 300), control1: P(pw, 360), control2: P(W / 2 - 330, 300))
            p.addCurve(to: P(W - pw, 560), control1: P(W / 2 + 330, 300), control2: P(W - pw, 360))
        }
        let pts = flatten(inner, step: 4).first!
        let bulbs = 17
        for k in 0..<bulbs {
            let p = pts[Int(CGFloat(k) / CGFloat(bulbs - 1) * CGFloat(pts.count - 1))]
            c.bulb(p + P(0, -26), r: 11)
        }
        for y in stride(from: CGFloat(700), to: H - 900, by: 170) {
            c.bulb(P(pw / 2 - 10, y), r: 11)
            c.bulb(P(W - pw / 2 + 10, y), r: 11)
        }
        // keystone cartouche
        let ks = buildPath { p in
            p.move(to: P(W / 2 - 80, 120)); p.addLine(to: P(W / 2 + 80, 120)); p.addLine(to: P(W / 2 + 56, 300))
            p.addQuadCurve(to: P(W / 2 - 56, 300), control: P(W / 2, 340)); p.closeSubpath()
        }
        c.shadowOnly(ks, dx: 8, dy: 14, blur: 18, color: hex(0x3A1E06, 0.8))
        c.stroke(ks, Metal.gold.edge, 6)
        c.metalPlate(ks, .gold, bevel: 10)
        let gem = polygonPath([P(W / 2, 185), P(W / 2 + 34, 228), P(W / 2, 272), P(W / 2 - 34, 228)])
        c.stroke(gem, hex(0x2A020C), 5)
        c.linear(gem, [(0, hex(0xFF7A8C)), (0.5, hex(0xC8102F)), (1, hex(0x4A0414))], P(W / 2 - 30, 190), P(W / 2 + 30, 270))
        c.glint(P(W / 2 - 10, 208), size: 12)
        // scroll volutes at the arch shoulders
        for s in [CGFloat(-1), 1] {
            let cx = W / 2 + s * 470, cy: CGFloat = 262
            let vol = buildPath { p in
                p.addArc(center: P(cx, cy), radius: 46, startAngle: 0, endAngle: .pi * 1.6, clockwise: s < 0)
            }
            c.stroke(vol, hex(0x5A3410, 0.7), 14)
            c.stroke(vol, hex(0xFFE6A0, 0.6), 4)
            c.glossy(circlePath(P(cx, cy), 12), light: hex(0xFFF6CC), base: hex(0xD8A04A), dark: hex(0x6A3E10), spec: 1)
        }
    }
}
