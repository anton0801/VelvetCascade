import XCTest
@testable import VelvetDomain

/// Базовый рисунок без совпадений: color(x,y) = (x + 2y) mod 5.
private let base6 = [
    "HDCBSH",
    "CBSHDC",
    "SHDCBS",
    "DCBSHD",
    "BSHDCB",
    "HDCBSH",
]

final class SwapAndMatchTests: XCTestCase {
    func testBaseBoardHasNoMatches() {
        XCTAssertFalse(MatchResolver.hasAnyMatch(TB.state(base6).board))
    }

    func testRun3RemovesWithoutSpecialAndCharges1() throws {
        let s = TB.state(["HHCBSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        XCTAssertFalse(MatchResolver.hasAnyMatch(s.board))
        let r = try TB.swap(s, (2, 1), (2, 0))
        let w1 = TB.waves(r)[0]
        XCTAssertEqual(w1.groups.count, 1)
        XCTAssertEqual(Set(w1.groups[0].cells), [Coord(0, 0), Coord(1, 0), Coord(2, 0)])
        XCTAssertEqual(w1.chargeGained, 1)
        XCTAssertTrue(w1.created.isEmpty)
        XCTAssertEqual(r.state.movesLeft, 19)
        XCTAssertGreaterThanOrEqual(r.state.collected[GemColor.heart.rawValue], 3)
        XCTAssertLessThanOrEqual(r.chargeGained, ChargePolicy.perSwapCap)
    }

    func testRun4CreatesLineSparkAtDestinationKeepingColorUnit() throws {
        let s = TB.state(["HHCHSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        XCTAssertFalse(MatchResolver.hasAnyMatch(s.board))
        let r = try TB.swap(s, (2, 1), (2, 0))
        let w1 = TB.waves(r)[0]
        XCTAssertEqual(w1.chargeGained, 3)
        XCTAssertEqual(w1.created.count, 1)
        XCTAssertEqual(w1.created[0].at, Coord(2, 0))
        XCTAssertEqual(w1.created[0].occupant.kind, .lineSpark(.heart, .horizontal))
        // Anchor gem превращается в special и не засчитывается второй раз: удалено 3, а не 4.
        XCTAssertEqual(w1.removed.count, 3)
        XCTAssertEqual(r.steps.first { if case .wave = $0.event { return true }; return false }!.collected[0], 3)
    }

    func testStraight5CreatesPrismAndCountsAbsorbedAnchor() throws {
        let s = TB.state(["HHCHHD", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        XCTAssertFalse(MatchResolver.hasAnyMatch(s.board))
        let r = try TB.swap(s, (2, 1), (2, 0))
        let w1 = TB.waves(r)[0]
        XCTAssertEqual(w1.chargeGained, 5)
        XCTAssertEqual(w1.created.first?.occupant.kind, .prism)
        XCTAssertEqual(w1.created.first?.at, Coord(2, 0))
        XCTAssertEqual(w1.removed.count, 5)
        XCTAssertEqual(r.steps.first { if case .wave = $0.event { return true }; return false }!.collected[0], 5)
    }

    func testTLShapeCreatesStageBurst() throws {
        let s = TB.state(["HHCHSH", "CBHHDC", "SHHCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        XCTAssertFalse(MatchResolver.hasAnyMatch(s.board))
        let r = try TB.swap(s, (3, 0), (2, 0))
        let w1 = TB.waves(r)[0]
        XCTAssertEqual(w1.groups.count, 1)
        XCTAssertEqual(w1.groups[0].cells.count, 5)
        XCTAssertEqual(w1.created.first?.occupant.kind, .stageBurst(.heart))
        XCTAssertEqual(w1.created.first?.at, Coord(2, 0))
        XCTAssertEqual(w1.chargeGained, 5)
    }

    func testPrismHasPriorityOverBurst() {
        // Straight5 + перпендикулярный run3 → Prism.
        var b = TB.state(base6).board
        for x in 0..<5 { b[Coord(x, 2)].occupant = Occupant(id: 900 + x, kind: .gem(.heart)) }
        b[Coord(2, 3)].occupant = Occupant(id: 950, kind: .gem(.heart))
        b[Coord(2, 4)].occupant = Occupant(id: 951, kind: .gem(.heart))
        let groups = MatchResolver.findGroups(b).filter { $0.color == .heart }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].special, .prism)
    }

    func testSeparateGroupsOfDifferentColors() {
        var b = TB.state(base6).board
        for x in 0..<3 { b[Coord(x, 0)].occupant = Occupant(id: 900 + x, kind: .gem(.heart)) }
        for x in 0..<3 { b[Coord(x, 1)].occupant = Occupant(id: 910 + x, kind: .gem(.diamond)) }
        let g = MatchResolver.findGroups(b)
        XCTAssertEqual(g.count, 2)
    }

    func testCascadeAnchorIsMinYX() throws {
        // Вертикальный run4 без swap → anchor = минимальная (y, x) клетка.
        var s = TB.state(base6)
        for y in 1...4 { s.board[Coord(3, y)].occupant = Occupant(id: 900 + y, kind: .gem(.star)) }
        var r = Resolver(state: s, record: true)
        try r.resolve(groups: MatchResolver.findGroups(r.s.board), sweep: [], forced: [], consumed: [], preferredAnchors: [])
        let w1 = r.steps.compactMap { if case .wave(let w) = $0.event { return w } else { return nil } }[0]
        XCTAssertEqual(w1.created.first?.at, Coord(3, 1))
        XCTAssertEqual(w1.created.first?.occupant.kind, .lineSpark(.star, .vertical))
    }

    func testSourceAnchorWhenDestinationNotInGroup() throws {
        // Игрок ведёт фишку из (2,0) вниз в (2,1); run4 образуется в строке 0 через source (2,0).
        let s = TB.state(["HHDHSC", "CBHSDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        XCTAssertFalse(MatchResolver.hasAnyMatch(s.board))
        let r = try TB.swap(s, (2, 0), (2, 1))
        let w1 = TB.waves(r)[0]
        XCTAssertEqual(w1.created.first?.at, Coord(2, 0))
    }

    func testInvalidSwapDoesNotSpendAnything() {
        let s = TB.state(base6)
        XCTAssertThrowsError(try TB.swap(s, (0, 0), (1, 0))) { e in
            XCTAssertEqual(e as? EngineError, .invalidSwap("No match"))
        }
        XCTAssertThrowsError(try TB.swap(s, (0, 0), (1, 1)))   // диагональ
        XCTAssertThrowsError(try TB.swap(s, (0, 0), (2, 0)))   // не соседи
        XCTAssertEqual(s.movesLeft, 20)
        XCTAssertEqual(s.rng, LevelRNG(seed: 42))
    }

    func testKeysAndPinnedAndVoidCannotBeSwapped() {
        var s = TB.state(["HHCBSH", "CB1HDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        XCTAssertNotNil(GameEngine.swapRejection(s, from: Coord(2, 1), to: Coord(2, 0)))
        s.board[Coord(0, 5)].overlay = .ice(hp: 1)
        XCTAssertNotNil(GameEngine.swapRejection(s, from: Coord(0, 5), to: Coord(1, 5)))
        let v = TB.state([".HCBSH", "CBSHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        XCTAssertNotNil(GameEngine.swapRejection(v, from: Coord(0, 0), to: Coord(1, 0)))
    }

    func testDuplicateActionIDRejected() throws {
        let s = TB.state(["HHCBSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        let a = GameAction(id: "same", kind: .swap(from: Coord(2, 1), to: Coord(2, 0)))
        let r = try GameEngine.apply(a, to: s)
        var s2 = r.state
        s2.board = s.board
        XCTAssertThrowsError(try GameEngine.apply(a, to: s2)) { XCTAssertEqual($0 as? EngineError, .duplicateAction) }
    }

    func testStaleRevisionRejected() {
        let s = TB.state(["HHCBSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        let a = GameAction(id: "x", kind: .swap(from: Coord(2, 1), to: Coord(2, 0)), expectedRevision: 5)
        XCTAssertThrowsError(try GameEngine.apply(a, to: s)) { XCTAssertEqual($0 as? EngineError, .staleRevision) }
    }

    func testDeterminismSameSeedSameActions() throws {
        let s = TB.state(["HHCBSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"], charge: 12)
        func run() throws -> String {
            var st = s
            st = try GameEngine.apply(GameAction(id: "a", kind: .swap(from: Coord(2, 1), to: Coord(2, 0))), to: st).state
            st = try GameEngine.apply(GameAction(id: "b", kind: .rotate), to: st).state
            return StateHasher.hash(st)
        }
        XCTAssertEqual(try run(), try run())
        // Запись шагов для renderer не меняет результат.
        let a = try GameEngine.apply(GameAction(id: "a", kind: .rotate), to: s, recordSteps: true).state
        let b = try GameEngine.apply(GameAction(id: "a", kind: .rotate), to: s, recordSteps: false).state
        XCTAssertEqual(StateHasher.hash(a), StateHasher.hash(b))
    }
}

final class SweepAndRotationTests: XCTestCase {
    func testTurnCostsMoveAndFullChargeAndChangesQ() throws {
        let s = TB.state(base6, charge: 12)
        let r = try TB.rotate(s)
        XCTAssertEqual(r.state.q, 1)
        XCTAssertEqual(r.state.movesLeft, 19)
        XCTAssertEqual(r.state.turnsUsed, 1)
        XCTAssertLessThanOrEqual(r.state.charge, ChargePolicy.perTurnCap)
        XCTAssertLessThanOrEqual(r.chargeGained, ChargePolicy.perTurnCap)
    }

    func testTurnUnavailableWithoutFullCharge() {
        XCTAssertThrowsError(try TB.rotate(TB.state(base6, charge: 11))) {
            XCTAssertEqual($0 as? EngineError, .turnUnavailable)
        }
    }

    func testQWrapsFrom3To0WithoutResettingObjectives() throws {
        var s = TB.state(base6, charge: 12, q: 3)
        s.collected = [5, 0, 0, 0, 0]
        let r = try TB.rotate(s)
        XCTAssertEqual(r.state.q, 0)
        XCTAssertGreaterThanOrEqual(r.state.collected[0], 5)
    }

    func testSweepHitsOneFrontierPerSegment() throws {
        let s = TB.state(base6, charge: 12)
        let r = try TB.rotate(s)
        let w1 = TB.waves(r)[0]
        XCTAssertEqual(Set(w1.sweepCells), Set((0..<6).map { Coord(5, $0) }))
        XCTAssertEqual(w1.removed.count, 6)
    }

    func testPreviewIsFreeAndMatchesSweep() throws {
        let s = TB.state(base6, charge: 12)
        let p = GameEngine.previewTurn(s)
        XCTAssertEqual(p.nextQ, 1)
        XCTAssertEqual(p.nextGravity, .right)
        XCTAssertEqual(Set(p.frontier), Set((0..<6).map { Coord(5, $0) }))
        XCTAssertEqual(s.charge, 12)
        XCTAssertEqual(s.rng, LevelRNG(seed: 42))
        let r = try TB.rotate(s)
        XCTAssertEqual(Set(TB.waves(r)[0].sweepCells), Set(p.frontier))
    }

    func testSweepDoesNotDestroyKeyAndDoesNotHitPinnedBoundary() throws {
        var s = TB.state(["HDCBSH", "CBSHDC", "SHDCB1", "DCBSHD", "BSHDCB", "HDCBSH"], charge: 12,
                         objectives: [.keys])
        s.board[Coord(5, 3)].overlay = .ice(hp: 1)
        let r = try TB.rotate(s)
        let w1 = TB.waves(r)[0]
        // Строка 3: закреплённая клетка (5,3) делит линию; frontier — (4,3), (5,3) не бьётся.
        XCTAssertTrue(w1.sweepCells.contains(Coord(4, 3)))
        XCTAssertFalse(w1.sweepCells.contains(Coord(5, 3)))
        XCTAssertEqual(r.state.board[Coord(5, 3)].overlay, .ice(hp: 1))
        // Ключ на frontier не повреждается и не исчезает.
        XCTAssertNotNil(r.state.board.occupantIndex(id: s.board[Coord(5, 2)].occupant!.id))
        XCTAssertFalse(w1.removed.contains { $0.occupant.kind.isKey })
    }

    func testSweepActivatesSpecial() throws {
        var s = TB.state(base6, charge: 12)
        TB.setSpecial(&s, (5, 2), .lineSpark(.star, .horizontal))
        let r = try TB.rotate(s)
        let w1 = TB.waves(r)[0]
        XCTAssertTrue(w1.effects.contains(.line(origin: Coord(5, 2), axis: .horizontal)))
        // Луч очищает весь ряд 2 (6 клеток) + остальные frontier (5 клеток).
        XCTAssertEqual(w1.removed.count, 11)
    }

    func testPlateClearedOnlyWhereGemRemoved() throws {
        var s = TB.state(base6, charge: 12, objectives: [.plates])
        s.board[Coord(5, 0)].floor = .plate(hp: 1)
        s.board[Coord(5, 1)].floor = .plate(hp: 2)
        s.board[Coord(0, 0)].floor = .plate(hp: 1)
        let r = try TB.rotate(s)
        let w1 = TB.waves(r)[0]
        XCTAssertTrue(w1.damaged.contains(DamageEvent(at: Coord(5, 0), layer: .plate, remainingHP: 0)))
        XCTAssertTrue(w1.damaged.contains(DamageEvent(at: Coord(5, 1), layer: .plate, remainingHP: 1)))
        XCTAssertFalse(w1.damaged.contains { $0.at == Coord(0, 0) })
    }

    func testKeyExtractedThroughActivePortOnce() throws {
        let port = ExitPort(x: 5, y: 2, direction: .right)
        let s = TB.state(["HDCBSH", "CBSHDC", "SHDC1S", "DCBSHD", "BSHDCB", "HDCBSH"], charge: 12,
                         objectives: [.keys], ports: [port])
        let r = try TB.rotate(s)
        XCTAssertEqual(r.state.extractedKeyIDs, [1])
        XCTAssertTrue(r.state.board.keyCoords.isEmpty)
        XCTAssertEqual(r.outcome, .won(stars: 3))
        XCTAssertTrue(r.steps.contains { if case .keysExtracted(let k) = $0.event { return k.count == 1 }; return false })
    }

    func testPortBoundToAnotherKeyDoesNotExtract() throws {
        let port = ExitPort(x: 5, y: 2, direction: .right, keyID: 2)
        let s = TB.state(["HDCBSH", "CBSHDC", "SHDC1S", "DCBSHD", "BSHDCB", "HDCBSH"], charge: 12,
                         objectives: [.keys], ports: [port])
        let r = try TB.rotate(s)
        XCTAssertEqual(r.state.extractedKeyIDs, [])
        let own = ExitPort(x: 5, y: 2, direction: .right, keyID: 1)
        var s2 = s
        s2.exitPorts = [own]
        XCTAssertEqual(try TB.rotate(s2).state.extractedKeyIDs, [1])
    }

    func testInactivePortDoesNotExtract() throws {
        let port = ExitPort(x: 5, y: 2, direction: .up)
        let s = TB.state(["HDCBSH", "CBSHDC", "SHDC1S", "DCBSHD", "BSHDCB", "HDCBSH"], charge: 12,
                         objectives: [.keys], ports: [port])
        let r = try TB.rotate(s)
        XCTAssertEqual(r.state.extractedKeyIDs, [])
        XCTAssertEqual(r.state.board.keyCoords.count, 1)
    }

    func testKeyAlreadyOnPortExtractedBeforeSweep() throws {
        let port = ExitPort(x: 5, y: 2, direction: .right)
        let s = TB.state(["HDCBSH", "CBSHDC", "SHDCB1", "DCBSHD", "BSHDCB", "HDCBSH"], charge: 12,
                         objectives: [.keys], ports: [port])
        let r = try TB.rotate(s)
        guard case .keysExtracted = r.steps[1].event else { return XCTFail("extraction must follow rotation") }
        XCTAssertEqual(r.state.extractedKeyIDs, [1])
    }
}

final class GravityTests: XCTestCase {
    func testCompactionInFourDirections() {
        for (q, expected) in [(0, Coord(1, 3)), (1, Coord(3, 1)), (2, Coord(1, 0)), (3, Coord(0, 1))] {
            var s = TB.state(["____", "_H__", "____", "____"], q: q)
            var r = Resolver(state: s, record: false)
            _ = r.applyGravity()
            s = r.s
            XCTAssertEqual(s.board.keyCoords.count, 0)
            let idx = s.board.cells.firstIndex { $0.occupant != nil }!
            XCTAssertEqual(s.board.coord(idx), expected, "q=\(q)")
        }
    }

    func testKeyFallsBetweenGems() {
        let s = TB.state(["H___", "1___", "____", "D___"])
        var r = Resolver(state: s, record: false)
        _ = r.applyGravity()
        XCTAssertEqual(r.s.board[Coord(0, 3)].occupant?.kind, .gem(.diamond))
        XCTAssertEqual(r.s.board[Coord(0, 2)].occupant?.kind, .key(1))
        XCTAssertEqual(r.s.board[Coord(0, 1)].occupant?.kind, .gem(.heart))
    }

    func testWallSplitsSegmentsAndInternalInletRefills() {
        let s = TB.state(["HH__", "#D__", "____", "_C__"])
        var r = Resolver(state: s, record: false)
        r.settleGravity()
        // Над стеной H не проходит сквозь неё.
        XCTAssertEqual(r.s.board[Coord(0, 0)].occupant?.kind, .gem(.heart))
        XCTAssertEqual(r.s.board[Coord(0, 1)].blocker, .wall)
        // Сегмент под стеной заполнен локальным inlet.
        XCTAssertNotNil(r.s.board[Coord(0, 2)].occupant)
        XCTAssertNotNil(r.s.board[Coord(0, 3)].occupant)
        XCTAssertEqual(r.s.board[Coord(1, 3)].occupant?.kind, .gem(.clover))
        XCTAssertTrue(r.s.board.cells.allSatisfy { !$0.isFlow || $0.occupant != nil })
    }

    func testPinnedGemDoesNotFall() {
        var s = TB.state(["H___", "____", "____", "____"])
        s.board[Coord(0, 0)].overlay = .chain(hp: 1)
        var r = Resolver(state: s, record: false)
        _ = r.applyGravity()
        XCTAssertEqual(r.s.board[Coord(0, 0)].occupant?.kind, .gem(.heart))
    }

    func testOpenedShutterIsFilled() throws {
        // Switch в (0,5) под сердцем; ряд 5 даёт HHH после swap; shutter (3,3) открывается и заполняется.
        var s = TB.state(["HDCBSH", "CBSHDC", "SHDCBS", "DCBZHD", "BSHDCB", "HHDHSH"],
                         links: [ShutterSwitchLink(group: 0, switches: [Coord(0, 5)], shutters: [Coord(3, 3)])])
        s.board[Coord(0, 5)].floor = .switchPlate(group: 0, active: false)
        XCTAssertFalse(MatchResolver.hasAnyMatch(s.board))
        let r = try TB.swap(s, (3, 5), (2, 5))
        let w1 = TB.waves(r)[0]
        XCTAssertEqual(w1.switchesActivated, [Coord(0, 5)])
        XCTAssertEqual(w1.shuttersOpened, [Coord(3, 3)])
        XCTAssertNil(r.state.board[Coord(3, 3)].blocker)
        XCTAssertNotNil(r.state.board[Coord(3, 3)].occupant)
        XCTAssertEqual(r.state.board[Coord(0, 5)].floor, .switchPlate(group: 0, active: true))
    }

    func testSwitchStaysActive() throws {
        var s = TB.state(base6)
        s.board[Coord(0, 0)].floor = .switchPlate(group: 0, active: true)
        s.shutterLinks = [ShutterSwitchLink(group: 0, switches: [Coord(0, 0)], shutters: [])]
        var r = Resolver(state: s, record: true)
        r.runWave(groups: [], sweep: [0], forced: [], consumed: [], preferredAnchors: [])
        XCTAssertEqual(r.s.board[Coord(0, 0)].floor, .switchPlate(group: 0, active: true))
        let w = r.steps.compactMap { if case .wave(let w) = $0.event { return w } else { return nil } }[0]
        XCTAssertTrue(w.switchesActivated.isEmpty)
    }
}

final class ObstacleTests: XCTestCase {
    func testCrateDamagedByAdjacentMatchOncePerWave() throws {
        let s = TB.state(["HHCYSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        let r = try TB.swap(s, (2, 1), (2, 0))
        let w1 = TB.waves(r)[0]
        XCTAssertEqual(w1.damaged.filter { $0.layer == .crate }, [DamageEvent(at: Coord(3, 0), layer: .crate, remainingHP: 1)])
    }

    func testIceDamagedOnlyByOwnMatchAndGemStaysThisWave() throws {
        // Лёд на (1,0) — внутри match: gem остаётся, overlay снят; на (3,0) рядом — не повреждается.
        var s = TB.state(["HHCDSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        s.board[Coord(1, 0)].overlay = .ice(hp: 2)
        s.board[Coord(3, 0)].overlay = .ice(hp: 1)
        var r = Resolver(state: s, record: true)
        r.s.board[Coord(2, 0)].occupant = Occupant(id: 777, kind: .gem(.heart))
        r.runWave(groups: MatchResolver.findGroups(r.s.board), sweep: [], forced: [], consumed: [], preferredAnchors: [])
        XCTAssertEqual(r.s.board[Coord(1, 0)].overlay, .ice(hp: 1))
        XCTAssertEqual(r.s.board[Coord(1, 0)].occupant?.kind, .gem(.heart))
        XCTAssertEqual(r.s.board[Coord(3, 0)].overlay, .ice(hp: 1))
        XCTAssertNil(r.s.board[Coord(0, 0)].occupant)
    }

    func testPinnedMatchResolvesOnFollowingWave() throws {
        var s = TB.state(["HHCDSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        s.board[Coord(0, 0)].overlay = .chain(hp: 1)
        s.board[Coord(1, 0)].overlay = .chain(hp: 1)
        s.board[Coord(2, 0)].occupant = Occupant(id: 777, kind: .gem(.heart))
        s.board[Coord(2, 0)].overlay = .chain(hp: 1)
        var r = Resolver(state: s, record: true)
        try r.resolve(groups: MatchResolver.findGroups(r.s.board), sweep: [], forced: [], consumed: [], preferredAnchors: [])
        let waves = r.steps.compactMap { if case .wave(let w) = $0.event { return w } else { return nil } }
        XCTAssertGreaterThanOrEqual(waves.count, 2)
        XCTAssertEqual(waves[0].removed.count, 0)
        XCTAssertEqual(waves[0].damaged.filter { $0.layer == .chain }.count, 3)
        XCTAssertEqual(waves[1].removed.count, 3)
    }

    func testLineBeamPassesVoidAndWallWithoutDestroyingWall() throws {
        var s = TB.state(["HDCBSH", "CB#H.C", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        TB.setSpecial(&s, (0, 1), .lineSpark(.clover, .horizontal))
        var r = Resolver(state: s, record: true)
        r.runWave(groups: [], sweep: [], forced: [Resolver.Activation(cell: 6, effect: .line(.horizontal), ownerID: 5010)],
                  consumed: [], preferredAnchors: [])
        XCTAssertEqual(r.s.board[Coord(2, 1)].blocker, .wall)
        XCTAssertNil(r.s.board[Coord(3, 1)].occupant)
        XCTAssertNil(r.s.board[Coord(5, 1)].occupant)
    }
}

final class SpecialComboTests: XCTestCase {
    func comboFirstWave(_ a: OccupantKind, _ b: OccupantKind) throws -> (GameState, WaveEvent) {
        var s = TB.state(base6)
        TB.setSpecial(&s, (2, 2), a)
        TB.setSpecial(&s, (3, 2), b)
        let r = try TB.swap(s, (2, 2), (3, 2))
        return (s, TB.waves(r)[0])
    }

    func testLineLine() throws {
        let (_, w) = try comboFirstWave(.lineSpark(.heart, .horizontal), .lineSpark(.diamond, .vertical))
        let expected = Set((0..<6).map { Coord($0, 2) } + (0..<6).map { Coord(3, $0) })
        XCTAssertEqual(Set(w.hitCells), expected)
    }

    func testBurstBurst() throws {
        let (_, w) = try comboFirstWave(.stageBurst(.heart), .stageBurst(.diamond))
        var expected = Set<Coord>()
        for y in 0...4 { for x in 1...5 { expected.insert(Coord(x, y)) } }
        XCTAssertEqual(Set(w.hitCells), expected)
    }

    func testLineBurst() throws {
        let (_, w) = try comboFirstWave(.lineSpark(.heart, .horizontal), .stageBurst(.diamond))
        var expected = Set<Coord>()
        for y in 1...3 { for x in 0..<6 { expected.insert(Coord(x, y)) } }
        for x in 2...4 { for y in 0..<6 { expected.insert(Coord(x, y)) } }
        XCTAssertEqual(Set(w.hitCells), expected)
    }

    func testPrismLineTurnsColorIntoAlternatingBeams() throws {
        let (s, w) = try comboFirstWave(.prism, .lineSpark(.bell, .horizontal))
        let bells = s.board.cells.indices.filter { s.board.cells[$0].occupant?.kind == .gem(.bell) }.map { s.board.coord($0) }
        let lines = w.effects.compactMap { e -> (Coord, Axis)? in if case .line(let o, let a) = e { return (o, a) } else { return nil } }
        XCTAssertEqual(lines.count, bells.count)
        for (k, l) in lines.enumerated() {
            XCTAssertEqual(l.0, bells.sorted()[k])
            XCTAssertEqual(l.1, k % 2 == 0 ? .horizontal : .vertical)
        }
    }

    func testPrismBurst() throws {
        let (s, w) = try comboFirstWave(.prism, .stageBurst(.clover))
        let clovers = s.board.cells.filter { $0.occupant?.kind == .gem(.clover) }.count
        let bursts = w.effects.filter { if case .burst = $0 { return true }; return false }.count
        XCTAssertEqual(bursts, clovers)
    }

    func testPrismPrismHitsAllCells() throws {
        let (_, w) = try comboFirstWave(.prism, .prism)
        XCTAssertEqual(w.hitCells.count, 36)
    }

    func testPrismWithGemClearsThatColor() throws {
        var s = TB.state(base6)
        TB.setSpecial(&s, (2, 2), .prism)
        let hearts = s.board.cells.filter { $0.occupant?.kind == .gem(.heart) }.count
        let partnerColor = s.board[Coord(3, 2)].occupant!.kind.baseColor!
        let r = try TB.swap(s, (2, 2), (3, 2))
        let w = TB.waves(r)[0]
        let removedOfColor = w.removed.filter { $0.occupant.kind.baseColor == partnerColor }.count
        let expected = s.board.cells.filter { $0.occupant?.kind.baseColor == partnerColor }.count
        XCTAssertEqual(removedOfColor, expected)
        XCTAssertTrue(w.removed.contains { $0.occupant.kind == .prism })
        _ = hearts
    }

    func testLineWithGemActivatesAtNewCell() throws {
        var s = TB.state(base6)
        TB.setSpecial(&s, (2, 2), .lineSpark(.heart, .vertical))
        let r = try TB.swap(s, (2, 2), (3, 2))
        let w = TB.waves(r)[0]
        XCTAssertTrue(w.effects.contains(.line(origin: Coord(3, 2), axis: .vertical)))
        XCTAssertEqual(r.state.movesLeft, 19)
    }

    func testEachSpecialActivatesOncePerWave() throws {
        var s = TB.state(base6)
        TB.setSpecial(&s, (0, 3), .lineSpark(.heart, .horizontal))
        TB.setSpecial(&s, (4, 3), .lineSpark(.star, .horizontal))
        var r = Resolver(state: s, record: true)
        r.runWave(groups: [], sweep: [18], forced: [], consumed: [], preferredAnchors: [])
        let w = r.steps.compactMap { if case .wave(let w) = $0.event { return w } else { return nil } }[0]
        XCTAssertEqual(w.effects.count, 2)
    }

    func testPrismHitByBlastPicksMostFrequentColorWithTieOrder() {
        var s = TB.state(["HDCBS", "HDCBS", "HDCBS", "HDCBS", "HDCBS"])
        s.board[Coord(4, 4)].occupant = Occupant(id: 99, kind: .prism)
        // Каждый цвет по 5, S — 4 после замены: tie → Heart.
        let r = Resolver(state: s, record: false)
        XCTAssertEqual(r.mostFrequentColor(), .heart)
    }

    func testSpecialPlusSpecialValidWithoutMatch() {
        var s = TB.state(base6)
        TB.setSpecial(&s, (0, 0), .stageBurst(.heart))
        XCTAssertNil(GameEngine.swapRejection(s, from: Coord(0, 0), to: Coord(1, 0)))
    }
}

final class ChargeWinDeadlockTests: XCTestCase {
    func testChargeGainTable() {
        XCTAssertEqual(ChargePolicy.gain(forGroupSize: 3), 1)
        XCTAssertEqual(ChargePolicy.gain(forGroupSize: 4), 3)
        XCTAssertEqual(ChargePolicy.gain(forGroupSize: 5), 5)
        XCTAssertEqual(ChargePolicy.gain(forGroupSize: 7), 5)
    }

    func testSwapCapOf6AndTurnCapOf4AndMax12() throws {
        var s = TB.state(base6)
        // Четыре отдельные группы: 3+3+3+5 → 1+1+1+5 = 8, cap 6.
        for x in 0..<3 { s.board[Coord(x, 0)].occupant = Occupant(id: 900 + x, kind: .gem(.heart)) }
        for x in 3..<6 { s.board[Coord(x, 0)].occupant = Occupant(id: 910 + x, kind: .gem(.diamond)) }
        for x in 0..<3 { s.board[Coord(x, 2)].occupant = Occupant(id: 920 + x, kind: .gem(.clover)) }
        for x in 0..<5 { s.board[Coord(x, 4)].occupant = Occupant(id: 930 + x, kind: .gem(.star)) }
        var r = Resolver(state: s, record: false)
        r.chargeCap = ChargePolicy.perSwapCap
        try r.resolve(groups: MatchResolver.findGroups(r.s.board), sweep: [], forced: [], consumed: [], preferredAnchors: [])
        XCTAssertEqual(r.chargeGainedThisAction, 6)
        var t = Resolver(state: s, record: false)
        t.chargeCap = ChargePolicy.perTurnCap
        try t.resolve(groups: MatchResolver.findGroups(t.s.board), sweep: [], forced: [], consumed: [], preferredAnchors: [])
        XCTAssertEqual(t.chargeGainedThisAction, 4)
        s.charge = 10
        var m = Resolver(state: s, record: false)
        try m.resolve(groups: MatchResolver.findGroups(m.s.board), sweep: [], forced: [], consumed: [], preferredAnchors: [])
        XCTAssertEqual(m.s.charge, 12)
    }

    func testStarsFormula() {
        XCTAssertEqual(WinPolicy.stars(initialMoves: 24, movesLeft: 3), 1)
        XCTAssertEqual(WinPolicy.stars(initialMoves: 24, movesLeft: 4), 2)
        XCTAssertEqual(WinPolicy.stars(initialMoves: 24, movesLeft: 7), 2)
        XCTAssertEqual(WinPolicy.stars(initialMoves: 24, movesLeft: 8), 3)
        XCTAssertEqual(WinPolicy.stars(initialMoves: 18, movesLeft: 0), 1)
        XCTAssertEqual(WinPolicy.stars(initialMoves: 18, movesLeft: 3), 2)   // ceil(2.7)=3
        XCTAssertEqual(WinPolicy.stars(initialMoves: 18, movesLeft: 6), 3)   // ceil(5.4)=6
    }

    func testWinOnLastMoveBeforeFail() throws {
        let s = TB.state(["HHCBSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"], moves: 1,
                         objectives: [.collect(color: .heart, target: 3)])
        let r = try TB.swap(s, (2, 1), (2, 0))
        XCTAssertEqual(r.state.movesLeft, 0)
        XCTAssertEqual(r.outcome, .won(stars: 1))
    }

    func testFailWhenMovesRunOut() throws {
        let s = TB.state(["HHCBSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"], moves: 1,
                         objectives: [.collect(color: .heart, target: 60)])
        let r = try TB.swap(s, (2, 1), (2, 0))
        XCTAssertEqual(r.outcome, .failed)
        XCTAssertThrowsError(try TB.rotate(r.state)) { XCTAssertEqual($0 as? EngineError, .notPlaying) }
    }

    func testDeadlockPrefersTurnOverShuffle() throws {
        let s = TB.state(["HDCH", "CHDC", "DCHD", "HDCH"], charge: 12)
        XCTAssertTrue(GameEngine.validSwaps(s).isEmpty)
        var r = Resolver(state: s, record: true)
        _ = try r.finish()
        XCTAssertTrue(r.didSuggestTurn)
        XCTAssertFalse(r.didShuffle)
        XCTAssertEqual(r.s.board, s.board)
    }

    func testDeadlockShufflePreservesImmovables() throws {
        var s = TB.state(["HDCHD", "C#DCH", "DCHD1", "HDCHD", "CHDCH"], charge: 0,
                         objectives: [.collect(color: .heart, target: 50)])
        s.board[Coord(0, 0)].floor = .plate(hp: 1)
        s.board[Coord(4, 4)].overlay = .ice(hp: 1)
        XCTAssertTrue(GameEngine.validSwaps(s).isEmpty)
        let before = s
        var r = Resolver(state: s, record: true)
        _ = try r.finish()
        XCTAssertTrue(r.didShuffle)
        XCTAssertFalse(MatchResolver.hasAnyMatch(r.s.board))
        XCTAssertFalse(GameEngine.validSwaps(r.s).isEmpty)
        XCTAssertEqual(r.s.board[Coord(1, 1)].blocker, .wall)
        XCTAssertEqual(r.s.board[Coord(4, 2)].occupant?.kind, .key(1))
        XCTAssertEqual(r.s.board[Coord(4, 4)].occupant, before.board[Coord(4, 4)].occupant)
        XCTAssertEqual(r.s.board[Coord(0, 0)].floor, .plate(hp: 1))
        XCTAssertEqual(r.s.movesLeft, before.movesLeft)
        XCTAssertNotEqual(r.s.rng, before.rng)
    }

    func testDeadlockWithoutCandidateIsStageDataError() {
        let s = TB.state(["H#D", "###", "C##"], charge: 0)
        var r = Resolver(state: s, record: false)
        XCTAssertThrowsError(try r.finish()) {
            guard case .stageDataError = $0 as? EngineError else { return XCTFail("\($0)") }
        }
    }

    func testHintPrefersObjectiveProgress() {
        let s = TB.state(["HHCBSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"],
                         objectives: [.collect(color: .heart, target: 10)])
        let h = HintPolicy.suggest(for: s)
        XCTAssertNotNil(h)
        if case .swap(let a, let b)? = h {
            XCTAssertTrue(GameEngine.isValidSwap(s, from: a, to: b))
        }
        let blocked = TB.state(["HDCH", "CHDC", "DCHD", "HDCH"], charge: 12)
        XCTAssertEqual(HintPolicy.suggest(for: blocked), .turn)
        let none = TB.state(["HDCH", "CHDC", "DCHD", "HDCH"], charge: 0)
        XCTAssertNil(HintPolicy.suggest(for: none))
    }
}

final class DailyTests: XCTestCase {
    func testAll125OutcomesDistribution() {
        var counts: [DailyOutcomeKind: Int] = [:]
        var total = 0
        for a in GemColor.allCases { for b in GemColor.allCases { for c in GemColor.allCases {
            counts[DailyRewardPolicy.classify([a, b, c]), default: 0] += 1
            total += DailyRewardPolicy.nominalReward(for: [a, b, c])
        } } }
        XCTAssertEqual(counts[.mixed], 60)
        XCTAssertEqual(counts[.pair], 60)
        XCTAssertEqual(counts[.triple], 5)
        XCTAssertEqual(Double(total) / 125.0, 1.64, accuracy: 1e-9)
        XCTAssertEqual(DailyOutcomeKind.mixed.probabilityPercent, 48)
        XCTAssertEqual(DailyOutcomeKind.triple.probabilityPercent, 4)
    }

    func testPairAnyPositions() {
        XCTAssertEqual(DailyRewardPolicy.classify([.heart, .star, .heart]), .pair)
        XCTAssertEqual(DailyRewardPolicy.classify([.star, .heart, .heart]), .pair)
        XCTAssertEqual(DailyRewardPolicy.classify([.bell, .bell, .bell]), .triple)
    }

    func testUTCDayAndEligibility() {
        XCTAssertEqual(DailyRewardPolicy.dayIndex(unixTime: 0), 0)
        XCTAssertEqual(DailyRewardPolicy.dayIndex(unixTime: 86_399.9), 0)
        XCTAssertEqual(DailyRewardPolicy.dayIndex(unixTime: 86_400), 1)
        XCTAssertTrue(DailyRewardPolicy.isEligible(currentDay: 100, highestClaimedDay: nil))
        XCTAssertFalse(DailyRewardPolicy.isEligible(currentDay: 100, highestClaimedDay: 100))
        XCTAssertFalse(DailyRewardPolicy.isEligible(currentDay: 99, highestClaimedDay: 100))   // часы назад
        XCTAssertTrue(DailyRewardPolicy.isEligible(currentDay: 101, highestClaimedDay: 100))
    }

    func testCreditCap() {
        XCTAssertEqual(DailyRewardPolicy.creditedAmount(nominal: 5, oldBalance: 999_998), 2)
        XCTAssertEqual(DailyRewardPolicy.creditedAmount(nominal: 5, oldBalance: 1_000_000), 0)
        XCTAssertEqual(HintEconomy.credit(1, to: 1_000_000).credited, 0)
    }
}

final class AnchorAndRollbackTests: XCTestCase {
    func testPlateUnderLineSparkAnchorNotDamagedButUnderPrismAnchorIs() throws {
        // Run4: anchor (2,0) превращается в LineSpark — пластина под ним не получает hit.
        var s = TB.state(["HHCHSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"], objectives: [.plates])
        s.board[Coord(2, 0)].floor = .plate(hp: 1)
        s.board[Coord(0, 0)].floor = .plate(hp: 1)
        var r = try TB.swap(s, (2, 1), (2, 0))
        var w1 = TB.waves(r)[0]
        XCTAssertFalse(w1.damaged.contains { $0.at == Coord(2, 0) && $0.layer == .plate })
        XCTAssertTrue(w1.damaged.contains { $0.at == Coord(0, 0) && $0.layer == .plate })
        // Straight5: anchor gem поглощён Prism — пластина под ним получает hit.
        var p = TB.state(["HHCHHD", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"], objectives: [.plates])
        p.board[Coord(2, 0)].floor = .plate(hp: 1)
        r = try TB.swap(p, (2, 1), (2, 0))
        w1 = TB.waves(r)[0]
        XCTAssertTrue(w1.damaged.contains { $0.at == Coord(2, 0) && $0.layer == .plate })
    }

    func testWaveLimitRollsBackWholeAction() {
        let s = TB.state(["HHCBSH", "CBHHDC", "SHDCBS", "DCBSHD", "BSHDCB", "HDCBSH"])
        let saved = GameEngine.maxWavesPerAction
        GameEngine.maxWavesPerAction = 0
        defer { GameEngine.maxWavesPerAction = saved }
        XCTAssertThrowsError(try TB.swap(s, (2, 1), (2, 0))) { XCTAssertEqual($0 as? EngineError, .waveLimitExceeded) }
        // Исходное состояние (moves, charge, RNG) не изменилось — value semantics.
        XCTAssertEqual(s.movesLeft, 20)
        XCTAssertEqual(s.rng, LevelRNG(seed: 42))
    }
}
