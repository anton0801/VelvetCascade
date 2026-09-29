// HUD.swift — UI07 StageChargeGauge, UI08 GravityCompass, UI09 MovesBadge, UI10 ObjectiveBadge,
// UI11 LevelNode, UI12 ResultStars, UI18 SparkEmitter, билет, иконки целей.

import SwiftUI
import VelvetDomain

/// UI07: 12 сегментов в латунном пазу 14 pt, зазор 2; пустой #4A344A, полный #FFD26E; рядом цифра N/12.
struct StageChargeGauge: View {
    let charge: Int
    var showNumber = true

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(i < charge ? Palette.spotlightGold : Palette.gaugeEmpty)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(i < charge ? 0.35 : 0))
                                .frame(height: 2).frame(maxHeight: .infinity, alignment: .top).padding(.horizontal, 1)
                        )
                }
            }
            .frame(height: 14)
            .padding(3)
            .background(
                Capsule().fill(LinearGradient(colors: [Palette.goldBottom, Palette.antiqueGold.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(Capsule().stroke(Palette.goldTop.opacity(0.5), lineWidth: 0.6))
            if showNumber {
                Text("\(charge)/12")
                    .vcFont(.hudSmall)
                    .foregroundColor(charge >= 12 ? Palette.spotlightGold : Palette.warmIvory)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stage Charge")
        .accessibilityValue("\(charge) of 12\(charge >= 12 ? ", ready to turn" : "")")
    }
}

/// UI08: 40×40 со схемой исходных осей поля и стрелкой локального направления; подпись Down/Right/Up/Left.
/// Отдельная маленькая экранная стрелка всегда вниз. Preview — следующее направление пунктиром.
struct GravityCompass: View {
    let q: Int
    var previewQ: Int?
    var showLabel = true

    private func arrow(for q: Int, in size: CGSize) -> Path {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let d = Direction.gravity(forOrientation: q).vector
        let len = size.width * 0.34
        let tip = CGPoint(x: c.x + CGFloat(d.dx) * len, y: c.y + CGFloat(d.dy) * len)
        let tail = CGPoint(x: c.x - CGFloat(d.dx) * len * 0.55, y: c.y - CGFloat(d.dy) * len * 0.55)
        var p = Path()
        p.move(to: tail)
        p.addLine(to: tip)
        let back = CGPoint(x: -CGFloat(d.dx), y: -CGFloat(d.dy))
        let perp = CGPoint(x: -back.y, y: back.x)
        let h = size.width * 0.14
        p.move(to: CGPoint(x: tip.x + back.x * h + perp.x * h * 0.8, y: tip.y + back.y * h + perp.y * h * 0.8))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x + back.x * h - perp.x * h * 0.8, y: tip.y + back.y * h - perp.y * h * 0.8))
        return p
    }

    var body: some View {
        HStack(spacing: 6) {
            Canvas { ctx, size in
                let r = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
                ctx.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(Palette.panel))
                ctx.stroke(Path(roundedRect: r, cornerRadius: 8), with: .color(Palette.antiqueGold), lineWidth: 0.8)
                // Исходные оси поля: верхняя кромка отмечена золотой чертой.
                var axes = Path()
                axes.move(to: CGPoint(x: size.width * 0.2, y: size.height * 0.16))
                axes.addLine(to: CGPoint(x: size.width * 0.8, y: size.height * 0.16))
                ctx.stroke(axes, with: .color(Palette.antiqueGold.opacity(0.9)), lineWidth: 1.5)
                if let pq = previewQ {
                    ctx.stroke(arrow(for: pq, in: size), with: .color(Palette.mutedRose),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 3]))
                }
                ctx.stroke(arrow(for: q, in: size), with: .color(Palette.spotlightGold),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 40, height: 40)
            if showLabel {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Direction.gravity(forOrientation: q).label)
                        .vcFont(.caption).foregroundColor(Palette.warmIvory)
                    HStack(spacing: 2) {
                        Text("↓").font(.system(size: 11, weight: .bold)).foregroundColor(Palette.mutedRose)
                        Text("floor").vcFont(.caption).foregroundColor(Palette.mutedRose)
                    }
                }
                .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gravity")
        .accessibilityValue("Pieces fall toward the stage's original \(Direction.gravity(forOrientation: q).label.lowercased()) side. On screen they always fall down.")
    }
}

/// UI09: ширина 76, min-height 60, арка сверху radius 14; «Moves» 13, число 24 monospaced; ≤3 → Error + «Few moves».
struct MovesBadge: View {
    let moves: Int

    var body: some View {
        let few = moves <= 3
        VStack(spacing: 0) {
            Text("Moves").vcFont(.caption).foregroundColor(Palette.mutedRose)
            Text("\(moves)").vcFont(.hud).foregroundColor(few ? Palette.error : Palette.warmIvory).monospacedDigit()
            if few { Text("Few moves").vcFont(.caption).foregroundColor(Palette.error).fixedSize() }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 76, minHeight: 60)
        .background(UnevenArch().fill(Palette.panel))
        .overlay(UnevenArch().stroke(Palette.antiqueGold, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Moves")
        .accessibilityValue("\(moves)\(few ? ", few moves left" : "")")
    }
}

/// Прямоугольник с аркой сверху (radius 14).
struct UnevenArch: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let rad: CGFloat = 14
        p.move(to: CGPoint(x: r.minX, y: r.maxY - 6))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + rad), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 6))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 6, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 6, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - 6), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Иконка цели: token/ключ/пластина.
struct ObjectiveIcon: View {
    let objective: ObjectiveDef
    var size: CGFloat = 28

    var body: some View {
        switch objective {
        case .collect(let color, _): ArtImage(name: GemArt.name(color), maxPoints: size).frame(width: size, height: size)
        case .plates: ArtImage(name: "vc_velvet_plate", maxPoints: size).frame(width: size, height: size)
        case .keys: ArtImage(name: "vc_stage_key", maxPoints: size).frame(width: size, height: size)
        }
    }
}

extension ObjectiveDef {
    var label: String {
        switch self {
        case .collect(let c, _): return c.name + "s"
        case .plates: return "Plates"
        case .keys: return "Keys"
        }
    }

    func spokenGoal(_ remaining: Int) -> String {
        switch self {
        case .collect(let c, _): return "\(remaining) \(c.name) gems left"
        case .plates: return "\(remaining) Velvet Plates left"
        case .keys: return "\(remaining) keys left"
        }
    }
}

/// UI10: token 28, remaining 17 semibold, подпись 13; при 0 — векторная галочка и «Done».
struct ObjectiveBadge: View {
    let objective: ObjectiveDef
    let remaining: Int
    /// Компактный HUD при крупном тексте: без подписи (объявляется VoiceOver).
    var compact = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                ObjectiveIcon(objective: objective, size: 28)
                if remaining == 0 { CheckMark().frame(width: 14, height: 14).offset(x: 4, y: 3) }
            }
            if remaining == 0 {
                Text("Done").vcFont(.caption).foregroundColor(Palette.success)
            } else {
                Text("\(remaining)").vcFont(.headline).foregroundColor(Palette.warmIvory).monospacedDigit()
            }
            if !compact {
                Text(objective.label).vcFont(.caption).foregroundColor(Palette.mutedRose).lineLimit(1).minimumScaleFactor(0.9)
            }
        }
        .frame(minWidth: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(objective.label)
        .accessibilityValue(remaining == 0 ? "Done" : objective.spokenGoal(remaining))
    }
}

struct CheckMark: View {
    var color: Color = Palette.success
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(Palette.deepVelvet))
            var p = Path()
            p.move(to: CGPoint(x: size.width * 0.25, y: size.height * 0.52))
            p.addLine(to: CGPoint(x: size.width * 0.43, y: size.height * 0.7))
            p.addLine(to: CGPoint(x: size.width * 0.76, y: size.height * 0.32))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Пятиконечная звезда.
struct StarShape: Shape {
    var inner: CGFloat = 0.45
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY + r.height * 0.04)
        let R = min(r.width, r.height) / 2
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double(i) * .pi / 5
            let rad = i % 2 == 0 ? R : R * inner
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rad, y: c.y + CGFloat(sin(a)) * rad)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Одна звезда с золотым bevel из двух вложенных paths либо пустой контур #8A647C.
struct BevelStar: View {
    let filled: Bool
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            if filled {
                StarShape().fill(LinearGradient(colors: [Palette.goldTop, Palette.spotlightGold, Palette.goldBottom], startPoint: .top, endPoint: .bottom))
                StarShape().inset(by: size * 0.16).fill(LinearGradient(colors: [Palette.goldTop.opacity(0.9), Palette.spotlightGold.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                StarShape().stroke(Palette.antiqueGold, lineWidth: 1)
            } else {
                StarShape().fill(Palette.ink.opacity(0.9))
                StarShape().stroke(Palette.starEmpty, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
    }
}

extension Shape where Self == StarShape {
    func inset(by amount: CGFloat) -> some Shape { InsetStar(amount: amount) }
}

struct InsetStar: Shape {
    let amount: CGFloat
    func path(in r: CGRect) -> Path { StarShape().path(in: r.insetBy(dx: amount, dy: amount)) }
}

/// UI12: три звезды 42 pt с gap 8, последовательное появление 120 ms, только реальный результат.
struct ResultStars: View {
    let stars: Int
    var animate: Bool = true
    @State private var shown = 0

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                BevelStar(filled: i < shown, size: i == 1 ? 50 : 42)
                    .scaleEffect(i < shown ? 1 : 0.9)
                    .offset(y: i == 1 ? -6 : 0)
            }
        }
        .onAppear {
            guard animate else { shown = stars; return }
            for i in 0..<stars {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(i) * 0.12) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { shown = i + 1 }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stars) of 3 stars")
    }
}

/// Мини-звёзды под узлом карты.
struct MiniStars: View {
    let stars: Int
    var size: CGFloat = 11
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { i in
                StarShape().fill(i < stars ? Palette.spotlightGold : Palette.starEmpty.opacity(0.6)).frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// UI11: диск 48; locked — тёмная бронза с замком; current — gold ring + ivory number; completed — обод + 1–3 звезды.
struct LevelNode: View {
    enum State { case locked, current, available, completed(Int) }
    let number: Int
    let state: State
    var selected = false

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle().stroke(ring, lineWidth: ringWidth)
            switch state {
            case .locked:
                LockGlyph().frame(width: 16, height: 18)
            default:
                Text("\(number)").vcFont(.headline).foregroundColor(Palette.warmIvory).monospacedDigit()
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: 48, height: 48)
        .overlay(alignment: .bottom) {
            if case .completed(let s) = state { MiniStars(stars: s).offset(y: 12) }
        }
        .scaleEffect(selected ? 1.06 : 1)
        .shadow(color: isCurrent ? Palette.spotlightGold.opacity(0.45) : .clear, radius: 8)
    }

    private var isCurrent: Bool { if case .current = state { return true }; return false }

    private var fill: AnyShapeStyle {
        switch state {
        case .locked: return AnyShapeStyle(Color(hex: 0x3A2A2A))
        case .current: return AnyShapeStyle(LinearGradient(colors: [Palette.rubyCurtain, Palette.velvetTop], startPoint: .top, endPoint: .bottom))
        case .available, .completed: return AnyShapeStyle(LinearGradient(colors: [Palette.panelTop, Palette.panel], startPoint: .top, endPoint: .bottom))
        }
    }

    private var ring: Color {
        switch state {
        case .locked: return Color(hex: 0x6B5040)
        case .current: return Palette.spotlightGold
        case .available: return Palette.antiqueGold
        case .completed: return Palette.antiqueGold
        }
    }

    private var ringWidth: CGFloat { isCurrent ? 3 : 2 }
}

struct LockGlyph: View {
    var body: some View {
        Canvas { ctx, s in
            let body = CGRect(x: s.width * 0.1, y: s.height * 0.45, width: s.width * 0.8, height: s.height * 0.5)
            ctx.fill(Path(roundedRect: body, cornerRadius: 2), with: .color(Color(hex: 0x9C7A5C)))
            var shackle = Path()
            shackle.addArc(center: CGPoint(x: s.width / 2, y: s.height * 0.45), radius: s.width * 0.28,
                           startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            ctx.stroke(shackle, with: .color(Color(hex: 0x9C7A5C)), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}

/// Баланс Hint Tickets с VC38.
struct TicketBalance: View {
    let count: Int
    var iconSize: CGFloat = 24

    var body: some View {
        HStack(spacing: 6) {
            ArtImage(name: "vc_hint_ticket", maxPoints: iconSize).frame(width: iconSize, height: iconSize)
            Text("\(count)").vcFont(.headline).foregroundColor(Palette.warmIvory).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .background(Capsule().fill(Palette.panel))
        .overlay(Capsule().stroke(Palette.antiqueGold.opacity(0.7), lineWidth: 0.8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hint Tickets")
        .accessibilityValue("\(count)")
    }
}

/// UI18: четырёхлучевая звезда с мягким halo; life 0.25–0.6 s; 2–6 pt; максимум 12 (Sweep) / 20 (result).
struct SparkEmitter: View {
    let count: Int
    var area: CGSize = CGSize(width: 240, height: 160)
    var seed: Int = 1
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                var rng = LevelRNG(seed: UInt64(seed))
                for _ in 0..<min(count, 20) {
                    let life = 0.25 + Double(rng.nextInt(below: 350)) / 1000
                    let delay = Double(rng.nextInt(below: 400)) / 1000
                    let x = Double(rng.nextInt(below: 1000)) / 1000 * size.width
                    let y0 = Double(rng.nextInt(below: 1000)) / 1000 * size.height
                    let sz = 2 + Double(rng.nextInt(below: 400)) / 100
                    let local = (t - delay).truncatingRemainder(dividingBy: life + 0.9)
                    guard local >= 0, local <= life else { continue }
                    let k = local / life
                    let y = y0 - k * 18
                    let alpha = sin(k * .pi)
                    let c = CGPoint(x: x, y: y)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - sz * 1.6, y: c.y - sz * 1.6, width: sz * 3.2, height: sz * 3.2)),
                             with: .color(Palette.spotlightGold.opacity(0.18 * alpha)))
                    var star = Path()
                    star.move(to: CGPoint(x: c.x, y: c.y - sz))
                    star.addLine(to: CGPoint(x: c.x + sz * 0.25, y: c.y - sz * 0.25))
                    star.addLine(to: CGPoint(x: c.x + sz, y: c.y))
                    star.addLine(to: CGPoint(x: c.x + sz * 0.25, y: c.y + sz * 0.25))
                    star.addLine(to: CGPoint(x: c.x, y: c.y + sz))
                    star.addLine(to: CGPoint(x: c.x - sz * 0.25, y: c.y + sz * 0.25))
                    star.addLine(to: CGPoint(x: c.x - sz, y: c.y))
                    star.addLine(to: CGPoint(x: c.x - sz * 0.25, y: c.y - sz * 0.25))
                    star.closeSubpath()
                    ctx.fill(star, with: .color(Palette.goldTop.opacity(alpha)))
                }
            }
        }
        .frame(width: area.width, height: area.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Конфетти результата: максимум 20 частиц, конечная анимация.
struct ConfettiBurst: View {
    var count = 20
    @State private var fire = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<min(count, 20), id: \.self) { i in
                    let angle = Double(i) / Double(count) * .pi * 2
                    let dist = 90.0 + Double((i * 37) % 60)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill([Palette.spotlightGold, Palette.brightCrimson, Palette.warmIvory, Palette.amethyst][i % 4])
                        .frame(width: 6, height: 10)
                        .rotationEffect(.degrees(fire ? Double(i * 47) : 0))
                        .offset(x: fire ? CGFloat(cos(angle) * dist) : 0, y: fire ? CGFloat(sin(angle) * dist + 40) : 0)
                        .opacity(fire ? 0 : 1)
                }
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { withAnimation(.easeOut(duration: 1.4)) { fire = true } }
    }
}

/// HStack или VStack в зависимости от размера текста (крупный Dynamic Type — вертикально, без переносов посреди слова).
struct AdaptiveStack<Content: View>: View {
    let vertical: Bool
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if vertical {
            VStack(alignment: .leading, spacing: spacing) { content }
        } else {
            HStack(spacing: spacing) { content }
        }
    }
}
