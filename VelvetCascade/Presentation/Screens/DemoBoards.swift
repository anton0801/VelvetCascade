// DemoBoards.swift — детерминированные демо-поля для обучения и Handbook (изолированы от профиля).

import Foundation
import VelvetDomain

enum DemoBoards {
    /// ASCII: H D C B S — gems; '.' void; '#' baffle; 'X' crate HP1; 'Y' crate HP2; 'Z' shutter A; '1' key;
    /// строчные h/d/c/b/s — gem под льдом HP1; 'i' — не используется; '*' — Burst Heart; '-' '|' — LineSpark Heart; 'P' — Prism.
    static func state(_ rows: [String], charge: Int = 0, moves: Int = 20, seed: UInt64 = 7,
                      objectives: [ObjectiveDef] = [.collect(color: .heart, target: 99)],
                      ports: [ExitPort] = [], links: [ShutterSwitchLink] = [],
                      plates: [Coord: Int] = [:], switches: [Coord: Int] = [:], chains: Set<Coord> = []) -> GameState {
        let n = rows.count
        var board = Board(n: n) { Array(rows[$0.y])[$0.x] != "." }
        var id = 1
        var keys: [Int] = []
        for y in 0..<n {
            let row = Array(rows[y])
            for x in 0..<n {
                let c = Coord(x, y)
                let ch = row[x]
                switch ch {
                case "H", "D", "C", "B", "S":
                    board[c].occupant = Occupant(id: id, kind: .gem(GemColor(letter: String(ch))!)); id += 1
                case "h", "d", "c", "b", "s":
                    board[c].occupant = Occupant(id: id, kind: .gem(GemColor(letter: String(ch))!)); id += 1
                    board[c].overlay = .ice(hp: 1)
                case "#": board[c].blocker = .wall
                case "X": board[c].blocker = .crate(hp: 1)
                case "Y": board[c].blocker = .crate(hp: 2)
                case "Z": board[c].blocker = .shutter(group: 0)
                case "1", "2":
                    let k = Int(String(ch))!
                    board[c].occupant = Occupant(id: id, kind: .key(k)); id += 1
                    keys.append(k)
                case "*": board[c].occupant = Occupant(id: id, kind: .stageBurst(.heart)); id += 1
                case "-": board[c].occupant = Occupant(id: id, kind: .lineSpark(.heart, .horizontal)); id += 1
                case "|": board[c].occupant = Occupant(id: id, kind: .lineSpark(.heart, .vertical)); id += 1
                case "P": board[c].occupant = Occupant(id: id, kind: .prism); id += 1
                default: break
                }
                if chains.contains(c) { board[c].overlay = .chain(hp: 1) }
            }
        }
        for (c, hp) in plates { board[c].floor = .plate(hp: hp) }
        for (c, g) in switches { board[c].floor = .switchPlate(group: g, active: false) }
        return GameState(levelID: 0, levelVersion: 1, board: board, q: 0, initialMoves: moves, movesLeft: moves,
                         initialCharge: charge, charge: charge, rng: LevelRNG(seed: seed), nextOccupantID: 500,
                         revision: 0, turnsUsed: 0, collected: [0, 0, 0, 0, 0], extractedKeyIDs: [],
                         objectives: objectives, initialKeyIDs: keys.sorted(), exitPorts: ports, shutterLinks: links,
                         status: .playing, recentActionIDs: [], specialsCreated: 0, shufflesPerformed: 0)
    }

    /// Match Tutorial: Heart Diamond Heart / Bell Heart Clover / Star Diamond Bell; центр вверх → 3 сердца.
    static var match3: GameState {
        state(["HDH", "BHC", "SDB"], seed: 11)
    }
    static let match3Swap = (Coord(1, 1), Coord(1, 0))

    /// Отдельная управляемая последовательность 4-match (не из 3×3 матрицы).
    static var match4: GameState {
        state(["HHDH", "CBHS", "SDCB", "BSDC"], seed: 5)
    }
    static let match4Swap = (Coord(2, 1), Coord(2, 0))

    /// Rotation Tutorial: ключ перед правым выходом; поворот → Sweep → ключ падает в выход.
    static var rotate: GameState {
        state(["HDCBS", "CBSHD", "SHD1C", "DCBSH", "BSHDC"], charge: 12, seed: 3, objectives: [.keys],
              ports: [ExitPort(x: 4, y: 2, direction: .right, keyID: 1)])
    }
}
