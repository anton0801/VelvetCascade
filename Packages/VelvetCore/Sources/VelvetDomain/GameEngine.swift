// GameEngine.swift — авторитетный порядок обработки хода (Swap / Rotate), wave-resolver,
// Curtain Sweep, гравитация, извлечение ключей, refill, deadlock-shuffle, Win/Fail.
//
// Порядок (спецификация, «Порядок обработки хода»):
// 1. Проверить state, revision, ActionID и legality (исходное состояние не мутируется — это и есть snapshot).
// 2. Списать 1 move; Rotate: сбросить charge, q+1; Swap: обменять occupants.
// 3. Извлечь eligible keys. Rotate: построить Sweep hits; Swap: matches или combo.
// 4. Wave: groups/activation queue → объединение hits → overlay/blocker/floor damage → objectives
//    → removals → new specials → switches/shutters → charge.
// 5. gravity → извлечение ключей → refill → scan; повторять до stable.
// 6. Win перед NoMoves; moves 0 без целей — Fail; иначе проверка deadlock.

public enum GameEngine {
    public static var maxWavesPerAction = 100
    public static let maxShuffleCandidates = 100

    // MARK: - Public API

    /// Применяет действие к копии состояния. При ошибке исходное состояние не меняется (rollback).
    public static func apply(_ action: GameAction, to state: GameState, recordSteps: Bool = true) throws -> ActionResult {
        guard state.status == .playing else { throw EngineError.notPlaying }
        if state.recentActionIDs.contains(action.id) { throw EngineError.duplicateAction }
        if let rev = action.expectedRevision, rev != state.revision { throw EngineError.staleRevision }

        var r = Resolver(state: state, record: recordSteps)
        switch action.kind {
        case .swap(let from, let to):
            if let reason = swapRejection(state, from: from, to: to) { throw EngineError.invalidSwap(reason) }
            try r.performSwap(from: from, to: to)
        case .rotate:
            guard state.isTurnAvailable else { throw EngineError.turnUnavailable }
            try r.performRotate()
        }
        r.s.recentActionIDs.append(action.id)
        if r.s.recentActionIDs.count > 32 { r.s.recentActionIDs.removeFirst(r.s.recentActionIDs.count - 32) }
        let outcome = try r.finish()
        return ActionResult(state: r.s, steps: r.steps, outcome: outcome, wavesResolved: r.waves,
                            chargeGained: r.chargeGainedThisAction, shuffled: r.didShuffle,
                            turnSuggested: r.didSuggestTurn)
    }

    /// nil — swap допустим; иначе причина отказа. Invalid swap не тратит ход/charge/PRNG.
    public static func swapRejection(_ state: GameState, from: Coord, to: Coord) -> String? {
        let b = state.board
        guard b.inBounds(from), b.inBounds(to) else { return "Out of bounds" }
        guard from.isOrthogonalNeighbor(of: to) else { return "Not adjacent" }
        let a = b[from], c = b[to]
        guard a.playable, c.playable else { return "Not a stage cell" }
        guard a.isSwappable, c.isSwappable else {
            if a.occupant?.kind.isKey == true || c.occupant?.kind.isKey == true { return "Keys can't be moved by hand" }
            if a.overlay != nil || c.overlay != nil { return "Pinned pieces can't move" }
            return "This piece can't move"
        }
        if a.occupant!.kind.isSpecial || c.occupant!.kind.isSpecial { return nil }
        let colors = MatchResolver.colorGrid(b)
        if MatchResolver.swapCreatesMatch(colors, n: b.n, b.index(from), b.index(to)) { return nil }
        return "No match"
    }

    public static func isValidSwap(_ state: GameState, from: Coord, to: Coord) -> Bool {
        swapRejection(state, from: from, to: to) == nil
    }

    /// Все допустимые swaps в row-major порядке (каждая пара один раз: вправо и вниз).
    public static func validSwaps(_ state: GameState) -> [(from: Coord, to: Coord)] {
        validSwaps(board: state.board)
    }

    public static func validSwaps(board b: Board) -> [(from: Coord, to: Coord)] {
        let n = b.n
        let colors = MatchResolver.colorGrid(b)
        var result: [(Coord, Coord)] = []
        for i in 0..<(n * n) {
            guard b.cells[i].isSwappable else { continue }
            let x = i % n, y = i / n
            let aSpecial = b.cells[i].occupant!.kind.isSpecial
            for j in [x + 1 < n ? i + 1 : -1, y + 1 < n ? i + n : -1] where j >= 0 {
                guard b.cells[j].isSwappable else { continue }
                if aSpecial || b.cells[j].occupant!.kind.isSpecial
                    || MatchResolver.swapCreatesMatch(colors, n: n, i, j) {
                    result.append((b.coord(i), b.coord(j)))
                }
            }
        }
        return result
    }

    static func hasValidSwap(board b: Board) -> Bool {
        let n = b.n
        let colors = MatchResolver.colorGrid(b)
        for i in 0..<(n * n) {
            guard b.cells[i].isSwappable else { continue }
            let x = i % n, y = i / n
            let aSpecial = b.cells[i].occupant!.kind.isSpecial
            for j in [x + 1 < n ? i + 1 : -1, y + 1 < n ? i + n : -1] where j >= 0 {
                guard b.cells[j].isSwappable else { continue }
                if aSpecial || b.cells[j].occupant!.kind.isSpecial
                    || MatchResolver.swapCreatesMatch(colors, n: n, i, j) {
                    return true
                }
            }
        }
        return false
    }

    /// Legal action — valid swap или доступный Turn.
    public static func hasLegalAction(_ state: GameState) -> Bool {
        state.isTurnAvailable || hasValidSwap(board: state.board)
    }

    public static func stars(initialMoves: Int, movesLeft: Int) -> Int {
        WinPolicy.stars(initialMoves: initialMoves, movesLeft: movesLeft)
    }
}

// MARK: - Turn preview (бесплатный, без RNG и мутаций)

public struct TurnPreview: Hashable, Sendable {
    public var nextQ: Int
    public var nextGravity: Direction
    /// Первичные клетки Sweep (последняя клетка каждого сегмента новой гравитации).
    public var frontier: [Coord]
    /// Frontier-клетки, где стоит ключ: ключ не повреждается.
    public var frontierKeys: [Coord]
    /// Порты, которые станут активными после поворота.
    public var activePorts: [ExitPort]
    /// Ключи, уже стоящие на порту, который станет активным, — будут извлечены сразу.
    public var immediateKeyExtractions: [Coord]
}

extension GameEngine {
    public static func previewTurn(_ state: GameState) -> TurnPreview {
        let nq = (state.q + 1) % 4
        let g = Direction.gravity(forOrientation: nq)
        let ports = state.exitPorts.filter { $0.direction == g }
        let b = state.board
        var immediate: [Coord] = []
        for p in ports {
            if let id = b[p.coord].occupant?.kind.keyID, p.accepts(keyID: id) { immediate.append(p.coord) }
        }
        let frontier = b.sweepFrontier(along: g).map { b.coord($0) }
        let keys = frontier.filter { b[$0].occupant?.kind.isKey == true }
        return TurnPreview(nextQ: nq, nextGravity: g, frontier: frontier.sorted(), frontierKeys: keys,
                           activePorts: ports, immediateKeyExtractions: immediate)
    }
}

// MARK: - Win / Stars

public enum WinPolicy {
    /// 1 за Win; 2 если remaining ≥ ceil(initial×0.15); 3 если remaining ≥ ceil(initial×0.30).
    public static func stars(initialMoves: Int, movesLeft: Int) -> Int {
        let two = (initialMoves * 15 + 99) / 100
        let three = (initialMoves * 30 + 99) / 100
        if movesLeft >= three { return 3 }
        if movesLeft >= two { return 2 }
        return 1
    }
}

// MARK: - Resolver

struct Resolver {
    var s: GameState
    let record: Bool
    var steps: [ResolutionStep] = []
    var waves = 0
    var chargeCap = ChargePolicy.perSwapCap
    var chargeGainedThisAction = 0
    var didShuffle = false
    var didSuggestTurn = false

    init(state: GameState, record: Bool) {
        self.s = state
        self.record = record
    }

    mutating func push(_ e: GameEvent) {
        guard record else { return }
        steps.append(ResolutionStep(event: e, board: s.board, q: s.q, charge: s.charge, movesLeft: s.movesLeft,
                                    collected: s.collected, extractedKeyIDs: s.extractedKeyIDs))
    }

    // MARK: Effects

    enum Effect {
        case line(Axis)
        case burst(Int)
        case colorClear(GemColor?)
        case lineLine
        case burstBurst
        case lineBurst
        case prismWithLine(GemColor)
        case prismWithBurst(GemColor)
        case prismPrism

        var order: Int {
            switch self {
            case .line: return 0
            case .burst: return 1
            case .colorClear: return 2
            case .lineLine: return 3
            case .burstBurst: return 4
            case .lineBurst: return 5
            case .prismWithLine: return 6
            case .prismWithBurst: return 7
            case .prismPrism: return 8
            }
        }
    }

    struct Activation {
        var cell: Int
        var effect: Effect
        /// ID special, чья это собственная активация (один раз за wave).
        var ownerID: Int?
    }

    static func effect(of kind: OccupantKind) -> Effect? {
        switch kind {
        case .lineSpark(_, let axis): return .line(axis)
        case .stageBurst: return .burst(1)
        case .prism: return .colorClear(nil)
        case .gem, .key: return nil
        }
    }

    func lineCells(_ cell: Int, _ axis: Axis) -> [Int] {
        let b = s.board, n = b.n
        let x = cell % n, y = cell / n
        var r: [Int] = []
        r.reserveCapacity(n)
        for t in 0..<n {
            let i = axis == .horizontal ? y * n + t : t * n + x
            if b.cells[i].playable { r.append(i) }
        }
        return r
    }

    func areaCells(_ cell: Int, radius: Int) -> [Int] {
        let b = s.board, n = b.n
        let x = cell % n, y = cell / n
        var r: [Int] = []
        for yy in max(0, y - radius)...min(n - 1, y + radius) {
            for xx in max(0, x - radius)...min(n - 1, x + radius) {
                let i = yy * n + xx
                if b.cells[i].playable { r.append(i) }
            }
        }
        return r
    }

    /// Самый частый baseColor на поле; tie: Heart, Diamond, Clover, Bell, Star.
    func mostFrequentColor() -> GemColor? {
        var counts = [Int](repeating: 0, count: 5)
        for c in s.board.cells {
            if c.playable, c.blocker == nil, let col = c.occupant?.kind.baseColor { counts[col.rawValue] += 1 }
        }
        var best = -1, bestCount = 0
        for k in 0..<5 where counts[k] > bestCount { best = k; bestCount = counts[k] }
        return best >= 0 ? GemColor(rawValue: best) : nil
    }

    func cellsOfColor(_ color: GemColor) -> [Int] {
        var r: [Int] = []
        for (i, c) in s.board.cells.enumerated() where c.playable && c.blocker == nil {
            if c.occupant?.kind.baseColor == color { r.append(i) }
        }
        return r
    }

    func effectCells(_ act: Activation) -> (cells: [Int], visuals: [EffectVisual]) {
        let b = s.board
        let origin = b.coord(act.cell)
        switch act.effect {
        case .line(let axis):
            return (lineCells(act.cell, axis), [.line(origin: origin, axis: axis)])
        case .burst(let radius):
            return (areaCells(act.cell, radius: radius), [.burst(center: origin, radius: radius)])
        case .colorClear(let explicit):
            guard let color = explicit ?? mostFrequentColor() else { return ([act.cell], []) }
            let targets = cellsOfColor(color)
            return (targets + [act.cell], [.colorClear(origin: origin, color: color, targets: targets.map { b.coord($0) })])
        case .lineLine:
            return (lineCells(act.cell, .horizontal) + lineCells(act.cell, .vertical),
                    [.line(origin: origin, axis: .horizontal), .line(origin: origin, axis: .vertical)])
        case .burstBurst:
            return (areaCells(act.cell, radius: 2), [.burst(center: origin, radius: 2)])
        case .lineBurst:
            var cells: [Int] = []
            let n = b.n
            let x = act.cell % n, y = act.cell / n
            for d in -1...1 {
                if y + d >= 0 && y + d < n { cells += lineCells((y + d) * n + x, .horizontal) }
                if x + d >= 0 && x + d < n { cells += lineCells(y * n + x + d, .vertical) }
            }
            return (cells, [.band(center: origin)])
        case .prismWithLine(let color), .prismWithBurst(let color):
            let isLine: Bool
            if case .prismWithLine = act.effect { isLine = true } else { isLine = false }
            let sources = cellsOfColor(color)
            var cells: [Int] = [act.cell]
            var visuals: [EffectVisual] = [.colorClear(origin: origin, color: color, targets: sources.map { b.coord($0) })]
            var k = 0
            for src in sources {
                cells.append(src)
                let cell = b.cells[src]
                // Источник эффекта — только подвижный обычный gem; pinned получает лишь hit по overlay,
                // цветной special активируется своей очередью.
                guard cell.overlay == nil, cell.occupant?.kind.isOrdinaryGem == true else { continue }
                if isLine {
                    let axis: Axis = k % 2 == 0 ? .horizontal : .vertical
                    cells += lineCells(src, axis)
                    visuals.append(.line(origin: b.coord(src), axis: axis))
                } else {
                    cells += areaCells(src, radius: 1)
                    visuals.append(.burst(center: b.coord(src), radius: 1))
                }
                k += 1
            }
            return (cells, visuals)
        case .prismPrism:
            return (b.cells.indices.filter { b.cells[$0].playable }, [.allCells(origin: origin)])
        }
    }

    // MARK: Wave

    mutating func runWave(groups: [MatchGroupInfo], sweep: [Int], forced: [Activation],
                          consumed: [Int], preferredAnchors: [Int]) {
        let n = s.board.n
        let count = n * n
        var hit = [Bool](repeating: false, count: count)
        var activated = Set<Int>()
        var ev = WaveEvent(index: waves)

        // Match hits; соседние crates получают damage от ортогонально соседнего match.
        for g in groups {
            for c in g.cells {
                hit[c] = true
                let x = c % n, y = c / n
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let xx = x + dx, yy = y + dy
                    guard xx >= 0, yy >= 0, xx < n, yy < n else { continue }
                    let j = yy * n + xx
                    if case .crate? = s.board.cells[j].blocker { hit[j] = true }
                }
            }
            if record {
                ev.groups.append(MatchedGroup(color: g.color, cells: g.cells.map { s.board.coord($0) },
                                              chargeGain: ChargePolicy.gain(forGroupSize: g.size)))
            }
        }
        for f in sweep { hit[f] = true }
        if record { ev.sweepCells = sweep.map { s.board.coord($0) } }

        // Планы новых specials: anchor = destination, затем source, затем минимальная (y, x) подходящая клетка.
        struct Plan { var cell: Int; var kind: SpecialKind; var color: GemColor; var protect: Bool }
        var plans: [Plan] = []
        for g in groups {
            guard let sp = g.special else { continue }
            let suitable = g.cells.filter { s.board.cells[$0].overlay == nil && s.board.cells[$0].blocker == nil }
            var anchor: Int?
            for p in preferredAnchors where suitable.contains(p) { anchor = p; break }
            if anchor == nil { anchor = suitable.min() }
            guard let a = anchor else { continue }
            let isPlainGem = s.board.cells[a].occupant?.kind.isOrdinaryGem == true
            // LineSpark/Burst: anchor gem превращается в special и сохраняет свою единицу цвета.
            // Prism: anchor gem поглощается (удаляется и засчитывается один раз), Prism не имеет цвета.
            let protect = isPlainGem && sp != .prism
            plans.append(Plan(cell: a, kind: sp, color: g.color, protect: protect))
        }
        let protected = Set(plans.filter { $0.protect }.map { $0.cell })

        // Расходуемые specials combo: hit без собственной активации.
        for c in consumed {
            hit[c] = true
            if let id = s.board.cells[c].occupant?.id { activated.insert(id) }
        }

        // Очередь активаций: row-major, затем фиксированный enum эффекта.
        var queue = forced
        for i in 0..<count where hit[i] {
            let cell = s.board.cells[i]
            guard cell.overlay == nil, let occ = cell.occupant, occ.kind.isSpecial, !activated.contains(occ.id),
                  let eff = Resolver.effect(of: occ.kind) else { continue }
            if queue.contains(where: { $0.ownerID == occ.id }) { continue }
            queue.append(Activation(cell: i, effect: eff, ownerID: occ.id))
        }
        queue.sort { ($0.cell, $0.effect.order) < ($1.cell, $1.effect.order) }

        var qi = 0
        while qi < queue.count {
            let act = queue[qi]
            qi += 1
            if let owner = act.ownerID {
                if activated.contains(owner) { continue }
                activated.insert(owner)
            }
            hit[act.cell] = true
            let (cells, visuals) = effectCells(act)
            if record { ev.effects += visuals }
            var discovered: [Int] = []
            for c in cells {
                let was = hit[c]
                hit[c] = true
                if was { continue }
                let cell = s.board.cells[c]
                if cell.overlay == nil, let occ = cell.occupant, occ.kind.isSpecial, !activated.contains(occ.id) {
                    discovered.append(c)
                }
            }
            for c in discovered.sorted() {
                let occ = s.board.cells[c].occupant!
                if let eff = Resolver.effect(of: occ.kind) {
                    queue.append(Activation(cell: c, effect: eff, ownerID: occ.id))
                }
            }
        }

        // Применение hits: blocker → overlay → occupant/floor. Не более 1 damage на клетку за wave.
        var switchGroups: [Int] = []
        for i in 0..<count where hit[i] {
            var cell = s.board.cells[i]
            guard cell.playable else { continue }
            let c = s.board.coord(i)
            if record { ev.hitCells.append(c) }
            if let blocker = cell.blocker {
                if case .crate(let hp) = blocker {
                    let nh = hp - 1
                    cell.blocker = nh > 0 ? .crate(hp: nh) : nil
                    if record { ev.damaged.append(DamageEvent(at: c, layer: .crate, remainingHP: max(0, nh))) }
                    s.board.cells[i] = cell
                }
                continue
            }
            if let overlay = cell.overlay {
                switch overlay {
                case .ice(let hp):
                    cell.overlay = hp > 1 ? .ice(hp: hp - 1) : nil
                    if record { ev.damaged.append(DamageEvent(at: c, layer: .ice, remainingHP: hp - 1)) }
                case .chain(let hp):
                    cell.overlay = hp > 1 ? .chain(hp: hp - 1) : nil
                    if record { ev.damaged.append(DamageEvent(at: c, layer: .chain, remainingHP: hp - 1)) }
                }
                s.board.cells[i] = cell
                continue
            }
            guard let occ = cell.occupant, !occ.kind.isKey, !protected.contains(i) else { continue }
            cell.occupant = nil
            if record { ev.removed.append(RemovedPiece(occupant: occ, at: c)) }
            if let col = occ.kind.baseColor { s.collected[col.rawValue] += 1 }
            switch cell.floor {
            case .plate(let hp)?:
                cell.floor = hp > 1 ? .plate(hp: hp - 1) : nil
                if record { ev.damaged.append(DamageEvent(at: c, layer: .plate, remainingHP: hp - 1)) }
            case .switchPlate(let group, let active)?:
                if !active {
                    cell.floor = .switchPlate(group: group, active: true)
                    switchGroups.append(group)
                    if record { ev.switchesActivated.append(c) }
                }
            case nil:
                break
            }
            s.board.cells[i] = cell
        }

        // Новые specials появляются после удалений и не активируются самим фактом рождения.
        for plan in plans {
            var cell = s.board.cells[plan.cell]
            guard cell.playable, cell.blocker == nil, cell.overlay == nil else { continue }
            if plan.protect {
                guard cell.occupant?.kind.isOrdinaryGem == true else { continue }
            } else {
                guard cell.occupant == nil else { continue }
            }
            let kind: OccupantKind
            switch plan.kind {
            case .lineSpark(let axis): kind = .lineSpark(plan.color, axis)
            case .stageBurst: kind = .stageBurst(plan.color)
            case .prism: kind = .prism
            }
            let occ = Occupant(id: s.nextOccupantID, kind: kind)
            s.nextOccupantID += 1
            cell.occupant = occ
            s.board.cells[plan.cell] = cell
            s.specialsCreated += 1
            if record { ev.created.append(RemovedPiece(occupant: occ, at: s.board.coord(plan.cell))) }
        }

        // Switch → постоянное открытие своих shutters.
        for group in switchGroups {
            for link in s.shutterLinks where link.group == group {
                for sc in link.shutters where s.board.inBounds(sc) {
                    if case .shutter? = s.board[sc].blocker {
                        s.board[sc].blocker = nil
                        if record { ev.shuttersOpened.append(sc) }
                    }
                }
            }
        }

        // Charge: только match groups; cap на действие; итог ≤ 12.
        let gain = groups.reduce(0) { $0 + ChargePolicy.gain(forGroupSize: $1.size) }
        let allowed = max(0, chargeCap - chargeGainedThisAction)
        let add = min(gain, allowed, GameState.maxCharge - s.charge)
        if add > 0 {
            chargeGainedThisAction += add
            s.charge += add
        }
        ev.chargeGained = max(0, add)
        push(.wave(ev))
    }

    // MARK: Gravity / keys / refill

    mutating func applyGravity() -> [PieceMove] {
        var moves: [PieceMove] = []
        let g = s.gravity
        for seg in s.board.segments(along: g) {
            var occs: [(Occupant, Int)] = []
            for i in seg { if let o = s.board.cells[i].occupant { occs.append((o, i)) } }
            if occs.count == seg.count || occs.isEmpty { continue }
            for i in seg { s.board.cells[i].occupant = nil }
            let start = seg.count - occs.count
            for (k, pair) in occs.enumerated() {
                let to = seg[start + k]
                s.board.cells[to].occupant = pair.0
                if to != pair.1 {
                    moves.append(PieceMove(id: pair.0.id, from: s.board.coord(pair.1), to: s.board.coord(to)))
                }
            }
        }
        return moves
    }

    mutating func extractKeys() -> [KeyExtraction] {
        var result: [KeyExtraction] = []
        let g = s.gravity
        for port in s.exitPorts where port.direction == g {
            guard s.board.inBounds(port.coord) else { continue }
            let i = s.board.index(port.coord)
            guard let occ = s.board.cells[i].occupant, case .key(let keyID) = occ.kind, port.accepts(keyID: keyID) else { continue }
            s.board.cells[i].occupant = nil
            if !s.extractedKeyIDs.contains(keyID) {
                s.extractedKeyIDs.append(keyID)
                s.extractedKeyIDs.sort()
            }
            result.append(KeyExtraction(occupantID: occ.id, keyID: keyID, at: port.coord, direction: g))
        }
        return result
    }

    mutating func refill() -> [PieceSpawn] {
        var spawns: [PieceSpawn] = []
        for seg in s.board.segments(along: s.gravity) {
            var empties: [Int] = []
            for i in seg where s.board.cells[i].occupant == nil { empties.append(i) }
            if empties.isEmpty { continue }
            // Заполнение из upstream-конца: сначала ближайшая к downstream пустая клетка.
            for i in empties.reversed() {
                let color = GemColor(rawValue: s.rng.nextInt(below: 5))!
                let occ = Occupant(id: s.nextOccupantID, kind: .gem(color))
                s.nextOccupantID += 1
                s.board.cells[i].occupant = occ
                spawns.append(PieceSpawn(occupant: occ, at: s.board.coord(i), dropDistance: empties.count))
            }
        }
        return spawns
    }

    /// Гравитация и извлечение ключей до стабилизации, затем refill.
    mutating func settleGravity() {
        while true {
            let mv = applyGravity()
            if !mv.isEmpty { push(.gravity(mv)) }
            let ex = extractKeys()
            if ex.isEmpty { break }
            push(.keysExtracted(ex))
        }
        let sp = refill()
        if !sp.isEmpty { push(.refill(sp)) }
    }

    mutating func resolve(groups first: [MatchGroupInfo], sweep: [Int], forced: [Activation], consumed: [Int],
                          preferredAnchors: [Int]) throws {
        var groups = first
        var sweep = sweep
        var forced = forced
        var consumed = consumed
        var preferred = preferredAnchors
        while true {
            waves += 1
            if waves > GameEngine.maxWavesPerAction { throw EngineError.waveLimitExceeded }
            runWave(groups: groups, sweep: sweep, forced: forced, consumed: consumed, preferredAnchors: preferred)
            settleGravity()
            groups = MatchResolver.findGroups(s.board)
            if groups.isEmpty { break }
            sweep = []
            forced = []
            consumed = []
            preferred = []
        }
    }

    // MARK: Actions

    mutating func performSwap(from: Coord, to: Coord) throws {
        s.movesLeft -= 1
        chargeCap = ChargePolicy.perSwapCap
        let fi = s.board.index(from), ti = s.board.index(to)
        let moved = s.board.cells[fi].occupant!   // фишка, которую игрок ведёт в destination
        let other = s.board.cells[ti].occupant!
        s.board.cells[fi].occupant = other
        s.board.cells[ti].occupant = moved
        push(.swapped(from: from, to: to))

        let ex = extractKeys()
        if !ex.isEmpty { push(.keysExtracted(ex)) }

        var forced: [Activation] = []
        var consumed: [Int] = []
        let mk = moved.kind, ok = other.kind
        if mk.isSpecial && ok.isSpecial {
            let effect: Effect
            switch (mk, ok) {
            case (.lineSpark, .lineSpark): effect = .lineLine
            case (.stageBurst, .stageBurst): effect = .burstBurst
            case (.lineSpark, .stageBurst), (.stageBurst, .lineSpark): effect = .lineBurst
            case (.prism, .prism): effect = .prismPrism
            case (.prism, .lineSpark(let c, _)), (.lineSpark(let c, _), .prism): effect = .prismWithLine(c)
            case (.prism, .stageBurst(let c)), (.stageBurst(let c), .prism): effect = .prismWithBurst(c)
            default: effect = .lineLine
            }
            consumed = [ti, fi]
            forced = [Activation(cell: ti, effect: effect, ownerID: nil)]
        } else if mk.isSpecial {
            forced = [Resolver.swapActivation(special: moved, at: ti, partner: other)]
        } else if ok.isSpecial {
            forced = [Resolver.swapActivation(special: other, at: fi, partner: moved)]
        }
        let groups = MatchResolver.findGroups(s.board)
        try resolve(groups: groups, sweep: [], forced: forced, consumed: consumed, preferredAnchors: [ti, fi])
    }

    static func swapActivation(special: Occupant, at cell: Int, partner: Occupant) -> Activation {
        switch special.kind {
        case .prism:
            return Activation(cell: cell, effect: .colorClear(partner.kind.baseColor), ownerID: special.id)
        default:
            return Activation(cell: cell, effect: effect(of: special.kind)!, ownerID: special.id)
        }
    }

    mutating func performRotate() throws {
        s.movesLeft -= 1
        s.charge = 0
        let fromQ = s.q
        s.q = (s.q + 1) % 4
        s.turnsUsed += 1
        chargeCap = ChargePolicy.perTurnCap
        push(.rotated(fromQ: fromQ, toQ: s.q))

        // Сначала извлечь ключи, уже стоящие на активных портах, затем Curtain Sweep.
        let ex = extractKeys()
        if !ex.isEmpty { push(.keysExtracted(ex)) }
        let frontier = s.board.sweepFrontier(along: s.gravity)
        try resolve(groups: [], sweep: frontier, forced: [], consumed: [], preferredAnchors: [])
    }

    // MARK: Finish: Win → Fail → deadlock

    mutating func finish() throws -> ActionOutcome {
        s.revision += 1
        if s.allObjectivesComplete {
            s.status = .won
            return .won(stars: WinPolicy.stars(initialMoves: s.initialMoves, movesLeft: s.movesLeft))
        }
        if s.movesLeft <= 0 {
            s.status = .failed
            return .failed
        }
        if !GameEngine.hasValidSwap(board: s.board) {
            if s.isTurnAvailable {
                didSuggestTurn = true
                push(.turnSuggested)
            } else {
                try shuffle()
            }
        }
        return .continuePlaying
    }

    /// Бесплатно переставляет только подвижные обычные gems; сохраняет mask, keys, specials, floors,
    /// overlays, objectives, q, moves и charge. Максимум 100 детерминированных кандидатов.
    mutating func shuffle() throws {
        var movable: [Int] = []
        for (i, c) in s.board.cells.enumerated() where c.isFlow && c.occupant?.kind.isOrdinaryGem == true {
            movable.append(i)
        }
        let original = movable.map { s.board.cells[$0].occupant! }
        var rng = s.rng
        for _ in 0..<GameEngine.maxShuffleCandidates {
            var perm = original
            rng.shuffle(&perm)
            var b = s.board
            for (k, idx) in movable.enumerated() { b.cells[idx].occupant = perm[k] }
            if !MatchResolver.hasAnyMatch(b) && GameEngine.hasValidSwap(board: b) {
                var moves: [PieceMove] = []
                let fromByID = Dictionary(uniqueKeysWithValues: zip(original.map { $0.id }, movable))
                for (k, idx) in movable.enumerated() where fromByID[perm[k].id] != idx {
                    moves.append(PieceMove(id: perm[k].id, from: b.coord(fromByID[perm[k].id]!), to: b.coord(idx)))
                }
                s.board = b
                s.rng = rng
                s.shufflesPerformed += 1
                didShuffle = true
                push(.shuffled(moves))
                return
            }
        }
        throw EngineError.stageDataError("No deadlock shuffle candidate within \(GameEngine.maxShuffleCandidates)")
    }
}
