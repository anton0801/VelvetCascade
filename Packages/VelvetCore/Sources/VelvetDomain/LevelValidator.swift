// LevelValidator.swift — проверка LevelDefinition до запуска и воспроизведение solutionTrace.

public struct LevelValidationIssue: Hashable, Sendable, CustomStringConvertible {
    public var code: String
    public var message: String
    public var description: String { "[\(code)] \(message)" }
}

public struct ReplayReport: Sendable {
    public var ok: Bool
    public var failureIndex: Int?
    public var failure: String?
    public var finalState: GameState
    public var stars: Int?
    public var turnsUsed: Int
    public var movesUsed: Int
}

public enum LevelValidator {
    public static let allowedShapes: Set<String> = ["S6", "S8", "C7", "C8", "X7", "D7", "U8", "T8", "R8"]

    /// Структурная проверка (быстрая, выполняется перед каждым стартом уровня).
    public static func validate(_ level: LevelDefinition, campaignVersion: Int? = nil) -> [LevelValidationIssue] {
        var issues: [LevelValidationIssue] = []
        func fail(_ code: String, _ msg: String) { issues.append(LevelValidationIssue(code: code, message: msg)) }

        if !(1...180).contains(level.id) { fail("id", "Level id \(level.id) out of 1…180") }
        if !(1...9).contains(level.worldID) { fail("world", "worldID \(level.worldID) out of 1…9") }
        if (level.id - 1) / 20 + 1 != level.worldID { fail("world", "Level \(level.id) must belong to world \((level.id - 1) / 20 + 1)") }
        if let cv = campaignVersion, cv != level.campaignVersion { fail("campaign", "campaignVersion mismatch") }
        if ![6, 7, 8].contains(level.n) { fail("size", "N must be 6, 7 or 8") }
        if !allowedShapes.contains(level.shape) { fail("shape", "Unknown shape \(level.shape)") }
        if level.mask.count != level.n || level.mask.contains(where: { $0.count != level.n || $0.contains(where: { $0 != "0" && $0 != "1" }) }) {
            fail("mask", "Mask must be N rows of N '0'/'1'")
            return issues
        }
        if level.initialOrientation < 0 || level.initialOrientation > 3 { fail("q", "initialOrientation out of 0…3") }
        if level.initialMoves <= 0 || level.initialMoves > 99 { fail("moves", "initialMoves out of range") }
        if ![0, 6, 12].contains(level.initialCharge) { fail("charge", "initialCharge must be 0/6/12") }
        if level.rngAlgorithmVersion != LevelRNG.algorithmVersion { fail("rng", "Unsupported rngAlgorithmVersion") }
        if Set(level.fiveColorPalette).count != 5 { fail("palette", "fiveColorPalette must list five distinct gems") }

        let n = level.n
        func inMask(_ c: Coord) -> Bool { c.x >= 0 && c.y >= 0 && c.x < n && c.y < n && level.maskContains(c) }

        var occ: [Coord: OccupantPlacement] = [:]
        for p in level.initialOccupants {
            if !inMask(p.coord) { fail("occupant", "Occupant outside mask at \(p.coord)") }
            if occ[p.coord] != nil { fail("duplicate", "Duplicate occupant at \(p.coord)") }
            if p.kind() == nil { fail("occupant", "Invalid occupant \(p.type) at \(p.coord)") }
            occ[p.coord] = p
        }
        var floors: [Coord: FloorPlacement] = [:]
        for f in level.floors {
            if !inMask(f.coord) { fail("floor", "Floor outside mask at \(f.coord)") }
            if floors[f.coord] != nil { fail("duplicate", "Duplicate floor at \(f.coord)") }
            if f.type == "plate" && !(1...2).contains(f.hp ?? 0) { fail("floor", "Plate HP must be 1…2 at \(f.coord)") }
            if f.type == "switch" && f.group == nil { fail("floor", "Switch without group at \(f.coord)") }
            if f.type != "plate" && f.type != "switch" { fail("floor", "Unknown floor \(f.type)") }
            floors[f.coord] = f
        }
        var overlays: [Coord: OverlayPlacement] = [:]
        for o in level.overlays {
            if !inMask(o.coord) { fail("overlay", "Overlay outside mask at \(o.coord)") }
            if overlays[o.coord] != nil { fail("duplicate", "Duplicate overlay at \(o.coord)") }
            if o.type == "ice" && !(1...2).contains(o.hp) { fail("overlay", "Ice HP must be 1…2") }
            if o.type == "chain" && o.hp != 1 { fail("overlay", "Chain HP must be 1") }
            if o.type != "ice" && o.type != "chain" { fail("overlay", "Unknown overlay \(o.type)") }
            if occ[o.coord]?.type != "gem" { fail("layers", "Overlay must pin an ordinary gem at \(o.coord)") }
            overlays[o.coord] = o
        }
        var blockers: [Coord: BlockerPlacement] = [:]
        for b in level.blockers {
            if !inMask(b.coord) { fail("blocker", "Blocker outside mask at \(b.coord)") }
            if blockers[b.coord] != nil { fail("duplicate", "Duplicate blocker at \(b.coord)") }
            if b.type == "crate" && !(1...2).contains(b.hp ?? 0) { fail("blocker", "Crate HP must be 1…2") }
            if b.type == "shutter" && b.group == nil { fail("blocker", "Shutter without group") }
            if !["crate", "wall", "shutter"].contains(b.type) { fail("blocker", "Unknown blocker \(b.type)") }
            if occ[b.coord] != nil { fail("layers", "Blocked cell must not hide an occupant at \(b.coord)") }
            if overlays[b.coord] != nil { fail("layers", "Blocker and overlay in one cell at \(b.coord)") }
            if floors[b.coord] != nil { fail("layers", "Floor hidden under blocker at \(b.coord)") }
            blockers[b.coord] = b
        }
        // Полное стартовое поле: каждая свободная клетка mask занята.
        for y in 0..<n {
            for x in 0..<n {
                let c = Coord(x, y)
                if inMask(c) && blockers[c] == nil && occ[c] == nil { fail("fill", "Empty playable cell at \(c)") }
            }
        }
        // Ключи.
        let keys = level.initialOccupants.filter { $0.type == "key" }
        if keys.count > 3 { fail("keys", "More than 3 keys") }
        if Set(keys.compactMap { $0.keyID }).count != keys.count { fail("keys", "Duplicate keyID") }
        for k in keys {
            if overlays[k.coord] != nil || blockers[k.coord] != nil { fail("keys", "Key combined with ice/chain/crate/shutter at \(k.coord)") }
        }
        // Порты.
        if level.exitPorts.count > 4 { fail("ports", "More than 4 exits") }
        if Set(level.exitPorts.map { $0.coord }).count != level.exitPorts.count { fail("ports", "Duplicate port cell") }
        for p in level.exitPorts {
            if !inMask(p.coord) { fail("ports", "Port outside mask at \(p.coord)") }
            if inMask(p.coord.offset(p.direction)) { fail("ports", "Port at \(p.coord) must face outside the mask (\(p.direction.label))") }
            if blockers[p.coord] != nil { fail("ports", "Port cell blocked at \(p.coord)") }
        }
        if !keys.isEmpty && level.exitPorts.isEmpty { fail("ports", "Keys without exits") }
        for p in level.exitPorts {
            if let id = p.keyID, !keys.contains(where: { $0.keyID == id }) { fail("ports", "Port \(p.coord) bound to missing key \(id)") }
        }
        for k in keys {
            if let id = k.keyID, !level.exitPorts.contains(where: { $0.accepts(keyID: id) }) { fail("ports", "Key \(id) has no suitable exit") }
        }
        // Цели.
        let types = Set(level.objectives.map { $0.typeKey + ($0.collectColorKey ?? "") })
        if level.objectives.isEmpty { fail("objectives", "No objectives") }
        if level.objectives.count > 3 { fail("objectives", "More than 3 objectives") }
        if types.count != level.objectives.count { fail("objectives", "Duplicate objective") }
        let hasKeysObj = level.objectives.contains(.keys)
        if hasKeysObj != !keys.isEmpty { fail("objectives", "Keys objective must match key presence") }
        let hasPlates = level.floors.contains { $0.type == "plate" }
        if level.objectives.contains(.plates) != hasPlates { fail("objectives", "Plates objective must match plate presence") }
        for o in level.objectives {
            if case .collect(_, let t) = o, t <= 0 || t > 200 { fail("objectives", "Collect target out of range") }
        }
        // Switch/shutter связи: у каждой группы есть switch и shutters, switch не под собственной створкой.
        for link in level.shutterSwitchLinks {
            if link.switches.isEmpty || link.shutters.isEmpty { fail("switch", "Group \(link.group) incomplete") }
            for s in link.switches {
                if floors[s]?.type != "switch" || floors[s]?.group != link.group { fail("switch", "Switch \(s) missing for group \(link.group)") }
                if blockers[s] != nil { fail("switch", "Switch \(s) is blocked") }
            }
            for sh in link.shutters where blockers[sh]?.type != "shutter" || blockers[sh]?.group != link.group {
                fail("switch", "Shutter \(sh) missing for group \(link.group)")
            }
        }
        for b in level.blockers where b.type == "shutter" {
            if !level.shutterSwitchLinks.contains(where: { $0.group == b.group }) { fail("switch", "Shutter without switch at \(b.coord)") }
        }
        if !isAcyclic(level) { fail("switch", "Cyclic shutter dependency") }

        // Стартовое поле без готовых matches и хотя бы с одним legal action.
        let state = LevelFactory.initialState(for: level)
        if MatchResolver.hasAnyMatch(state.board) { fail("board", "Initial board contains a ready match") }
        if !GameEngine.hasLegalAction(state) { fail("board", "Initial board has no legal action") }
        return issues
    }

    /// Switch группы G не может находиться в «кармане», который открывают только створки G.
    /// Карман — связная компонента свободных клеток после удаления всех shutters; если switch
    /// лежит в компоненте, все соседи-входы которой — shutters своей же группы, зависимость циклична.
    static func isAcyclic(_ level: LevelDefinition) -> Bool {
        var deps: [Int: Set<Int>] = [:]
        let shutterGroup = Dictionary(level.blockers.filter { $0.type == "shutter" }.map { ($0.coord, $0.group ?? 0) },
                                      uniquingKeysWith: { a, _ in a })
        for link in level.shutterSwitchLinks {
            for s in link.switches {
                // Клетки switch, окружённые исключительно shutters, зависят от их групп.
                var neighborsGroups = Set<Int>()
                var free = false
                for d in Direction.allCases {
                    let nb = s.offset(d)
                    guard level.maskContains(nb) else { continue }
                    if let g = shutterGroup[nb] { neighborsGroups.insert(g) } else { free = true }
                }
                if !free { deps[link.group, default: []].formUnion(neighborsGroups) }
            }
        }
        // DFS на циклы.
        var state: [Int: Int] = [:]
        func visit(_ g: Int) -> Bool {
            if state[g] == 1 { return false }
            if state[g] == 2 { return true }
            state[g] = 1
            for d in deps[g] ?? [] where !visit(d) { return false }
            state[g] = 2
            return true
        }
        for g in deps.keys where !visit(g) { return false }
        return true
    }

    /// Воспроизводит solutionTrace Domain-движком и сверяет hash после каждого settled action.
    public static func replay(_ level: LevelDefinition) -> ReplayReport {
        var state = LevelFactory.initialState(for: level)
        for (i, step) in level.solutionTrace.enumerated() {
            guard let kind = step.gameAction else {
                return ReplayReport(ok: false, failureIndex: i, failure: "Unknown action", finalState: state,
                                    stars: nil, turnsUsed: state.turnsUsed, movesUsed: state.movesUsed)
            }
            do {
                let r = try GameEngine.apply(GameAction(id: "replay-\(i)", kind: kind), to: state, recordSteps: false)
                state = r.state
                let h = StateHasher.hash(state)
                if h != step.hash {
                    return ReplayReport(ok: false, failureIndex: i, failure: "Hash mismatch \(h) != \(step.hash)",
                                        finalState: state, stars: nil, turnsUsed: state.turnsUsed, movesUsed: state.movesUsed)
                }
            } catch {
                return ReplayReport(ok: false, failureIndex: i, failure: "\(error)", finalState: state,
                                    stars: nil, turnsUsed: state.turnsUsed, movesUsed: state.movesUsed)
            }
        }
        let won = state.status == .won
        return ReplayReport(ok: won, failureIndex: won ? nil : level.solutionTrace.count,
                            failure: won ? nil : "Trace does not complete objectives", finalState: state,
                            stars: won ? WinPolicy.stars(initialMoves: state.initialMoves, movesLeft: state.movesLeft) : nil,
                            turnsUsed: state.turnsUsed, movesUsed: state.movesUsed)
    }

    /// Геометрический минимум clockwise Turn: каждый ключ извлекается только при gravity == direction
    /// одного из портов; от q=0 до направления d нужно d.rawValue поворотов.
    public static func geometricMinimumTurns(_ level: LevelDefinition) -> Int {
        guard !level.initialKeyIDs.isEmpty else { return 0 }
        var result = 0
        for id in level.initialKeyIDs {
            let turns = level.exitPorts.filter { $0.accepts(keyID: id) }.map { $0.direction.clockwiseTurnsFromRest }
            result = max(result, turns.min() ?? 0)
        }
        return result
    }
}

extension ObjectiveDef {
    var collectColorKey: String? {
        if case .collect(let c, _) = self { return c.letter }
        return nil
    }
}
