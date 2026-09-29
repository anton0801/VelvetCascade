// Inspect.swift — отладочный вывод воспроизведения уровня (LevelForge inspect --level N).
import Foundation
import VelvetDomain

func boardASCII(_ b: Board) -> String {
    var s = ""
    for y in 0..<b.n {
        for x in 0..<b.n {
            let c = b[Coord(x, y)]
            if !c.playable { s += " ."; continue }
            if let bl = c.blocker {
                switch bl { case .wall: s += " #"; case .crate(let hp): s += " X\(hp)".suffix(2).description; case .shutter: s += " Z" }
                continue
            }
            var ch = "?"
            switch c.occupant?.kind {
            case .gem(let g)?: ch = g.letter
            case .lineSpark(let g, let a)?: ch = a == .horizontal ? "-" : "|"; _ = g
            case .stageBurst?: ch = "*"
            case .prism?: ch = "P"
            case .key(let k)?: ch = "\(k)"
            case nil: ch = "_"
            }
            if c.overlay != nil { ch = ch.lowercased() }
            s += " " + ch
        }
        s += "\n"
    }
    return s
}

func runInspect(root: URL, id: Int) {
    let url = root.appendingPathComponent(String(format: "VelvetCascade/Resources/Levels/level_%03d.json", id))
    guard let data = try? Data(contentsOf: url), let def = try? JSONDecoder().decode(LevelDefinition.self, from: data) else { print("no level"); return }
    var s = LevelFactory.initialState(for: def)
    print("Level \(id) \(def.title) moves \(def.initialMoves) charge \(def.initialCharge) objectives \(def.objectives)")
    print("ports \(def.exitPorts)")
    print(boardASCII(s.board))
    for (i, t) in def.solutionTrace.enumerated() {
        let r = try! GameEngine.apply(GameAction(id: "i\(i)", kind: t.gameAction!), to: s)
        let waves = r.steps.compactMap { if case .wave(let w) = $0.event { return w } else { return nil } }
        print("#\(i) \(t.action) \(t.from.map { "\($0)" } ?? "") \(t.to.map { "\($0)" } ?? "") waves=\(waves.count) removed=\(waves.map { $0.removed.count }) created=\(waves.flatMap { $0.created.map { "\($0.occupant.kind)" } }) effects=\(waves.map { $0.effects.count }) collected=\(r.state.collected) charge=\(r.state.charge) q=\(r.state.q)")
        s = r.state
    }
    print(boardASCII(s.board))
    print("status \(s.status)")
}

func runDiagnose(root: URL, id: Int) {
    let csv = root.appendingPathComponent("docs/spec/LEVEL_BRIEFS.csv").path
    guard let brief = (try? BriefParser.load(path: csv))?.first(where: { $0.id == id }) else { return }
    print("brief \(id): keys \(brief.keys.map { $0.direction.label }) shutters \(brief.shutterCells)/\(brief.switchCells) crates \(brief.crates1)/\(brief.crates2) walls \(brief.walls) ice \(brief.ice1)/\(brief.ice2) chains \(brief.chains) plates \(brief.platesHP1)/\(brief.platesHP2)")
    var stages: [String: Int] = [:]
    for attempt in 0..<40 {
        var l = Layout(brief: brief, attempt: attempt)
        if !l.placeKeys() { stages["keys", default: 0] += 1; continue }
        if !l.placeShutters() { stages["shutters", default: 0] += 1; continue }
        if !l.placeWalls() { stages["walls", default: 0] += 1; continue }
        if !l.placeCrates() { stages["crates", default: 0] += 1; continue }
        if !l.placePlates() { stages["plates", default: 0] += 1; continue }
        if !l.placeOverlays() { stages["overlays", default: 0] += 1; continue }
        if l.fill() == nil { stages["fill", default: 0] += 1; continue }
        stages["ok", default: 0] += 1
    }
    print(stages)
}

func runBotDebug(root: URL, id: Int, seed: UInt64) {
    let url = root.appendingPathComponent(String(format: "VelvetCascade/Resources/Levels/level_%03d.json", id))
    guard let data = try? Data(contentsOf: url), let def = try? JSONDecoder().decode(LevelDefinition.self, from: data) else { return }
    var s = LevelFactory.initialState(for: def)
    var rng = LevelRNG(seed: seed)
    var step = 0
    while s.status == .playing && step < 200 {
        step += 1
        let acts = Solver.actions(s)
        var best: GameActionKind?
        var bestScore = Double.infinity
        for (k, kind) in acts.enumerated() {
            var probe = s
            probe.rng = LevelRNG(seed: rng.next())
            guard let r = try? GameEngine.apply(GameAction(id: "p\(step)-\(k)", kind: kind), to: probe, recordSteps: false) else { continue }
            let score = Heuristic.estimate(r.state) + Double(rng.nextInt(below: 1000)) / 1000.0 * 0.35
            if ProcessInfo.processInfo.environment["BOTSTEP"] == "\(step)" { print("   cand \(kind) score=\(String(format: "%.2f", score)) status=\(r.state.status)") }
            if score < bestScore { bestScore = score; best = kind }
        }
        guard let chosen = best, let r = try? GameEngine.apply(GameAction(id: "b\(step)", kind: chosen), to: s, recordSteps: false) else { break }
        s = r.state
        let sw = s.board.cells.enumerated().compactMap { (i, c) -> String? in if case .switchPlate(let g, let a)? = c.floor { return "\(g):\(a ? "on" : "off")" } else { return nil } }
        print("\(step) \(chosen) h=\(String(format: "%.2f", Heuristic.estimate(s))) q=\(s.q) ch=\(s.charge) mv=\(s.movesLeft) keys=\(s.board.keyCoords.map { "\($0.keyID)@\($0.coord)" }) ext=\(s.extractedKeyIDs) sw=\(sw) rem=\(s.objectives.map { s.remaining(for: $0) })")
    }
    print(boardASCII(s.board))
    print(s.status)
}
