// Backgrounds.swift — VC01–VC03 onboarding scenes and VC27–VC35 world backgrounds (1290×2796, opaque).
// Composition rule: quiet dark-plum centre (≈70 % of width), UI-calm lower 35 %, light & detail only
// along the edges and the top. Every world shares the palette and velvet material but changes props/light.
import Foundation
import CoreGraphics

struct WorldLook {
    var wallTop: RGBA = hex(0x2A1531)
    var wallMid: RGBA = hex(0x27142E)
    var wallBottom: RGBA = hex(0x170B1E)
    var centerGlow: RGBA = hex(0x4A2340)
    var drape: DrapeColors = .ruby
    var valance: DrapeColors = .burgundy
    var key: RGBA = hex(0xFFD26E)       // spotlight colour
    var accent: RGBA? = nil             // secondary edge light (e.g. cold blue)
}

enum Backgrounds {
    static let W: CGFloat = 1290, H: CGFloat = 2796

    // MARK: shared base
    static func base(_ c: Canvas, _ look: WorldLook) {
        c.linear(rectPath(c.bounds), [(0, look.wallTop), (0.35, look.wallMid), (0.7, look.wallMid.mix(look.wallBottom, 0.5)), (1, look.wallBottom)], P(0, 0), P(0, H))
        // warm pool of stage light behind the play area (very soft)
        c.radialEllipse(nil, [(0, look.centerGlow.alpha(0.55)), (0.6, look.centerGlow.alpha(0.18)), (1, look.centerGlow.alpha(0))], center: P(W / 2, H * 0.40), rx: W * 0.62, ry: H * 0.30)
        // faint backdrop panels (vertical velvet flats)
        c.save {
            for i in 0..<9 {
                let x = W * (CGFloat(i) + 0.5) / 9
                c.stroke(polygonPath([P(x, 0), P(x, H * 0.66)], closed: false), hex(0x0E0612, 0.18), 6)
                c.stroke(polygonPath([P(x + 5, 0), P(x + 5, H * 0.66)], closed: false), hex(0x5A3060, 0.06), 2)
            }
        }
    }

    static func finish(_ c: Canvas, vignette: CGFloat = 0.62) {
        c.vignette(strength: vignette)
        // calm the lower third further for UI text
        c.linear(nil, [(0, Pal.deepVelvet.alpha(0)), (1, Pal.deepVelvet.alpha(0.55))], P(0, H * 0.62), P(0, H))
        c.filmGrain(alpha: 0.05)
    }

    static func sideDrapes(_ c: Canvas, colors: DrapeColors, width w: CGFloat = 230, top: CGFloat = 150, pinchY: CGFloat? = 1560, seed: UInt64 = 11, folds: Int = 6, sway: CGFloat = 0) {
        c.drape(Drape(rect: CGRect(x: -30, y: top, width: w + 30, height: H - top + 40), colors: colors, folds: folds, outerLeft: true, pinchY: pinchY, pinch: 0.42, sway: sway, seed: seed))
        c.drape(Drape(rect: CGRect(x: W - w, y: top, width: w + 30, height: H - top + 40), colors: colors, folds: folds, outerLeft: false, pinchY: pinchY, pinch: 0.42, sway: -sway, seed: seed + 7))
    }

    // MARK: worlds
    static func world(_ n: Int, _ c: Canvas) {
        switch n {
        case 1: rubyRehearsal(c)
        case 2: keyholeWings(c)
        case 3: propWorkshop(c)
        case 4: frostedGallery(c)
        case 5: chainLoft(c)
        case 6: clockworkCurtains(c)
        case 7: splitStage(c)
        case 8: moonlitRotation(c)
        default: grandCascade(c)
        }
    }

    /// 01 Ruby Rehearsal — intimate red-plum stage, brass ring only at the edges, warm spotlights.
    static func rubyRehearsal(_ c: Canvas) {
        let look = WorldLook(centerGlow: hex(0x5A2238), drape: .ruby, valance: .burgundy)
        let skip = ProcessInfo.processInfo.environment["AF_SKIP"] ?? ""
        base(c, look)
        if !skip.contains("floor") { c.stageFloor(top: H * 0.74, vanish: P(W / 2, H * 0.30), color: hex(0x1E0D1A), lineColor: hex(0x3A1E2E, 0.35)) }
        if !skip.contains("cones") {
            c.lightCone(apex: P(120, -40), toward: P(560, 1500), spread: deg(24), color: look.key, alpha: 0.22, seed: 3)
            c.lightCone(apex: P(W - 120, -40), toward: P(W - 560, 1500), spread: deg(24), color: look.key, alpha: 0.22, seed: 4)
        }
        if !skip.contains("drapes") { sideDrapes(c, colors: look.drape, seed: 21) }
        if !skip.contains("ring") { c.brassRingFragments(center: P(W / 2, H * 0.43), radius: 590, width: 46, calmHalfWidth: 330, fadeWidth: 150) }
        if !skip.contains("valance") { c.valance(bandHeight: 120, swagDepth: 190, swags: 4, colors: look.valance) }
        footlights(c, color: hex(0xFFC870))
        finish(c)
    }

    static func footlights(_ c: Canvas, color: RGBA, y: CGFloat = H - 40) {
        // only at the outer edges: warm footlight shells on the stage lip, glow washing up the drapes
        for x in [CGFloat(95), W - 95] {
            c.layer(blend: .screen) { c.blob(P(x, y - 40), rx: 220, ry: 260, color: color.alpha(0.22)) }
            let shell = buildPath { p in
                p.move(to: P(x - 70, y + 40))
                p.addCurve(to: P(x + 70, y + 40), control1: P(x - 70, y - 60), control2: P(x + 70, y - 60))
                p.closeSubpath()
            }
            c.stroke(shell, hex(0x160808), 8)
            c.metalPlate(shell, .brass, bevel: 8)
            let glass = ellipsePath(P(x, y - 8), 40, 18)
            c.fill(glass, color.lighter(0.5))
            c.layer(blend: .screen) { c.blob(P(x, y - 14), rx: 70, ry: 40, color: color.alpha(0.9)) }
        }
    }

    // Stubs filled in below (other worlds and onboarding scenes).
}
