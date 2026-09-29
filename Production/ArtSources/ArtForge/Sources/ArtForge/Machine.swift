// Machine.swift — VC23 Daily Encore cabinet (1536×1536, alpha).
// Front, symmetric red-plum cabinet with a brass frame and Vell's hat on top. Exactly three EMPTY cream
// windows of equal width, drawn at the catalog geometry (normalized): x 0.17–0.36 / 0.405–0.595 / 0.64–0.83,
// y 0.36–0.72. No symbols, text, buttons or lever. Window rects are re-measured from pixels by art_qa.py.
import Foundation
import CoreGraphics

enum Machine {
    static let S: CGFloat = 1536
    static let windowsNorm: [(CGFloat, CGFloat)] = [(0.17, 0.36), (0.405, 0.595), (0.64, 0.83)]
    static let yNorm: (CGFloat, CGFloat) = (0.36, 0.72)

    static func windowRects() -> [CGRect] {
        windowsNorm.map { (x0, x1) in
            CGRect(x: (x0 * S).rounded(), y: (yNorm.0 * S).rounded(), width: ((x1 - x0) * S).rounded(), height: ((yNorm.1 - yNorm.0) * S).rounded())
        }
    }

    static func draw(_ c: Canvas) {
        let wins = windowRects()
        let L = c.lightDir()
        // ground shadow
        c.blob(P(768, 1418), rx: 640, ry: 46, color: hex(0x0A020A, 0.55))
        // base plinth with feet
        let plinth = rrectPath(CGRect(x: 160, y: 1296, width: 1216, height: 96), 22)
        for fx in [CGFloat(200), 1336] {
            let foot = rrectPath(CGRect(x: fx - 60, y: 1360, width: 120, height: 56), 16)
            c.stroke(foot, Metal.brass.edge, 8); c.metalPlate(foot, .brass, bevel: 8)
        }
        c.stroke(plinth, Metal.brass.edge, 10)
        c.metalPlate(plinth, .brass, bevel: 12)
        c.stroke(polygonPath([P(190, 1330), P(1346, 1330)], closed: false), hex(0x3A220A, 0.6), 4)
        // cabinet body with arched top
        let body = buildPath { p in
            p.move(to: P(180, 1306)); p.addLine(to: P(180, 560))
            p.addCurve(to: P(768, 318), control1: P(180, 392), control2: P(470, 318))
            p.addCurve(to: P(1356, 560), control1: P(1066, 318), control2: P(1356, 392))
            p.addLine(to: P(1356, 1306)); p.closeSubpath()
        }
        c.shadowOnly(body, dx: 18, dy: 26, blur: 40, color: hex(0x05010A, 0.7))
        c.stroke(body, hex(0x12040C), 12)
        // crimson lacquer with plum lower half
        c.linear(body, [(0, hex(0xC8304A)), (0.30, hex(0x9A1C38)), (0.62, hex(0x5E1236)), (1, hex(0x2E0A26))], P(0, 318), P(0, 1306))
        c.clip(body) {
            c.linear(body, [(0, RGBA.white.alpha(0.16)), (0.25, RGBA.clear), (0.8, RGBA.clear), (1, RGBA.black.alpha(0.35))], P(180, 0), P(1356, 0))
            c.innerShadow(body, dx: -L.dx * 18, dy: -L.dy * 18, blur: 14, color: hex(0xFF9AAE, 0.45))
            c.innerShadow(body, dx: L.dx * 26, dy: L.dy * 26, blur: 26, color: hex(0x12020A, 0.7))
            c.fabricGrain(body, alpha: 0.06, fibre: 0)
            // glossy lacquer reflection on the arch
            c.blob(P(520, 440), rx: 240, ry: 60, color: RGBA.white.alpha(0.18), angle: deg(-14))
        }
        c.metalRim(body, width: 18, metal: .gold)
        // side columns: crimson lacquer with gold bands, capitals and bases
        for x in [CGFloat(216), 1320] {
            let col = rrectPath(CGRect(x: x - 26, y: 590, width: 52, height: 690), 18)
            c.shadowOnly(col, dx: 8, dy: 10, blur: 12, color: hex(0x05010A, 0.6))
            c.stroke(col, hex(0x12040C), 7)
            c.linear(col, [(0, hex(0xF0607A)), (0.3, hex(0xC8243F)), (0.7, hex(0x7A0E2A)), (1, hex(0x3A0616))], P(x - 26, 0), P(x + 26, 0))
            c.clip(col) {
                c.stroke(polygonPath([P(x - 10, 600), P(x - 10, 1270)], closed: false), hex(0xFFB0C0, 0.45), 4)
                for y in stride(from: CGFloat(700), through: 1180, by: 160) {
                    let band = rectPath(CGRect(x: x - 30, y: y, width: 60, height: 16))
                    c.stroke(band, Metal.gold.edge, 4)
                    c.linear(band, [(0, hex(0xFFE9A8)), (0.4, hex(0xE0A650)), (1, hex(0x6A4012))], P(x - 26, 0), P(x + 26, 0))
                }
            }
            c.metalRim(col, width: 5, metal: .gold)
            for y in [CGFloat(578), 1268] {
                let cap = rrectPath(CGRect(x: x - 40, y: y, width: 80, height: 28), 8)
                c.stroke(cap, Metal.gold.edge, 6); c.metalPlate(cap, .gold, bevel: 6)
            }
        }
        // gold filigree scrolls on the arch face
        c.clip(body) {
            for s2 in [CGFloat(-1), 1] {
                for r in [CGFloat(330), 420] {
                    let scroll = buildPath { p in
                        p.move(to: P(768 + s2 * 120, 462))
                        p.addCurve(to: P(768 + s2 * r, 470), control1: P(768 + s2 * (r * 0.45), 420), control2: P(768 + s2 * (r * 0.8), 500))
                    }
                    c.stroke(scroll, hex(0x3A0A14, 0.6), 7)
                    c.stroke(scroll, hex(0xF2C66A, 0.85), 3)
                }
            }
        }
        // inner stage panel (dark plum) holding the windows
        let panel = rrectPath(CGRect(x: 236, y: 486, width: 1064, height: 686), 36)
        c.stroke(panel, hex(0x12040C), 10)
        c.velvet(panel, base: hex(0x3A1646), sheen: hex(0x6E3A84), deep: hex(0x14061A), sheenWidth: 44, texture: 0.12)
        c.innerShadow(panel, dx: L.dx * 20, dy: L.dy * 20, blur: 22, color: hex(0x000000, 0.7))
        c.metalRim(panel, width: 12, metal: .brass)
        // small velvet swag across the top of the panel (above the windows)
        let swag = buildPath { p in
            p.move(to: P(250, 496)); p.addLine(to: P(1286, 496)); p.addLine(to: P(1286, 516))
            for k in 0..<6 {
                let xa = 1286 - CGFloat(k) * 1036 / 6, xb = 1286 - CGFloat(k + 1) * 1036 / 6
                p.addQuadCurve(to: P(xb, 516), control: P((xa + xb) / 2, 548))
            }
            p.closeSubpath()
        }
        c.clip(panel) {
            c.shadowOnly(swag, dx: 0, dy: 6, blur: 8, color: hex(0x05010A, 0.7))
            c.linear(swag, [(0, hex(0x6A0A20)), (0.6, hex(0xB52643)), (1, hex(0x7A0E26))], P(0, 496), P(0, 540))
        }
        // window bezels (outside the window rects) and plum pillars between them
        for r in wins {
            let bez = rrectPath(r.insetBy(dx: -24, dy: -24), 30)
            c.shadowOnly(bez, dx: 8, dy: 12, blur: 14, color: hex(0x05010A, 0.7))
            c.stroke(bez, Metal.gold.edge, 8)
            c.metalPlate(bez, .gold, bevel: 10)
            c.stroke(rrectPath(r.insetBy(dx: -12, dy: -12), 22), hex(0x5A3410, 0.55), 3)
            for (x, y) in [(r.minX - 12, r.minY - 12), (r.maxX + 12, r.minY - 12), (r.minX - 12, r.maxY + 12), (r.maxX + 12, r.maxY + 12)] {
                c.glossy(circlePath(P(x, y), 6), light: hex(0xFFF6D0), base: hex(0xC89038), dark: hex(0x5A3412), spec: 1)
            }
        }
        // empty cream windows (reel drums): subtle cylindrical shading only, no symbols
        for r in wins {
            let w = rrectPath(r, 14)
            c.fill(w, hex(0xFFF3DC))
            c.linear(w, [(0, hex(0xEADBBF)), (0.16, hex(0xFBEFD8)), (0.5, hex(0xFFF7E8)), (0.84, hex(0xFBEFD8)), (1, hex(0xEADBBF))], P(0, r.minY), P(0, r.maxY))
            c.clip(w) {
                c.innerShadow(w, dx: 0, dy: 6, blur: 10, color: hex(0xB89A78, 0.45))
                // faint glass reflection
                let refl = polygonPath([P(r.minX, r.minY + 40), P(r.minX + r.width * 0.55, r.minY), P(r.minX + r.width * 0.75, r.minY), P(r.minX, r.minY + r.height * 0.42)])
                c.fill(refl, RGBA.white.alpha(0.22))
            }
        }
        // lower front panel with a quiet gold ornament (no text, no buttons)
        let lower = rrectPath(CGRect(x: 300, y: 1186, width: 936, height: 90), 26)
        c.stroke(lower, hex(0x12040C), 8)
        c.velvet(lower, base: hex(0x4A1A50), sheen: hex(0x8A4A9A), deep: hex(0x1A0820), sheenWidth: 22, texture: 0.12)
        c.metalRim(lower, width: 8, metal: .gold)
        for s in [CGFloat(-1), 1] {
            let scroll = buildPath { p in
                p.move(to: P(768 + s * 60, 1231))
                p.addCurve(to: P(768 + s * 360, 1231), control1: P(768 + s * 160, 1196), control2: P(768 + s * 260, 1266))
            }
            c.stroke(scroll, hex(0x2A1606, 0.8), 9)
            c.metalRim(scroll, width: 5, metal: .gold)
            c.glossy(circlePath(P(768 + s * 372, 1231), 9), light: hex(0xFFF6D0), base: hex(0xC89038), dark: hex(0x5A3412), spec: 1)
        }
        let dia = polygonPath([P(768, 1200), P(800, 1231), P(768, 1262), P(736, 1231)])
        c.stroke(dia, hex(0x06122E), 6)
        c.linear(dia, [(0, hex(0x7CC8FF)), (0.5, hex(0x1C6FD8)), (1, hex(0x0A2A66))], P(740, 1204), P(796, 1258))
        c.metalRim(dia, width: 4, metal: .gold)
        // marquee bulbs along the arch
        let arch = buildPath { p in
            p.move(to: P(214, 560))
            p.addCurve(to: P(768, 352), control1: P(214, 410), control2: P(490, 352))
            p.addCurve(to: P(1322, 560), control1: P(1046, 352), control2: P(1322, 410))
        }
        let pts = flatten(arch, step: 3).first!
        for k in 0..<13 where k != 6 {
            c.bulb(pts[Int(CGFloat(k) / 12 * CGFloat(pts.count - 1))], r: 13)
        }
        // crest pedestal and Vell's hat on top
        let ped = buildPath { p in
            p.move(to: P(650, 380)); p.addQuadCurve(to: P(886, 380), control: P(768, 300))
            p.addLine(to: P(900, 408)); p.addLine(to: P(636, 408)); p.closeSubpath()
        }
        c.stroke(ped, Metal.gold.edge, 8)
        c.metalPlate(ped, .gold, bevel: 10)
        Items.vellHat(c, at: P(768, 468), size: 232)
        MetaStore.shared.set("VC23", "designReelRects", wins.map { normRect($0, S, S) })
    }
}
