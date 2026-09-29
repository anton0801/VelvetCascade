// LevelFactory.swift — построение стартового GameState из LevelDefinition и hash состояния.

public enum LevelFactory {
    public static func board(for level: LevelDefinition) -> Board {
        var board = Board(n: level.n) { level.maskContains($0) }
        for b in level.blockers where board.inBounds(b.coord) {
            switch b.type {
            case "crate": board[b.coord].blocker = .crate(hp: b.hp ?? 1)
            case "wall": board[b.coord].blocker = .wall
            case "shutter": board[b.coord].blocker = .shutter(group: b.group ?? 0)
            default: break
            }
        }
        for f in level.floors where board.inBounds(f.coord) {
            switch f.type {
            case "plate": board[f.coord].floor = .plate(hp: f.hp ?? 1)
            case "switch": board[f.coord].floor = .switchPlate(group: f.group ?? 0, active: false)
            default: break
            }
        }
        for o in level.overlays where board.inBounds(o.coord) {
            switch o.type {
            case "ice": board[o.coord].overlay = .ice(hp: o.hp)
            case "chain": board[o.coord].overlay = .chain(hp: o.hp)
            default: break
            }
        }
        var nextID = 1
        for p in level.initialOccupants where board.inBounds(p.coord) {
            if let kind = p.kind() {
                board[p.coord].occupant = Occupant(id: nextID, kind: kind)
                nextID += 1
            }
        }
        return board
    }

    /// Стартовое состояние попытки (Retry восстанавливает то же поле, seed и initialCharge).
    public static func initialState(for level: LevelDefinition) -> GameState {
        let board = board(for: level)
        let maxID = board.cells.compactMap { $0.occupant?.id }.max() ?? 0
        return GameState(
            levelID: level.id,
            levelVersion: level.levelVersion,
            board: board,
            q: level.initialOrientation,
            initialMoves: level.initialMoves,
            movesLeft: level.initialMoves,
            initialCharge: level.initialCharge,
            charge: min(GameState.maxCharge, max(0, level.initialCharge)),
            rng: LevelRNG(seed: level.seed),
            nextOccupantID: maxID + 1,
            revision: 0,
            turnsUsed: 0,
            collected: [0, 0, 0, 0, 0],
            extractedKeyIDs: [],
            objectives: level.objectives,
            initialKeyIDs: level.initialKeyIDs,
            exitPorts: level.exitPorts,
            shutterLinks: level.shutterSwitchLinks,
            status: .playing,
            recentActionIDs: [],
            specialsCreated: 0,
            shufflesPerformed: 0
        )
    }
}

/// Канонический 64-bit FNV-1a hash settled-состояния (стабилен между платформами и запусками;
/// Swift Hasher не используется, т.к. он рандомизирован).
public enum StateHasher {
    public static func hash(_ s: GameState) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        @inline(__always) func mix(_ v: Int) {
            var x = UInt64(bitPattern: Int64(v))
            for _ in 0..<8 {
                h ^= x & 0xff
                h = h &* 0x0000_0100_0000_01b3
                x >>= 8
            }
        }
        mix(s.board.n)
        mix(s.q)
        mix(s.movesLeft)
        mix(s.charge)
        mix(Int(truncatingIfNeeded: s.rng.state))
        mix(s.nextOccupantID)
        mix(s.turnsUsed)
        mix(s.status == .playing ? 0 : (s.status == .won ? 1 : 2))
        for c in s.collected { mix(c) }
        mix(s.extractedKeyIDs.count)
        for k in s.extractedKeyIDs { mix(k) }
        for cell in s.board.cells {
            mix(cell.playable ? 1 : 0)
            if let o = cell.occupant {
                mix(o.id)
                switch o.kind {
                case .gem(let c): mix(10 + c.rawValue)
                case .lineSpark(let c, let a): mix(20 + c.rawValue * 2 + a.rawValue)
                case .stageBurst(let c): mix(40 + c.rawValue)
                case .prism: mix(50)
                case .key(let id): mix(60 + id)
                }
            } else {
                mix(-1)
            }
            switch cell.floor {
            case .plate(let hp)?: mix(100 + hp)
            case .switchPlate(let g, let a)?: mix(200 + g * 2 + (a ? 1 : 0))
            case nil: mix(0)
            }
            switch cell.overlay {
            case .ice(let hp)?: mix(300 + hp)
            case .chain(let hp)?: mix(400 + hp)
            case nil: mix(0)
            }
            switch cell.blocker {
            case .crate(let hp)?: mix(500 + hp)
            case .shutter(let g)?: mix(600 + g)
            case .wall?: mix(700)
            case nil: mix(0)
            }
        }
        return String(h, radix: 16).leftPadded(to: 16)
    }
}

extension String {
    func leftPadded(to length: Int, with pad: Character = "0") -> String {
        count >= length ? self : String(repeating: pad, count: length - count) + self
    }
}
