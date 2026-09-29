// BoardView.swift — BoardRenderer: поле в локальных координатах, поворот сцены R^q, hit testing через inverseR.
//
// Viewport — квадрат min(screenWidth−32, 430); inset 8, gap 2. Во время поворота квадрат по диагонали
// шире исходного: масштаб 1/(|cos θ|+|sin θ|) = 0.7071 на 45°, чтобы углы не обрезались.
// HUD, фон и кнопки неподвижны; позиции клеток поворачиваются, glyphs предметов компенсируют поворот.

import SwiftUI
import VelvetDomain

struct BoardGeometry {
    let n: Int
    let viewport: CGFloat
    let inset: CGFloat = 8
    let gap: CGFloat = 2

    var cell: CGFloat { (viewport - inset * 2 - gap * CGFloat(n - 1)) / CGFloat(n) }
    var step: CGFloat { cell + gap }

    /// Центр клетки в неповёрнутом содержимом (локальные координаты).
    func center(_ c: Coord) -> CGPoint {
        CGPoint(x: inset + CGFloat(c.x) * step + cell / 2, y: inset + CGFloat(c.y) * step + cell / 2)
    }

    /// Экранная клетка под точкой (в неповёрнутой рамке viewport).
    func screenCell(at p: CGPoint) -> Coord? {
        let x = Int(floor((p.x - inset + gap / 2) / step))
        let y = Int(floor((p.y - inset + gap / 2) / step))
        guard x >= 0, y >= 0, x < n, y < n else { return nil }
        return Coord(x, y)
    }
}

/// Поворот сцены: угол анимируется, масштаб вычисляется из угла.
struct StageRotation: AnimatableModifier {
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let r = angle * .pi / 180
        let scale = 1 / (abs(cos(r)) + abs(sin(r)))
        return content
            .rotationEffect(.degrees(angle))
            .scaleEffect(scale)
    }
}

/// Компенсация поворота для glyph предмета.
struct CounterRotation: AnimatableModifier {
    var angle: Double
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }
    func body(content: Content) -> some View { content.rotationEffect(.degrees(-angle)) }
}

struct PieceModel: Identifiable, Equatable {
    let id: Int
    let kind: OccupantKind
    let cell: Coord
    let pinned: Bool
}

struct BoardView: View {
    @ObservedObject var session: GameSession
    let viewport: CGFloat
    var highContrast: Bool
    var gravityLabels: Bool
    var dimmed: Bool = false

    private var geo: BoardGeometry { BoardGeometry(n: session.n, viewport: viewport) }

    var pieces: [PieceModel] {
        var r: [PieceModel] = []
        let b = session.board
        for i in 0..<b.cells.count {
            if let o = b.cells[i].occupant {
                r.append(PieceModel(id: o.id, kind: o.kind, cell: b.coord(i), pinned: b.cells[i].overlay != nil))
            }
        }
        return r.sorted { $0.id < $1.id }
    }

    var body: some View {
        ZStack {
            BoardFrameView(viewport: viewport)
            content
                .frame(width: viewport, height: viewport)
                .modifier(StageRotation(angle: session.displayAngle))
                .id(session.crossfadeToken)
                .transition(.opacity)
            if let p = session.preview { TurnArrowOverlay(viewport: viewport, preview: p) }
            GestureLayer(session: session, geo: geo)
            AccessibilityBoardAdapter(session: session, geo: geo)
        }
        .frame(width: viewport, height: viewport)
    }

    private var content: some View {
        let g = geo
        let angle = session.displayAngle
        return ZStack(alignment: .topLeading) {
            // Клетки, полы, блокеры (статические слои).
            ForEach(0..<(g.n * g.n), id: \.self) { i in
                let c = session.board.coord(i)
                let cell = session.board.cells[i]
                if cell.playable {
                    CellLayerView(cell: cell, size: g.cell, angle: angle, highContrast: highContrast,
                                  links: session.level.shutterSwitchLinks)
                        .frame(width: g.cell, height: g.cell)
                        .position(g.center(c))
                }
            }
            // Подсветка frontier (preview/Sweep).
            ForEach(frontierCells, id: \.self) { c in
                RoundedRectangle(cornerRadius: 5)
                    .fill(Palette.spotlightGold.opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.spotlightGold, lineWidth: 2))
                    .frame(width: g.cell, height: g.cell)
                    .position(g.center(c))
                    .allowsHitTesting(false)
            }
            // Фишки и ключи.
            ForEach(pieces) { p in
                PieceView(model: p, size: g.cell, angle: angle, highContrast: highContrast)
                    .frame(width: g.cell, height: g.cell)
                    .offset(invalidOffset(p))
                    .position(g.center(p.cell))
                    .transition(transition(for: p))
                    .zIndex(p.kind.isKey ? 2 : 1)
            }
            // Overlays поверх фишек (ice/chain).
            ForEach(0..<(g.n * g.n), id: \.self) { i in
                let cell = session.board.cells[i]
                if cell.playable, let ov = cell.overlay {
                    OverlayLayerView(overlay: ov, size: g.cell, angle: angle)
                        .frame(width: g.cell, height: g.cell)
                        .position(g.center(session.board.coord(i)))
                        .transition(.opacity)
                        .zIndex(3)
                }
            }
            // Выходы.
            ForEach(Array(session.level.exitPorts.enumerated()), id: \.offset) { _, port in
                PortView(port: port, active: port.direction == Direction.gravity(forOrientation: session.hudQ),
                         size: g.cell, angle: angle, done: port.keyID.map { session.hudExtracted.contains($0) } ?? false,
                         inner: session.board.inBounds(port.coord.offset(port.direction)), step: g.step)
                    .frame(width: g.cell, height: g.cell)
                    .position(g.center(port.coord))
                    .zIndex(4)
                    .allowsHitTesting(false)
            }
            // Выделение и подсказка.
            if let s = session.selected {
                SelectionFrame(size: g.cell).position(g.center(s)).zIndex(5)
            }
            if let h = session.hintSwap {
                ForEach([h.0, h.1], id: \.self) { c in
                    RoundedRectangle(cornerRadius: 6).stroke(Palette.spotlightGold, lineWidth: 2)
                        .frame(width: g.cell, height: g.cell).position(g.center(c)).zIndex(5)
                }
            }
            // Эффекты specials.
            ForEach(session.effects) { e in
                EffectView(effect: e, geo: g).zIndex(6)
            }
        }
        .frame(width: viewport, height: viewport, alignment: .topLeading)
        .overlay(Color.black.opacity(dimmed ? 0.28 : 0).allowsHitTesting(false))
    }

    private var frontierCells: [Coord] {
        if let p = session.preview { return p.frontier }
        return session.sweepHighlight
    }

    private func invalidOffset(_ p: PieceModel) -> CGSize {
        guard let (a, b) = session.invalidPair else { return .zero }
        let other: Coord
        if p.cell == a { other = b } else if p.cell == b { other = a } else { return .zero }
        let k = geo.step * 0.28
        return CGSize(width: CGFloat(other.x - p.cell.x) * k, height: CGFloat(other.y - p.cell.y) * k)
    }

    private func transition(for p: PieceModel) -> AnyTransition {
        let g = Direction.gravity(forOrientation: session.hudQ).vector
        let drop = CGFloat(session.spawnDrops[p.id] ?? 1)
        let insertion = AnyTransition.offset(x: -CGFloat(g.dx) * drop * geo.step, y: -CGFloat(g.dy) * drop * geo.step)
            .combined(with: .opacity)
        if let d = session.exitingKeys[p.id] {
            let v = d.vector
            return .asymmetric(insertion: insertion,
                               removal: AnyTransition.offset(x: CGFloat(v.dx) * geo.step * 1.2, y: CGFloat(v.dy) * geo.step * 1.2)
                                .combined(with: .opacity))
        }
        return .asymmetric(insertion: insertion, removal: AnyTransition.scale(scale: 0.2).combined(with: .opacity))
    }
}

// MARK: - Frame / cells

/// UI05: угловые латунные крепления 12 pt, двойной контур, тёмный настил #211426, дуга позади.
struct BoardFrameView: View {
    let viewport: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(LinearGradient(colors: [Palette.antiqueGold.opacity(0.55), Palette.goldBottom.opacity(0.15)], startPoint: .top, endPoint: .bottom), lineWidth: 6)
                .frame(width: viewport * 1.2, height: viewport * 1.2)
                .mask(Rectangle().frame(width: viewport * 1.3, height: viewport * 0.72).offset(y: -viewport * 0.3))
                .frame(width: viewport, height: viewport)
                .accessibilityHidden(true)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.boardFloor)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.antiqueGold, lineWidth: 1.2)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .inset(by: 3)
                .stroke(Palette.antiqueGold.opacity(0.45), lineWidth: 0.8)
            ForEach(0..<4, id: \.self) { i in
                CornerMount()
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(Double(i) * 90))
                    .position(x: i == 0 || i == 3 ? 5 : viewport - 5, y: i < 2 ? 5 : viewport - 5)
            }
        }
        .frame(width: viewport, height: viewport)
        .accessibilityHidden(true)
    }
}

struct CornerMount: View {
    var body: some View {
        Canvas { ctx, s in
            var p = Path()
            p.move(to: CGPoint(x: 0, y: s.height))
            p.addLine(to: CGPoint(x: 0, y: 3))
            p.addQuadCurve(to: CGPoint(x: 3, y: 0), control: .zero)
            p.addLine(to: CGPoint(x: s.width, y: 0))
            ctx.stroke(p, with: .color(Palette.spotlightGold), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: 2.5, y: 2.5, width: 3, height: 3)), with: .color(Palette.goldTop))
        }
    }
}

/// UI06 + полы + блокеры одной клетки.
struct CellLayerView: View {
    let cell: Cell
    let size: CGFloat
    let angle: Double
    let highContrast: Bool
    let links: [ShutterSwitchLink]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.cellFill)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Palette.cellEdge, lineWidth: 0.5)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            switch cell.floor {
            case .plate(let hp)?:
                ArtImage(name: "vc_velvet_plate", maxPoints: size).frame(width: size, height: size)
                DamageStuds(hp: hp).frame(width: size, height: size)
            case .switchPlate(let group, let active)?:
                ArtImage(name: "vc_switch", maxPoints: size * 0.8)
                    .frame(width: size * 0.8, height: size * 0.8)
                    .scaleEffect(active ? 0.9 : 1)
                    .brightness(active ? -0.12 : 0)
                GlyphBadge(text: ShutterSwitchLink.glyph(for: group), active: active, size: size)
                    .modifier(CounterRotation(angle: angle))
            case nil:
                EmptyView()
            }
            switch cell.blocker {
            case .crate(let hp)?:
                ArtImage(name: "vc_crate", maxPoints: size).frame(width: size * 0.94, height: size * 0.94)
                if hp == 1 { CrackMark().stroke(Color.black.opacity(0.55), lineWidth: 1.4).frame(width: size * 0.5, height: size * 0.5) }
                DamageStuds(hp: hp).frame(width: size, height: size)
            case .wall?:
                ArtImage(name: "vc_baffle", maxPoints: size).frame(width: size, height: size)
            case .shutter(let group)?:
                ArtImage(name: "vc_shutter_closed", maxPoints: size).frame(width: size, height: size)
                GlyphBadge(text: ShutterSwitchLink.glyph(for: group), active: false, size: size)
                    .modifier(CounterRotation(angle: angle))
            case nil:
                EmptyView()
            }
        }
    }
}

/// UI14: HP2 — два ivory studs 3 pt у нижнего края, HP1 — один.
struct DamageStuds: View {
    let hp: Int
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 3) {
                ForEach(0..<hp, id: \.self) { _ in
                    Circle().fill(Palette.warmIvory).frame(width: 3.5, height: 3.5)
                        .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
                }
            }
            .position(x: g.size.width / 2, y: g.size.height - 5)
        }
        .accessibilityHidden(true)
    }
}

struct CrackMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.2))
        p.addLine(to: CGPoint(x: r.midX * 0.9, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX * 1.1, y: r.midY * 0.8))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY * 0.9))
        return p
    }
}

/// UI15: ромбовидный badge с glyph группы A/B/C.
struct GlyphBadge: View {
    let text: String
    let active: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(active ? Palette.success : Palette.panel)
                .frame(width: size * 0.26, height: size * 0.26)
                .rotationEffect(.degrees(45))
                .overlay(Rectangle().stroke(Palette.spotlightGold, lineWidth: 0.8).frame(width: size * 0.26, height: size * 0.26).rotationEffect(.degrees(45)))
            Text(text).font(.system(size: max(8, size * 0.2), weight: .bold)).foregroundColor(active ? Palette.ink : Palette.warmIvory)
        }
        .frame(width: size, height: size, alignment: .topTrailing)
        .offset(x: -size * 0.02, y: size * 0.02)
        .allowsHitTesting(false)
    }
}

struct OverlayLayerView: View {
    let overlay: Overlay
    let size: CGFloat
    let angle: Double

    var body: some View {
        switch overlay {
        case .ice(let hp):
            ZStack {
                ArtImage(name: "vc_ice_overlay", maxPoints: size).frame(width: size, height: size)
                if hp == 1 {
                    CrackMark().stroke(Color.white.opacity(0.85), lineWidth: 1).frame(width: size * 0.7, height: size * 0.7)
                    CrackMark().stroke(Palette.sapphire.opacity(0.9), lineWidth: 0.8).frame(width: size * 0.5, height: size * 0.5).rotationEffect(.degrees(120))
                }
                DamageStuds(hp: hp).frame(width: size, height: size)
            }
        case .chain:
            ArtImage(name: "vc_chain_overlay", maxPoints: size).frame(width: size, height: size)
        }
    }
}

// MARK: - Pieces

struct PieceView: View {
    let model: PieceModel
    let size: CGFloat
    let angle: Double
    let highContrast: Bool

    var body: some View {
        ZStack {
            switch model.kind {
            case .gem(let c):
                token(GemArt.name(c), color: c)
            case .lineSpark(let c, let axis):
                token(GemArt.name(c), color: c)
                LineSparkOverlay(axis: axis).frame(width: size * 0.9, height: size * 0.9)
            case .stageBurst(let c):
                ArtImage(name: "vc_special_burst", maxPoints: size * 0.82)
                    .frame(width: size * 0.82, height: size * 0.82)
                    .modifier(CounterRotation(angle: angle))
                ArtImage(name: GemArt.name(c), maxPoints: size * 0.36)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .offset(x: size * 0.24, y: size * 0.24)
                    .modifier(CounterRotation(angle: angle))
            case .prism:
                ArtImage(name: "vc_special_prism", maxPoints: size * 0.82)
                    .frame(width: size * 0.82, height: size * 0.82)
                    .modifier(CounterRotation(angle: angle))
            case .key(let id):
                ArtImage(name: "vc_stage_key", maxPoints: size * 0.8)
                    .frame(width: size * 0.78, height: size * 0.78)
                    .modifier(CounterRotation(angle: angle))
                KeyNumber(id: id, size: size).modifier(CounterRotation(angle: angle))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func token(_ name: String, color: GemColor) -> some View {
        ZStack {
            if highContrast {
                Circle().fill(Palette.deepVelvet.opacity(0.85)).frame(width: size * 0.9, height: size * 0.9)
                Circle().stroke(Palette.warmIvory, lineWidth: 2).frame(width: size * 0.9, height: size * 0.9)
            }
            ArtImage(name: name, maxPoints: size * 0.8).frame(width: size * 0.79, height: size * 0.79)
            if highContrast { HighContrastPips(color: color, size: size) }
        }
        .modifier(CounterRotation(angle: angle))
    }
}

/// High Contrast: дополнительный узор (число точек = порядковый номер формы), формы не меняются.
struct HighContrastPips: View {
    let color: GemColor
    let size: CGFloat
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0...color.rawValue, id: \.self) { _ in Circle().fill(Palette.warmIvory).frame(width: 3, height: 3) }
        }
        .padding(2)
        .background(Capsule().fill(Color.black.opacity(0.7)))
        .frame(width: size, height: size, alignment: .bottom)
        .offset(y: -1)
    }
}

/// UI13: две параллельные светлые полосы 2 pt с промежутком 2 вдоль localAxis, золотые наконечники.
struct LineSparkOverlay: View {
    let axis: VelvetDomain.Axis
    var body: some View {
        Canvas { ctx, s in
            for k in [-2.0, 2.0] {
                var p = Path()
                if axis == .horizontal {
                    p.move(to: CGPoint(x: s.width * 0.06, y: s.height / 2 + k))
                    p.addLine(to: CGPoint(x: s.width * 0.94, y: s.height / 2 + k))
                } else {
                    p.move(to: CGPoint(x: s.width / 2 + k, y: s.height * 0.06))
                    p.addLine(to: CGPoint(x: s.width / 2 + k, y: s.height * 0.94))
                }
                ctx.stroke(p, with: .color(Palette.warmIvory.opacity(0.95)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            let tips: [CGPoint] = axis == .horizontal
                ? [CGPoint(x: s.width * 0.05, y: s.height / 2), CGPoint(x: s.width * 0.95, y: s.height / 2)]
                : [CGPoint(x: s.width / 2, y: s.height * 0.05), CGPoint(x: s.width / 2, y: s.height * 0.95)]
            for t in tips {
                ctx.fill(Path(ellipseIn: CGRect(x: t.x - 3, y: t.y - 3, width: 6, height: 6)), with: .color(Palette.spotlightGold))
            }
        }
        .allowsHitTesting(false)
    }
}

struct KeyNumber: View {
    let id: Int
    let size: CGFloat
    var body: some View {
        Text("\(id)")
            .font(.system(size: max(9, size * 0.24), weight: .heavy, design: .rounded))
            .foregroundColor(Palette.ink)
            .frame(width: size * 0.32, height: size * 0.32)
            .background(Circle().fill(Palette.warmIvory))
            .overlay(Circle().stroke(Palette.antiqueGold, lineWidth: 1))
            .frame(width: size, height: size, alignment: .topLeading)
            .offset(x: size * 0.02, y: size * 0.02)
    }
}

/// Выход: арка VC15 за внешней кромкой клетки (в пустой клетке, если она внутри поля) + наружная стрелка
/// и номер ключа; Active — золото, Inactive — Muted Rose, выход пройден — Success.
struct PortView: View {
    let port: ExitPort
    let active: Bool
    let size: CGFloat
    let angle: Double
    let done: Bool
    let inner: Bool
    let step: CGFloat

    var body: some View {
        let v = port.direction.vector
        let color = done ? Palette.success : (active ? Palette.spotlightGold : Palette.mutedRose)
        let archSize = inner ? size * 0.78 : size * 0.5
        let archOffset = inner ? step : size * 0.5 + 4
        ZStack {
            EdgeLine(direction: port.direction).stroke(color, style: StrokeStyle(lineWidth: active ? 3.5 : 2, lineCap: .round))
            ZStack {
                if inner {
                    RoundedRectangle(cornerRadius: 6).fill(Palette.plumStage.opacity(0.9))
                        .frame(width: size * 0.92, height: size * 0.92)
                    RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: size * 0.92, height: size * 0.92)
                }
                ArtImage(name: "vc_exit_port", maxPoints: archSize)
                    .frame(width: archSize, height: archSize)
                    .opacity(active || done ? 1 : 0.75)
                    .modifier(CounterRotation(angle: angle))
                if let k = port.keyID {
                    Text("\(k)")
                        .font(.system(size: max(9, size * 0.22), weight: .heavy, design: .rounded))
                        .foregroundColor(Palette.ink)
                        .frame(width: size * 0.28, height: size * 0.28)
                        .background(Circle().fill(color))
                        .modifier(CounterRotation(angle: angle))
                        .offset(x: CGFloat(-v.dy) * archSize * 0.45, y: CGFloat(v.dx) * archSize * 0.45)
                }
            }
            .offset(x: CGFloat(v.dx) * archOffset, y: CGFloat(v.dy) * archOffset)
            OutwardArrow(direction: port.direction)
                .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.3, height: size * 0.3)
                .offset(x: CGFloat(v.dx) * (archOffset + archSize * 0.45 + size * 0.1),
                        y: CGFloat(v.dy) * (archOffset + archSize * 0.45 + size * 0.1))
        }
    }
}

struct EdgeLine: Shape {
    let direction: Direction
    func path(in r: CGRect) -> Path {
        var p = Path()
        switch direction {
        case .down: p.move(to: CGPoint(x: r.minX + 3, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - 3, y: r.maxY))
        case .up: p.move(to: CGPoint(x: r.minX + 3, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX - 3, y: r.minY))
        case .left: p.move(to: CGPoint(x: r.minX, y: r.minY + 3)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - 3))
        case .right: p.move(to: CGPoint(x: r.maxX, y: r.minY + 3)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 3))
        }
        return p
    }
}

struct OutwardArrow: Shape {
    let direction: Direction
    func path(in r: CGRect) -> Path {
        let v = direction.vector
        let c = CGPoint(x: r.midX, y: r.midY)
        let tip = CGPoint(x: c.x + CGFloat(v.dx) * r.width * 0.45, y: c.y + CGFloat(v.dy) * r.height * 0.45)
        let perp = CGPoint(x: -CGFloat(v.dy), y: CGFloat(v.dx))
        var p = Path()
        p.move(to: CGPoint(x: tip.x - CGFloat(v.dx) * r.width * 0.4 + perp.x * r.width * 0.35, y: tip.y - CGFloat(v.dy) * r.height * 0.4 + perp.y * r.height * 0.35))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x - CGFloat(v.dx) * r.width * 0.4 - perp.x * r.width * 0.35, y: tip.y - CGFloat(v.dy) * r.height * 0.4 - perp.y * r.height * 0.35))
        return p
    }
}

/// UI06 Selected: ivory 2 pt + угловые brackets.
struct SelectionFrame: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).stroke(Palette.warmIvory, lineWidth: 2)
            ForEach(0..<4, id: \.self) { i in
                CornerMount().frame(width: 9, height: 9).rotationEffect(.degrees(Double(i) * 90))
                    .position(x: i == 0 || i == 3 ? 3 : size - 3, y: i < 2 ? 3 : size - 3)
            }
        }
        .frame(width: size + 4, height: size + 4)
        .allowsHitTesting(false)
    }
}

// MARK: - Effects

struct EffectView: View {
    let effect: BoardEffect
    let geo: BoardGeometry
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch effect.kind {
            case .line(let o, let axis):
                beam(o, axis)
            case .band(let c):
                ForEach(-1...1, id: \.self) { d in
                    beam(Coord(c.x, c.y + d), .horizontal)
                    beam(Coord(c.x + d, c.y), .vertical)
                }
            case .burst(let c, let r):
                let side = geo.step * CGFloat(r * 2 + 1)
                RoundedRectangle(cornerRadius: 10)
                    .fill(RadialGradient(colors: [Palette.goldTop.opacity(0.85), Palette.brightCrimson.opacity(0.35), .clear],
                                         center: .center, startRadius: 2, endRadius: side * 0.6))
                    .frame(width: side, height: side)
                    .scaleEffect(0.4 + progress * 0.7)
                    .opacity(Double(1 - progress * 0.7))
                    .position(geo.center(c))
            case .colorClear(let o, let targets):
                ForEach(targets, id: \.self) { t in
                    Path { p in p.move(to: geo.center(o)); p.addLine(to: geo.center(t)) }
                        .stroke(Palette.warmIvory.opacity(Double(0.7 - progress * 0.5)), lineWidth: 1.5)
                    Circle().fill(Palette.goldTop.opacity(0.7)).frame(width: geo.cell * 0.6, height: geo.cell * 0.6)
                        .scaleEffect(0.5 + progress).opacity(Double(1 - progress)).position(geo.center(t))
                }
            case .allCells:
                Rectangle().fill(Palette.goldTop.opacity(Double(0.5 - progress * 0.45)))
                    .frame(width: geo.viewport, height: geo.viewport)
            case .sparks(let c):
                SparkEmitter(count: 12, area: CGSize(width: geo.cell * 2, height: geo.cell * 2), seed: c.x * 31 + c.y)
                    .position(geo.center(c))
            }
        }
        .frame(width: geo.viewport, height: geo.viewport, alignment: .topLeading)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { progress = 1 } }
    }

    private func beam(_ c: Coord, _ axis: VelvetDomain.Axis) -> some View {
        let long = geo.viewport - geo.inset
        let thick = geo.cell * 0.46
        let center = axis == .horizontal ? CGPoint(x: geo.viewport / 2, y: geo.center(c).y) : CGPoint(x: geo.center(c).x, y: geo.viewport / 2)
        return Capsule()
            .fill(LinearGradient(colors: [.clear, Palette.warmIvory.opacity(0.95), Palette.spotlightGold, Palette.warmIvory.opacity(0.95), .clear],
                                 startPoint: axis == .horizontal ? .top : .leading, endPoint: axis == .horizontal ? .bottom : .trailing))
            .frame(width: axis == .horizontal ? long * max(0.2, progress) : thick, height: axis == .horizontal ? thick : long * max(0.2, progress))
            .opacity(Double(1.1 - progress * 0.6))
            .position(center)
    }
}

/// Внешняя стрелка 90° по часовой стрелке вокруг поля (Turn Preview), вне содержимого клеток.
struct TurnArrowOverlay: View {
    let viewport: CGFloat
    let preview: TurnPreview
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            Path { p in
                p.addArc(center: CGPoint(x: viewport / 2, y: viewport / 2), radius: viewport * 0.56,
                         startAngle: .degrees(-135), endAngle: .degrees(-45), clockwise: false)
            }
            .stroke(Palette.spotlightGold, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6], dashPhase: phase))
            let a = -45.0 * .pi / 180
            let tip = CGPoint(x: viewport / 2 + CGFloat(cos(a)) * viewport * 0.56, y: viewport / 2 + CGFloat(sin(a)) * viewport * 0.56)
            Path { p in
                p.move(to: CGPoint(x: tip.x - 14, y: tip.y - 4))
                p.addLine(to: tip)
                p.addLine(to: CGPoint(x: tip.x - 4, y: tip.y + 14))
            }
            .stroke(Palette.spotlightGold, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .frame(width: viewport, height: viewport)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { phase = -28 } }
    }
}

// MARK: - Input

/// Неповёрнутый слой ввода: tap-then-tap, swipe и long press; экранная клетка → локальная через inverseR.
struct GestureLayer: View {
    @ObservedObject var session: GameSession
    let geo: BoardGeometry
    @State private var startScreen: Coord?
    @State private var swiped = false
    @State private var longPressTask: DispatchWorkItem?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        if startScreen == nil {
                            startScreen = geo.screenCell(at: v.startLocation)
                            swiped = false
                            if let s = startScreen {
                                let work = DispatchWorkItem {
                                    if !swiped { session.longPress(local: session.localCell(fromScreen: s)); swiped = true }
                                }
                                longPressTask = work
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
                            }
                        }
                        let t = v.translation
                        if abs(t.width) > 6 || abs(t.height) > 6 { longPressTask?.cancel() }
                        guard !swiped, let s = startScreen else { return }
                        let threshold = geo.cell * 0.35
                        if max(abs(t.width), abs(t.height)) > threshold {
                            let d: Direction = abs(t.width) > abs(t.height) ? (t.width > 0 ? .right : .left) : (t.height > 0 ? .down : .up)
                            swiped = true
                            session.swipe(fromLocal: session.localCell(fromScreen: s), screenDirection: d)
                        }
                    }
                    .onEnded { _ in
                        longPressTask?.cancel()
                        if !swiped, let s = startScreen {
                            session.tap(local: session.localCell(fromScreen: s))
                        }
                        startScreen = nil
                        swiped = false
                    }
            )
            .accessibilityHidden(true)
    }
}
