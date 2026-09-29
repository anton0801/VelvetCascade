// Solver.swift — эвристика, beam-search солвер (доказательство решаемости) и «человеческий» бот.
//
// Солвер использует тот же Domain-движок и тот же детерминированный PRNG уровня: найденная
// последовательность действий воспроизводится в игре байт-в-байт (hash после каждого хода).
// Бот не подглядывает в будущий refill (оценивает ходы на копии с чужим seed) — его процент
// побед используется как автоматическая оценка сложности, а не как ручной playtest.

import Foundation
import VelvetDomain

enum Heuristic {
    /// Оценка «сколько ещё ходов нужно» (меньше — лучше).
    static func estimate(_ s: GameState) -> Double {
        if s.status == .won { return -1000 }
        var h = 0.0
        let b = s.board
        // Цвета.
        for obj in s.objectives {
            switch obj {
            case .collect:
                h += Double(s.remaining(for: obj)) / 2.2
            case .plates:
                h += Double(b.remainingPlateHP) / 1.4
            case .keys:
                break
            }
        }
        // Ключи и повороты.
        let keysOnBoard = b.keyCoords
        if !keysOnBoard.isEmpty && s.objectives.contains(.keys) {
            var maxT = 0
            var pathCost = 0.0
            for (keyID, c) in keysOnBoard {
                var bestCombined = Double.infinity
                var bestT = 0
                var bestPath = 0.0
                for p in s.exitPorts where p.accepts(keyID: keyID) {
                    let t = (p.direction.rawValue - s.q + 4) % 4
                    let cost = alignCost(c, p, s)
                    let combined = Double(t) * 4 + cost
                    if combined < bestCombined { bestCombined = combined; bestT = t; bestPath = cost }
                }
                maxT = max(maxT, bestT)
                pathCost += bestPath
            }
            h += pathCost
            if maxT > 0 {
                let need = Double(max(0, GameState.maxCharge - s.charge)) + Double(maxT - 1) * 10.0
                h += Double(maxT) + need / 2.4
            }
        }
        // Неактивные switch: открытие створок полезно (особенно на пути ключей).
        for c in b.cells {
            if case .switchPlate(_, let active)? = c.floor, !active { h += 0.9 }
        }
        // Потенциал специальных фишек.
        var bonus = 0.0
        for c in b.cells {
            switch c.occupant?.kind {
            case .lineSpark?: bonus += 0.7
            case .stageBurst?: bonus += 0.9
            case .prism?: bonus += 1.2
            default: break
            }
        }
        h -= min(bonus, max(0, h * 0.5))
        return h
    }

    /// Стоимость довести ключ c до порта p (без учёта поворотов).
    static func alignCost(_ c: Coord, _ p: ExitPort, _ s: GameState) -> Double {
        let b = s.board
        let d = p.direction
        let aligned: Bool
        let along: Int
        switch d {
        case .down: aligned = c.x == p.x; along = p.y - c.y
        case .up: aligned = c.x == p.x; along = c.y - p.y
        case .right: aligned = c.y == p.y; along = p.x - c.x
        case .left: aligned = c.y == p.y; along = c.x - p.x
        }
        if aligned && along >= 0 {
            var cost = 0.0
            var cur = c
            for _ in 0..<along {
                cur = cur.offset(d)
                guard b.inBounds(cur), b[cur].playable else { return 40 }
                let cell = b[cur]
                if let blk = cell.blocker {
                    switch blk {
                    case .wall: return 40
                    case .crate(let hp): cost += 1.6 * Double(hp)
                    case .shutter: cost += 2.5
                    }
                } else if cell.overlay != nil {
                    cost += 1.8
                } else if cell.occupant != nil {
                    cost += 0.55
                }
            }
            return cost
        }
        let perp = d.isVertical ? abs(c.x - p.x) : abs(c.y - p.y)
        return 3.0 + Double(perp) * 1.6 + (along < 0 ? Double(-along) * 1.2 + 2 : Double(along) * 0.4)
    }
}

struct SolveResult {
    var trace: [TraceAction]
    var finalState: GameState
    var expansions: Int
}

enum Solver {
    static func actions(_ s: GameState) -> [GameActionKind] {
        var a: [GameActionKind] = GameEngine.validSwaps(s).map { .swap(from: $0.from, to: $0.to) }
        if s.isTurnAvailable { a.append(.rotate) }
        return a
    }

    struct Node {
        var state: GameState
        var trace: [TraceAction]
        var h: Double
        var parent: Int
    }

    /// Beam search по settled-состояниям. Возвращает первое найденное выигрышное решение.
    static func solve(_ level: LevelDefinition, width: Int, deadline: Date) -> SolveResult? {
        let start = LevelFactory.initialState(for: level)
        var beam = [Node(state: start, trace: [], h: Heuristic.estimate(start), parent: 0)]
        var seen = Set<String>()
        var expansions = 0
        for depth in 0..<level.initialMoves {
            var cands: [Node] = []
            for (pi, node) in beam.enumerated() {
                if Date() > deadline { return nil }
                for (k, kind) in actions(node.state).enumerated() {
                    expansions += 1
                    let action = GameAction(id: "s\(depth)-\(k)", kind: kind)
                    guard let r = try? GameEngine.apply(action, to: node.state, recordSteps: false) else { continue }
                    let hash = StateHasher.hash(r.state)
                    let ta: TraceAction
                    switch kind {
                    case .swap(let f, let t): ta = TraceAction(action: "swap", from: f, to: t, hash: hash)
                    case .rotate: ta = TraceAction(action: "rotate", hash: hash)
                    }
                    if r.state.status == .won {
                        return SolveResult(trace: node.trace + [ta], finalState: r.state, expansions: expansions)
                    }
                    if r.state.status == .failed { continue }
                    guard seen.insert(hash).inserted else { continue }
                    cands.append(Node(state: r.state, trace: node.trace + [ta], h: Heuristic.estimate(r.state), parent: pi))
                }
            }
            if cands.isEmpty { return nil }
            cands.sort { $0.h < $1.h }
            // Разнообразие: не более maxPerParent потомков от одного родителя.
            let maxPerParent = max(3, width / 6)
            var perParent: [Int: Int] = [:]
            var next: [Node] = []
            for c in cands where next.count < width {
                let used = perParent[c.parent, default: 0]
                if used >= maxPerParent { continue }
                perParent[c.parent] = used + 1
                next.append(c)
            }
            beam = next
        }
        return nil
    }

    /// Бот без знания будущего refill: каждое действие оценивается на копии с посторонним seed.
    static func botPlay(_ level: LevelDefinition, seed: UInt64, noise: Double = 0.35) -> (won: Bool, movesUsed: Int, turns: Int) {
        var s = LevelFactory.initialState(for: level)
        var rng = LevelRNG(seed: seed)
        var step = 0
        while s.status == .playing {
            step += 1
            if step > 200 { break }
            let acts = actions(s)
            if acts.isEmpty { break }
            var best: GameActionKind?
            var bestScore = Double.infinity
            // Общие случайные числа: все ходы оцениваются на одних и тех же двух выборках refill
            // (не на реальном seed уровня) — бот не знает будущего и не переоценивает «шумные» ходы.
            let probeSeeds = [rng.next(), rng.next()]
            for (k, kind) in acts.enumerated() {
                var total = 0.0
                var ok = true
                for (j, ps) in probeSeeds.enumerated() {
                    var probe = s
                    probe.rng = LevelRNG(seed: ps)
                    guard let r = try? GameEngine.apply(GameAction(id: "p\(step)-\(k)-\(j)", kind: kind), to: probe, recordSteps: false) else { ok = false; break }
                    total += Heuristic.estimate(r.state)
                }
                guard ok else { continue }
                let score = total / Double(probeSeeds.count) + Double(rng.nextInt(below: 1000)) / 1000.0 * noise
                if score < bestScore { bestScore = score; best = kind }
            }
            guard let chosen = best,
                  let r = try? GameEngine.apply(GameAction(id: "b\(step)", kind: chosen), to: s, recordSteps: false) else { break }
            s = r.state
        }
        return (s.status == .won, s.movesUsed, s.turnsUsed)
    }

    static func botWinRate(_ level: LevelDefinition, runs: Int) -> (rate: Double, avgMovesOnWin: Double) {
        var wins = 0
        var moves = 0
        for i in 0..<runs {
            let r = botPlay(level, seed: UInt64(level.id) &* 97 &+ UInt64(i) &* 131 &+ 7)
            if r.won { wins += 1; moves += r.movesUsed }
        }
        return (Double(wins) / Double(runs), wins > 0 ? Double(moves) / Double(wins) : 0)
    }
}
