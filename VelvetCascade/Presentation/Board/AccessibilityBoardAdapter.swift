// AccessibilityBoardAdapter.swift — VoiceOver: выбор клетки, row/column, содержимое и явное «Swap with …».
// Строки и колонки считаются по экрану (как их видит игрок); swap-направления тоже экранные,
// преобразование в локальные координаты выполняет inverseR.

import SwiftUI
import VelvetDomain

enum CellDescriber {
    static func describe(_ cell: Cell, at local: Coord, state: GameState, ports: [ExitPort], extracted: [Int]) -> String {
        guard cell.playable else { return "Empty space" }
        var parts: [String] = []
        switch cell.blocker {
        case .crate(let hp)?: parts.append(hp == 2 ? "Sturdy crate, 2 hits" : "Crate, 1 hit")
        case .wall?: parts.append("Brass baffle")
        case .shutter(let g)?: parts.append("Closed shutter \(ShutterSwitchLink.glyph(for: g))")
        case nil: break
        }
        if let o = cell.occupant { parts.append(describe(o.kind)) }
        switch cell.overlay {
        case .ice(let hp)?: parts.append(hp == 2 ? "under thick ice" : "under ice")
        case .chain?: parts.append("chained")
        case nil: break
        }
        switch cell.floor {
        case .plate(let hp)?: parts.append(hp == 2 ? "on a double Velvet Plate" : "on a Velvet Plate")
        case .switchPlate(let g, let active)?: parts.append("on switch \(ShutterSwitchLink.glyph(for: g))\(active ? ", on" : "")")
        case nil: break
        }
        for p in ports where p.coord == local {
            let active = p.direction == state.gravity
            parts.append("exit\(p.keyID.map { " for key \($0)" } ?? "") facing \(p.direction.label), \(active ? "active" : "inactive")")
        }
        if parts.isEmpty { parts.append("Empty") }
        return parts.joined(separator: ", ")
    }

    static func describe(_ k: OccupantKind) -> String {
        switch k {
        case .gem(let c): return "\(c.name) gem"
        case .lineSpark(let c, let a): return "\(c.name) LineSpark, \(a == .horizontal ? "row" : "column") beam"
        case .stageBurst(let c): return "\(c.name) Stage Burst"
        case .prism: return "Prism"
        case .key(let id): return "Key \(id)"
        }
    }
}

struct AccessibilityBoardAdapter: View {
    @ObservedObject var session: GameSession
    let geo: BoardGeometry

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<(geo.n * geo.n), id: \.self) { i in
                let screen = Coord(i % geo.n, i / geo.n)
                let local = BoardTransform.toLocal(screen, q: session.state.q, n: geo.n)
                let cell = session.board[local]
                if cell.playable {
                    Color.clear
                        .frame(width: geo.cell, height: geo.cell)
                        .position(CGPoint(x: geo.inset + CGFloat(screen.x) * geo.step + geo.cell / 2,
                                          y: geo.inset + CGFloat(screen.y) * geo.step + geo.cell / 2))
                        .accessibilityElement()
                        .accessibilityLabel("Row \(screen.y + 1), column \(screen.x + 1)")
                        .accessibilityValue(CellDescriber.describe(cell, at: local, state: session.state,
                                                                   ports: session.level.exitPorts, extracted: session.hudExtracted)
                                            + (session.selected == local ? ", selected" : "")
                                            + (isHint(local) ? ", hint" : ""))
                        .accessibilityAddTraits(cell.isSwappable ? .isButton : [])
                        .accessibilityHint(cell.isSwappable ? "Double-tap to select. Use actions to swap." : "")
                        .accessibilityAction { session.tap(local: local) }
                        .modifier(SwapActions(enabled: cell.isSwappable,
                                              names: [Direction.up, .down, .left, .right].map { "Swap \($0.label.lowercased()) with \(neighborName(screen, $0))" },
                                              perform: { d in session.swipe(fromLocal: local, screenDirection: d) }))
                }
            }
        }
        .frame(width: geo.viewport, height: geo.viewport, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stage board")
    }

    private func isHint(_ c: Coord) -> Bool {
        guard let h = session.hintSwap else { return false }
        return h.0 == c || h.1 == c
    }

    private func neighborName(_ screen: Coord, _ d: Direction) -> String {
        let s = screen.offset(d)
        guard s.x >= 0, s.y >= 0, s.x < geo.n, s.y < geo.n else { return "edge" }
        let local = BoardTransform.toLocal(s, q: session.state.q, n: geo.n)
        guard let o = session.board[local].occupant, session.board[local].playable else { return "empty space" }
        return CellDescriber.describe(o.kind)
    }
}

/// iOS 15: именованные accessibility-действия swap в экранных направлениях.
struct SwapActions: ViewModifier {
    let enabled: Bool
    let names: [String]
    let perform: (Direction) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityAction(named: Text(names[0])) { perform(.up) }
                .accessibilityAction(named: Text(names[1])) { perform(.down) }
                .accessibilityAction(named: Text(names[2])) { perform(.left) }
                .accessibilityAction(named: Text(names[3])) { perform(.right) }
        } else {
            content
        }
    }
}
