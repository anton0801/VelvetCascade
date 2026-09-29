// Layout.swift — генерация конкретной раскладки уровня по brief (координаты, слои, ключи, порты).
//
// Раскладка строится детерминированно из (levelID, attempt): одинаковый attempt даёт одинаковый уровень.
// Солвер затем ищет реальное решение этим же Domain-движком; неудачные попытки отбрасываются.

import Foundation
import VelvetDomain

struct LayoutOptions {
    var movesOverride: Int?
    var targetScale: Double = 1.0
    /// Масштаб количества препятствий/пластин, если форма физически не вмещает brief.
    var countScale: Double = 1.0
    /// Дополнительная дистанция ключа до выхода (рычаг сложности для key-уровней).
    var distanceBoost: Int = 0
    /// Смещение пластин к краям поля (рычаг сложности для уровней с пластинами).
    var plateSpread: Int = 0
    /// Доля пластин HP1, превращённых в HP2 (рычаг сложности; меняет цель V a/b и логируется).
    var plateHardening: Double = 0
}

struct Layout {
    let brief: Brief
    let n: Int
    let mask: [Bool]
    var rng: LevelRNG

    var blockers: [Coord: BlockerPlacement] = [:]
    var overlays: [Coord: OverlayPlacement] = [:]
    var floors: [Coord: FloorPlacement] = [:]
    var keys: [Coord: Int] = [:]
    var ports: [ExitPort] = []
    var links: [ShutterSwitchLink] = []
    /// Клетки пути ключей и порты: без случайных blockers/overlays.
    var reserved: Set<Coord> = []
    var keyPaths: [[Coord]] = []
    var notes: [String] = []

    var options = LayoutOptions()

    func scaled(_ v: Int) -> Int {
        guard v > 0 else { return 0 }
        return max(1, Int((Double(v) * options.countScale).rounded()))
    }

    init(brief: Brief, attempt: Int) {
        self.brief = brief
        self.n = ShapeCatalog.size(of: brief.shape)
        var m: [Bool] = []
        for y in 0..<n { for x in 0..<n { m.append(ShapeCatalog.contains(shape: brief.shape, Coord(x, y))) } }
        self.mask = m
        let seed = UInt64(brief.id) &* 1_000_003 &+ UInt64(attempt) &* 7919 &+ 0x5EED
        self.rng = LevelRNG(seed: seed)
    }

    // MARK: Helpers

    func inMask(_ c: Coord) -> Bool {
        c.x >= 0 && c.y >= 0 && c.x < n && c.y < n && mask[c.y * n + c.x]
    }

    func isOpen(_ c: Coord) -> Bool { inMask(c) && blockers[c] == nil }

    var maskCells: [Coord] {
        var r: [Coord] = []
        for y in 0..<n { for x in 0..<n where mask[y * n + x] { r.append(Coord(x, y)) } }
        return r
    }

    func mirror(_ c: Coord) -> Coord { Coord(n - 1 - c.x, c.y) }

    mutating func random() -> Double { Double(rng.nextInt(below: 1_000_000)) / 1_000_000.0 }

    var focus: String { brief.designFocus.lowercased() }

    /// Клетка входит хотя бы в одно окно из 3 подряд открытых клеток (ряд или колонка).
    func hasPotentialRun(_ c: Coord, permanentOnly: Bool = false) -> Bool {
        func open(_ p: Coord) -> Bool {
            guard inMask(p) else { return false }
            guard let b = blockers[p] else { return true }
            return permanentOnly && b.type != "wall"
        }
        for axis in 0..<2 {
            for off in -2...0 {
                var ok = true
                for k in 0..<3 {
                    let p = axis == 0 ? Coord(c.x + off + k, c.y) : Coord(c.x, c.y + off + k)
                    if !open(p) { ok = false; break }
                }
                if ok { return true }
            }
        }
        return false
    }

    func orthNeighbors(_ c: Coord) -> [Coord] {
        Direction.allCases.map { c.offset($0) }.filter { inMask($0) }
    }

    /// Интерьерная клетка: все 4 соседа в mask.
    func isInterior(_ c: Coord) -> Bool { orthNeighbors(c).count == 4 }

    // MARK: Keys & exits

    var preferredDistance: Int {
        let slot = (brief.id - 1) % 20 + 1
        if focus.contains("корот") || focus.contains("близк") || focus.contains("передышк") { return 1 }
        if [11, 17].contains(slot) { return max(1, 1 + options.distanceBoost) }
        if brief.worldID <= 3 { return max(1, 2 + options.distanceBoost) }
        return max(1, (slot >= 15 ? 3 : 2) + options.distanceBoost)
    }

    mutating func placeKeys() -> Bool {
        guard !brief.keys.isEmpty else { return true }
        let wantsInner = focus.contains("внутрен") || focus.contains("void")
        let wantsOuterSecond = focus.contains("внешн")
        var usedLines = Set<String>()
        for (i, spec) in brief.keys.enumerated() {
            let d = spec.direction
            let earlier = (0..<d.rawValue).map { Direction.gravity(forOrientation: $0) }
            var best: (port: Coord, key: Coord, path: [Coord], score: Double)?
            for p in maskCells where !inMask(p.offset(d)) {
                if ports.contains(where: { $0.coord == p }) || keys[p] != nil || reserved.contains(p) { continue }
                // Линия upstream от порта.
                var line: [Coord] = [p]
                var cur = p.offset(d.opposite)
                while inMask(cur) { line.append(cur); cur = cur.offset(d.opposite) }
                guard line.count >= 3 else { continue }
                let lineKey = d.isVertical ? "c\(p.x)" : "r\(p.y)"
                let maxDist = min(4 + options.distanceBoost, line.count - 1)
                for dist in 1...maxDist {
                    let k = line[dist]
                    let path = Array(line[0..<dist])
                    if keys[k] != nil || reserved.contains(k) { continue }
                    if path.contains(where: { reserved.contains($0) || keys[$0] != nil }) { continue }
                    var score = 0.0
                    for g in earlier where !inMask(k.offset(g)) { score += 3 }
                    score -= Double(abs(dist - preferredDistance)) * 1.2
                    let inner = p.offset(d).x >= 0 && p.offset(d).y >= 0 && p.offset(d).x < n && p.offset(d).y < n
                    if wantsInner && i == 0 && inner { score += 6 }
                    if wantsOuterSecond && i >= 1 && !inner { score += 4 }
                    if usedLines.contains(lineKey) { score -= 5 }
                    // Подсказки brief о положении выхода.
                    if focus.contains("верхн") && !d.isVertical { score += Double(n - 1 - p.y) * 0.8 }
                    if focus.contains("правом верхнем") { score += Double(p.x + (n - 1 - p.y)) * 0.6 }
                    if focus.contains("нижн") && !d.isVertical { score += Double(p.y) * 0.6 }
                    // Не прижимать ключ к углу доски (там мало совпадений вокруг).
                    if orthNeighbors(k).count <= 1 { score -= 2 }
                    score += random() * 2.5
                    if best == nil || score > best!.score { best = (p, k, path, score) }
                }
            }
            guard let b = best else { return false }
            keys[b.key] = i + 1
            ports.append(ExitPort(x: b.port.x, y: b.port.y, direction: d, keyID: i + 1))
            reserved.insert(b.key)
            reserved.formUnion(b.path)
            keyPaths.append(b.path)
            usedLines.insert(d.isVertical ? "c\(b.port.x)" : "r\(b.port.y)")
        }
        return true
    }

    // MARK: Shutters & switches

    mutating func placeShutters() -> Bool {
        let groups = brief.switchCells
        let total = max(groups, scaled(brief.shutterCells))
        guard total > 0, groups > 0 else { return true }
        var perGroup = Array(repeating: total / groups, count: groups)
        for g in 0..<(total % groups) { perGroup[g] += 1 }
        let chain = focus.contains("→") || focus.contains("цепоч") || focus.contains("последовательн")
            || focus.contains("доступ к третьему") || focus.contains("путь к b")
        var shutterCells: [[Coord]] = Array(repeating: [], count: groups)
        var switches: [Coord?] = Array(repeating: nil, count: groups)

        func canBlock(_ c: Coord) -> Bool {
            inMask(c) && blockers[c] == nil && keys[c] == nil && !ports.contains(where: { $0.coord == c })
        }

        // 1) Цепочка: switch группы g+1 в «кармане», закрытом shutters группы g.
        if chain && groups >= 2 {
            for g in 0..<(groups - 1) {
                var bestPocket: (Coord, [Coord])?
                var bestScore = -Double.infinity
                for c in maskCells where canBlock(c) && !reserved.contains(c) {
                    let nbs = orthNeighbors(c)
                    let free = nbs.filter { canBlock($0) && !reserved.contains($0) }
                    guard free.count == nbs.count, !free.isEmpty, free.count <= perGroup[g] else { continue }
                    let score = Double(-free.count) + random()
                    if score > bestScore { bestScore = score; bestPocket = (c, free) }
                }
                guard let pocket = bestPocket else { return false }
                switches[g + 1] = pocket.0
                reserved.insert(pocket.0)
                for s in pocket.1 {
                    blockers[s] = BlockerPlacement(x: s.x, y: s.y, type: "shutter", group: g)
                    shutterCells[g].append(s)
                }
            }
        }

        // 2) Створки на путях ключей (последние группы сторожат выходы).
        var pathIndex = 0
        for g in (0..<groups).reversed() where shutterCells[g].count < perGroup[g] {
            guard pathIndex < keyPaths.count else { break }
            let path = keyPaths[pathIndex].filter { c in canBlock(c) && !ports.contains(where: { $0.coord == c }) }
            pathIndex += 1
            for c in path.reversed() where shutterCells[g].count < perGroup[g] {
                blockers[c] = BlockerPlacement(x: c.x, y: c.y, type: "shutter", group: g)
                shutterCells[g].append(c)
            }
        }

        // 3) Остаток — компактными «дверями»: рост от уже поставленных клеток группы.
        for g in 0..<groups {
            var guardCount = 0
            while shutterCells[g].count < perGroup[g] {
                guardCount += 1
                if guardCount > 400 { return false }
                var cands: [Coord] = []
                for c in shutterCells[g] {
                    for nb in orthNeighbors(c) where canBlock(nb) && !reserved.contains(nb) && !cands.contains(nb) {
                        // Не замуровывать клетки: у соседа должен остаться хотя бы один открытый выход.
                        cands.append(nb)
                    }
                }
                if cands.isEmpty {
                    cands = maskCells.filter { canBlock($0) && !reserved.contains($0) && isInterior($0) }
                    if cands.isEmpty { cands = maskCells.filter { canBlock($0) && !reserved.contains($0) } }
                }
                guard !cands.isEmpty else { return false }
                let c = cands[rng.nextInt(below: cands.count)]
                blockers[c] = BlockerPlacement(x: c.x, y: c.y, type: "shutter", group: g)
                shutterCells[g].append(c)
            }
        }

        // 4) Switch каждой группы в открытой клетке с потенциальным совпадением.
        for g in 0..<groups where switches[g] == nil {
            var best: Coord?
            var bestScore = -Double.infinity
            for c in maskCells where canBlock(c) && !reserved.contains(c) && floors[c] == nil {
                guard hasPotentialRun(c) else { continue }
                let nearOwn = shutterCells[g].map { abs($0.x - c.x) + abs($0.y - c.y) }.min() ?? 4
                if nearOwn <= 1 { continue }
                var score = -Double(abs(nearOwn - 3)) + random() * 2
                if isInterior(c) { score += 1 }
                if switches.contains(where: { $0 != nil && abs($0!.x - c.x) + abs($0!.y - c.y) < 3 }) { score -= 3 }
                if score > bestScore { bestScore = score; best = c }
            }
            guard let s = best else { return false }
            switches[g] = s
            reserved.insert(s)
        }
        for g in 0..<groups {
            let s = switches[g]!
            floors[s] = FloorPlacement(x: s.x, y: s.y, type: "switch", group: g)
            links.append(ShutterSwitchLink(group: g, switches: [s], shutters: shutterCells[g].sorted()))
        }
        return true
    }

    // MARK: Walls / crates / overlays

    mutating func placeSymmetric(count: Int, allowReserved: Bool = false, interiorOnly: Bool = false,
                                 minSpacing: Int = 1, accept: (Layout, Coord) -> Bool, place: (inout Layout, Coord) -> Void) -> Bool {
        var remaining = count
        var tries = 0
        var placedCells: [Coord] = []
        while remaining > 0 && tries < 600 {
            tries += 1
            let snapshot = self
            let cands = maskCells.filter { c in
                (allowReserved || !snapshot.reserved.contains(c)) && accept(snapshot, c) && (!interiorOnly || snapshot.isInterior(c))
                    && !placedCells.contains(where: { abs($0.x - c.x) + abs($0.y - c.y) <= minSpacing - 1 && minSpacing > 1 })
            }
            guard !cands.isEmpty else { break }
            let c = cands[rng.nextInt(below: cands.count)]
            let m = mirror(c)
            if remaining >= 2 && m != c && accept(self, m) && (allowReserved || !reserved.contains(m)) {
                place(&self, c)
                place(&self, m)
                placedCells += [c, m]
                remaining -= 2
            } else if remaining == 1 || m == c {
                place(&self, c)
                placedCells.append(c)
                remaining -= 1
            }
        }
        return remaining == 0
    }

    func freeForBlocker(_ c: Coord) -> Bool {
        inMask(c) && blockers[c] == nil && overlays[c] == nil && keys[c] == nil && floors[c] == nil
            && !ports.contains(where: { $0.coord == c }) && !pathHalo.contains(c)
    }

    /// Клетки, соседние с путями ключей: без ящиков и стен, чтобы фишки на пути можно было собрать.
    var pathHalo: Set<Coord> {
        var h = Set<Coord>()
        for path in keyPaths { for c in path { for nb in orthNeighbors(c) { h.insert(nb) } } }
        for (k, _) in keys { for nb in orthNeighbors(k) { h.insert(nb) } }
        return h
    }

    mutating func placeWalls() -> Bool {
        guard brief.walls > 0 else { return true }
        let accept: (Layout, Coord) -> Bool = { l, c in
            guard l.freeForBlocker(c) else { return false }
            // Стена не должна изолировать соседей.
            return l.orthNeighbors(c).filter { l.blockers[$0] != nil }.count <= 1
        }
        let place: (inout Layout, Coord) -> Void = { l, c in l.blockers[c] = BlockerPlacement(x: c.x, y: c.y, type: "wall") }
        let snapshot = self
        if placeSymmetric(count: brief.walls, interiorOnly: true, minSpacing: 3, accept: accept, place: place) { return true }
        // Узкие формы: ослабить требования (не только внутренние клетки, меньший интервал).
        self = snapshot
        return placeSymmetric(count: brief.walls, interiorOnly: false, minSpacing: 2, accept: accept, place: place)
    }

    mutating func placeCrates() -> Bool {
        let gate = focus.contains("перед правым выходом") || focus.contains("ящики перед")
        var hp1 = scaled(brief.crates1)
        let hp2 = scaled(brief.crates2)
        if gate, let path = keyPaths.first {
            for c in path where hp1 > 0 && freeForBlocker(c) && !ports.contains(where: { $0.coord == c }) {
                blockers[c] = BlockerPlacement(x: c.x, y: c.y, type: "crate", hp: 1)
                hp1 -= 1
            }
        }
        let accept: (Layout, Coord) -> Bool = { l, c in
            guard l.freeForBlocker(c) else { return false }
            let blockedNb = l.orthNeighbors(c).filter { l.blockers[$0] != nil }.count
            return blockedNb <= 1
        }
        guard placeSymmetric(count: hp2, accept: accept, place: { l, c in
            l.blockers[c] = BlockerPlacement(x: c.x, y: c.y, type: "crate", hp: 2)
        }) else { return false }
        return placeSymmetric(count: hp1, accept: accept, place: { l, c in
            l.blockers[c] = BlockerPlacement(x: c.x, y: c.y, type: "crate", hp: 1)
        })
    }

    mutating func placeOverlays() -> Bool {
        let pinPath = focus.contains("между закреплён") || focus.contains("открыть падающий")
        let accept: (Layout, Coord) -> Bool = { l, c in
            l.inMask(c) && l.blockers[c] == nil && l.overlays[c] == nil && l.keys[c] == nil
                && !l.ports.contains(where: { $0.coord == c }) && l.floors[c]?.type != "switch"
                && l.hasPotentialRun(c, permanentOnly: true)
        }
        func put(_ type: String, _ hp: Int) -> (inout Layout, Coord) -> Void {
            { l, c in l.overlays[c] = OverlayPlacement(x: c.x, y: c.y, type: type, hp: hp) }
        }
        var chains = scaled(brief.chains)
        if pinPath, let k = keys.first?.key {
            for nb in orthNeighbors(k) where chains > 0 && accept(self, nb) && !reserved.contains(nb) {
                overlays[nb] = OverlayPlacement(x: nb.x, y: nb.y, type: "chain", hp: 1)
                chains -= 1
            }
        }
        guard placeSymmetric(count: scaled(brief.ice2), accept: accept, place: put("ice", 2)) else { return false }
        guard placeSymmetric(count: scaled(brief.ice1), accept: accept, place: put("ice", 1)) else { return false }
        return placeSymmetric(count: chains, accept: accept, place: put("chain", 1))
    }

    // MARK: Plates

    mutating func placePlates() -> Bool {
        let hp1Base = scaled(brief.platesHP1)
        let hardened = Int((Double(hp1Base) * options.plateHardening).rounded())
        let hp2Count = scaled(brief.platesHP2) + hardened
        let total = hp1Base + scaled(brief.platesHP2)
        guard total > 0 else { return true }
        let candidates = maskCells.filter { c in
            blockers[c] == nil && keys[c] == nil && floors[c] == nil && hasPotentialRun(c, permanentOnly: true)
        }
        guard candidates.count >= total else { return false }
        let cx = Double(n - 1) / 2
        let f = focus
        // Весовая функция по заданию brief.
        func weight(_ c: Coord) -> Double {
            let dx = Double(c.x) - cx, dy = Double(c.y) - cx
            let dCenter = abs(dx) + abs(dy)
            if f.contains("правого края") || f.contains("правому краю") || f.contains("полосой у правого") {
                return Double(c.x) * 3 - abs(dy) * 0.3
            }
            if f.contains("углов") || f.contains("угловых") { return max(abs(dx), abs(dy)) * 2 + dCenter }
            if f.contains("двух соседних краях") || f.contains("соседних краях") {
                return Double(max(c.x, c.y)) * 2
            }
            if f.contains("полос") || f.contains("длинную полосу") { return -abs(dy + 0.5) * 3 - abs(dx) * 0.2 }
            if f.contains("наружн") && f.contains("внутрен") { return abs(dCenter - 3.5) < 1.2 ? 3 : 0 }
            if f.contains("внутренн") || f.contains("у внутреннего") { return -dCenter }
            if f.contains("перемычк") { return -abs(dy - 0.5) * 2 }
            // По умолчанию: центральный прямоугольник / симметричное ядро.
            return -dCenter
        }
        let spread = Double(options.plateSpread)
        func spreadWeight(_ c: Coord) -> Double {
            let dx = Double(c.x) - cx, dy = Double(c.y) - cx
            return weight(c) + spread * (abs(dx) + abs(dy)) * 1.6
        }
        var scored = candidates.map { ($0, spreadWeight($0) + random() * 0.6) }
        scored.sort { $0.1 > $1.1 }
        var chosen: [Coord] = []
        var seen = Set<Coord>()
        for (c, _) in scored where chosen.count < total {
            if seen.contains(c) { continue }
            chosen.append(c)
            seen.insert(c)
            let m = mirror(c)
            if chosen.count < total, m != c, candidates.contains(m), !seen.contains(m) {
                chosen.append(m)
                seen.insert(m)
            }
        }
        guard chosen.count == total else { return false }
        // HP2 — ближе к центру/приоритету, HP1 — вокруг.
        let byCenter = chosen.sorted { spreadWeight($0) > spreadWeight($1) }
        for (i, c) in byCenter.enumerated() {
            let hp = i < hp2Count ? 2 : 1
            floors[c] = FloorPlacement(x: c.x, y: c.y, type: "plate", hp: hp)
        }
        return true
    }

    // MARK: Fill

    mutating func fill() -> [OccupantPlacement]? {
        for _ in 0..<60 {
            var colors = [Int](repeating: -1, count: n * n)
            var occ: [OccupantPlacement] = []
            for y in 0..<n {
                for x in 0..<n {
                    let c = Coord(x, y)
                    guard inMask(c), blockers[c] == nil else { continue }
                    if let k = keys[c] {
                        occ.append(OccupantPlacement(x: x, y: y, type: "key", keyID: k))
                        continue
                    }
                    var banned = Set<Int>()
                    if x >= 2, colors[y * n + x - 1] >= 0, colors[y * n + x - 1] == colors[y * n + x - 2] { banned.insert(colors[y * n + x - 1]) }
                    if y >= 2, colors[(y - 1) * n + x] >= 0, colors[(y - 1) * n + x] == colors[(y - 2) * n + x] { banned.insert(colors[(y - 1) * n + x]) }
                    var col = rng.nextInt(below: 5)
                    while banned.contains(col) { col = rng.nextInt(below: 5) }
                    colors[y * n + x] = col
                    occ.append(OccupantPlacement(x: x, y: y, type: "gem", color: GemColor(rawValue: col)!))
                }
            }
            let def = definition(occupants: occ, moves: brief.moves, targetScale: 1)
            let s = LevelFactory.initialState(for: def)
            if MatchResolver.hasAnyMatch(s.board) { continue }
            let swaps = GameEngine.validSwaps(s)
            if swaps.isEmpty { continue }
            if !openingRequirementSatisfied(s, swaps: swaps) { continue }
            return occ
        }
        return nil
    }

    /// Особые требования учебных уровней к стартовому полю.
    func openingRequirementSatisfied(_ s: GameState, swaps: [(from: Coord, to: Coord)]) -> Bool {
        func specialsFrom(_ sw: (from: Coord, to: Coord)) -> [OccupantKind] {
            guard let r = try? GameEngine.apply(GameAction(id: "probe", kind: .swap(from: sw.from, to: sw.to)), to: s) else { return [] }
            guard let w = r.steps.compactMap({ step -> WaveEvent? in if case .wave(let w) = step.event { return w }; return nil }).first else { return [] }
            return w.created.map { $0.occupant.kind }
        }
        func firstWaveColors(_ sw: (from: Coord, to: Coord)) -> [GemColor] {
            guard let r = try? GameEngine.apply(GameAction(id: "probe", kind: .swap(from: sw.from, to: sw.to)), to: s) else { return [] }
            guard let w = r.steps.compactMap({ step -> WaveEvent? in if case .wave(let w) = step.event { return w }; return nil }).first else { return [] }
            return w.groups.map { $0.color }
        }
        switch brief.id {
        case 1:
            return swaps.contains { firstWaveColors($0).contains(.heart) }
        case 2:
            return swaps.count >= 2 && swaps.contains { firstWaveColors($0).contains(.diamond) }
        case 4:
            return swaps.contains { specialsFrom($0).contains { if case .lineSpark = $0 { return true }; return false } }
        case 7:
            return swaps.contains { specialsFrom($0).contains { if case .stageBurst = $0 { return true }; return false } }
        case 8:
            return swaps.contains { specialsFrom($0).contains(.prism) }
        default:
            return true
        }
    }

    // MARK: Build

    func objectives(targetScale: Double) -> [ObjectiveDef] {
        var o: [ObjectiveDef] = []
        if !brief.keys.isEmpty { o.append(.keys) }
        if brief.hasPlates { o.append(.plates) }
        for (c, t) in brief.collect {
            o.append(.collect(color: c, target: max(3, Int((Double(t) * targetScale).rounded()))))
        }
        return o
    }

    func definition(occupants: [OccupantPlacement], moves: Int, targetScale: Double) -> LevelDefinition {
        let slot = (brief.id - 1) % 20 + 1
        let difficulty = min(10, max(1, brief.worldID + (slot >= 15 ? 2 : (slot >= 8 ? 1 : 0)) - ([11, 17].contains(slot) ? 1 : 0)))
        let seed = (UInt64(brief.id) &* 2_654_435_761 &+ rng.state) & 0x1F_FFFF_FFFF_FFFF
        return LevelDefinition(
            id: brief.id, campaignVersion: 1, worldID: brief.worldID, levelVersion: 1, title: brief.title,
            shape: brief.shape, n: n, mask: ShapeCatalog.maskRows(shape: brief.shape), initialOrientation: 0,
            initialMoves: moves, initialCharge: brief.charge, fiveColorPalette: GemColor.allCases,
            initialOccupants: occupants,
            floors: floors.values.sorted { $0.coord < $1.coord },
            overlays: overlays.values.sorted { $0.coord < $1.coord },
            blockers: blockers.values.sorted { $0.coord < $1.coord },
            exitPorts: ports, shutterSwitchLinks: links.sorted { $0.group < $1.group },
            objectives: objectives(targetScale: targetScale), rngAlgorithmVersion: LevelRNG.algorithmVersion,
            seed: seed, tutorialSteps: Tutorials.steps(for: brief.id), solutionTrace: [],
            authoredDifficulty: difficulty, playtestStatus: "unverified", turnBrief: brief.turnBrief,
            requiredTurns: 0, newMechanic: Tutorials.newMechanic(for: brief.id)?.0,
            newMechanicTopic: Tutorials.newMechanic(for: brief.id)?.1)
    }

    static func generate(brief: Brief, attempt: Int, options: LayoutOptions) -> (LevelDefinition, [String])? {
        guard let (l, occ) = build(brief: brief, attempt: attempt, options: options) else { return nil }
        var def = l.definition(occupants: occ, moves: options.movesOverride ?? brief.moves, targetScale: options.targetScale)
        def.requiredTurns = LevelValidator.geometricMinimumTurns(def)
        return (def, l.notes)
    }

    static func build(brief: Brief, attempt: Int, options: LayoutOptions) -> (Layout, [OccupantPlacement])? {
        var l = Layout(brief: brief, attempt: attempt)
        l.options = options
        guard l.placeKeys() else { return nil }
        guard l.placeShutters() else { return nil }
        guard l.placeWalls() else { return nil }
        guard l.placeCrates() else { return nil }
        guard l.placePlates() else { return nil }
        guard l.placeOverlays() else { return nil }
        guard let occ = l.fill() else { return nil }
        return (l, occ)
    }

    func makeDefinition(_ occ: [OccupantPlacement], moves: Int, targetScale: Double) -> LevelDefinition {
        var def = definition(occupants: occ, moves: moves, targetScale: targetScale)
        def.requiredTurns = LevelValidator.geometricMinimumTurns(def)
        return def
    }
}
