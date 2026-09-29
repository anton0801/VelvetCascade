import XCTest
@testable import VelvetDomain

/// ASCII-конструктор поля для тестов.
/// H D C B S — gems; '.' — void; '#' — wall; 'X' — crate HP1; 'Y' — crate HP2; '1'…'3' — ключи;
/// '_' — пустая playable клетка; 'Z' — closed shutter группы 0.
enum TB {
    static func state(_ rows: [String], moves: Int = 20, charge: Int = 0, q: Int = 0, seed: UInt64 = 42,
                      objectives: [ObjectiveDef] = [.collect(color: .heart, target: 99)],
                      ports: [ExitPort] = [], links: [ShutterSwitchLink] = []) -> GameState {
        let n = rows.count
        var board = Board(n: n) { c in
            let ch = Array(rows[c.y])[c.x]
            return ch != "."
        }
        var id = 1
        var keyIDs: [Int] = []
        for y in 0..<n {
            let row = Array(rows[y])
            precondition(row.count == n, "row \(y) length")
            for x in 0..<n {
                let c = Coord(x, y)
                switch row[x] {
                case "H", "D", "C", "B", "S":
                    board[c].occupant = Occupant(id: id, kind: .gem(GemColor(letter: String(row[x]))!)); id += 1
                case "#": board[c].blocker = .wall
                case "X": board[c].blocker = .crate(hp: 1)
                case "Y": board[c].blocker = .crate(hp: 2)
                case "Z": board[c].blocker = .shutter(group: 0)
                case "1", "2", "3":
                    let k = Int(String(row[x]))!
                    board[c].occupant = Occupant(id: id, kind: .key(k)); id += 1
                    keyIDs.append(k)
                default: break
                }
            }
        }
        return GameState(levelID: 1, levelVersion: 1, board: board, q: q, initialMoves: moves, movesLeft: moves,
                         initialCharge: charge, charge: charge, rng: LevelRNG(seed: seed), nextOccupantID: 1000,
                         revision: 0, turnsUsed: 0, collected: [0, 0, 0, 0, 0], extractedKeyIDs: [],
                         objectives: objectives, initialKeyIDs: keyIDs.sorted(), exitPorts: ports,
                         shutterLinks: links, status: .playing, recentActionIDs: [], specialsCreated: 0,
                         shufflesPerformed: 0)
    }

    static var counter = 0
    static func act(_ kind: GameActionKind) -> GameAction {
        counter += 1
        return GameAction(id: "t\(counter)", kind: kind)
    }

    static func swap(_ s: GameState, _ a: (Int, Int), _ b: (Int, Int)) throws -> ActionResult {
        try GameEngine.apply(act(.swap(from: Coord(a.0, a.1), to: Coord(b.0, b.1))), to: s)
    }

    static func rotate(_ s: GameState) throws -> ActionResult {
        try GameEngine.apply(act(.rotate), to: s)
    }

    static func waves(_ r: ActionResult) -> [WaveEvent] {
        r.steps.compactMap { if case .wave(let w) = $0.event { return w } else { return nil } }
    }

    static func setSpecial(_ s: inout GameState, _ c: (Int, Int), _ kind: OccupantKind) {
        s.board[Coord(c.0, c.1)].occupant = Occupant(id: 5000 + c.1 * 10 + c.0, kind: kind)
    }
}
