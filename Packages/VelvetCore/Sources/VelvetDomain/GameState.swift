// GameState.swift — состояние попытки, действия, события и результаты.

public enum RunStatus: String, Codable, Sendable {
    case playing
    case won
    case failed
}

public enum GameActionKind: Hashable, Codable, Sendable {
    case swap(from: Coord, to: Coord)
    case rotate
}

public struct GameAction: Hashable, Codable, Sendable {
    /// Уникальный ActionID предотвращает двойное выполнение.
    public var id: String
    public var kind: GameActionKind
    /// Ожидаемая revision состояния (проверяется при исполнении; nil — не проверять).
    public var expectedRevision: Int?

    public init(id: String, kind: GameActionKind, expectedRevision: Int? = nil) {
        self.id = id
        self.kind = kind
        self.expectedRevision = expectedRevision
    }
}

public struct GameState: Hashable, Codable, Sendable {
    public var levelID: Int
    public var levelVersion: Int
    public var board: Board
    /// Ориентация сцены 0…3.
    public var q: Int
    public var initialMoves: Int
    public var movesLeft: Int
    public var initialCharge: Int
    /// Stage Charge 0…12.
    public var charge: Int
    public var rng: LevelRNG
    public var nextOccupantID: Int
    public var revision: Int
    public var turnsUsed: Int
    /// Собрано по цветам (индекс = GemColor.rawValue).
    public var collected: [Int]
    public var extractedKeyIDs: [Int]
    public var objectives: [ObjectiveDef]
    public var initialKeyIDs: [Int]
    public var exitPorts: [ExitPort]
    public var shutterLinks: [ShutterSwitchLink]
    public var status: RunStatus
    public var recentActionIDs: [String]
    public var specialsCreated: Int
    public var shufflesPerformed: Int

    public static let maxCharge = 12

    public init(levelID: Int, levelVersion: Int, board: Board, q: Int, initialMoves: Int, movesLeft: Int,
                initialCharge: Int, charge: Int, rng: LevelRNG, nextOccupantID: Int, revision: Int, turnsUsed: Int,
                collected: [Int], extractedKeyIDs: [Int], objectives: [ObjectiveDef], initialKeyIDs: [Int],
                exitPorts: [ExitPort], shutterLinks: [ShutterSwitchLink], status: RunStatus, recentActionIDs: [String],
                specialsCreated: Int, shufflesPerformed: Int) {
        self.levelID = levelID
        self.levelVersion = levelVersion
        self.board = board
        self.q = q
        self.initialMoves = initialMoves
        self.movesLeft = movesLeft
        self.initialCharge = initialCharge
        self.charge = charge
        self.rng = rng
        self.nextOccupantID = nextOccupantID
        self.revision = revision
        self.turnsUsed = turnsUsed
        self.collected = collected
        self.extractedKeyIDs = extractedKeyIDs
        self.objectives = objectives
        self.initialKeyIDs = initialKeyIDs
        self.exitPorts = exitPorts
        self.shutterLinks = shutterLinks
        self.status = status
        self.recentActionIDs = recentActionIDs
        self.specialsCreated = specialsCreated
        self.shufflesPerformed = shufflesPerformed
    }

    public var movesUsed: Int { initialMoves - movesLeft }
    public var gravity: Direction { Direction.gravity(forOrientation: q) }
    public var n: Int { board.n }

    public var isTurnAvailable: Bool {
        status == .playing && charge >= GameState.maxCharge && movesLeft > 0
    }

    // MARK: Objectives

    public func remaining(for objective: ObjectiveDef) -> Int {
        switch objective {
        case .collect(let color, let target):
            return max(0, target - collected[color.rawValue])
        case .plates:
            return board.remainingPlateCells
        case .keys:
            return initialKeyIDs.filter { !extractedKeyIDs.contains($0) }.count
        }
    }

    public var allObjectivesComplete: Bool {
        objectives.allSatisfy { remaining(for: $0) == 0 }
    }

    public func activePort(at c: Coord) -> ExitPort? {
        exitPorts.first { $0.x == c.x && $0.y == c.y && $0.direction == gravity }
    }

    public func port(at c: Coord) -> ExitPort? {
        exitPorts.first { $0.x == c.x && $0.y == c.y }
    }
}

// MARK: - Events (для renderer; не изменяют Domain)

public struct PieceMove: Hashable, Codable, Sendable {
    public var id: Int
    public var from: Coord
    public var to: Coord
}

public struct PieceSpawn: Hashable, Codable, Sendable {
    public var occupant: Occupant
    public var at: Coord
    /// Количество клеток «над» точкой появления для анимации падения внутри сегмента.
    public var dropDistance: Int
}

public struct RemovedPiece: Hashable, Codable, Sendable {
    public var occupant: Occupant
    public var at: Coord
}

public enum DamageLayer: String, Hashable, Codable, Sendable {
    case crate, ice, chain, plate
}

public struct DamageEvent: Hashable, Codable, Sendable {
    public var at: Coord
    public var layer: DamageLayer
    public var remainingHP: Int
}

public enum EffectVisual: Hashable, Codable, Sendable {
    case line(origin: Coord, axis: Axis)
    case burst(center: Coord, radius: Int)
    case band(center: Coord)
    case colorClear(origin: Coord, color: GemColor, targets: [Coord])
    case allCells(origin: Coord)
}

public struct MatchedGroup: Hashable, Codable, Sendable {
    public var color: GemColor
    public var cells: [Coord]
    public var chargeGain: Int
}

public struct KeyExtraction: Hashable, Codable, Sendable {
    public var occupantID: Int
    public var keyID: Int
    public var at: Coord
    public var direction: Direction
}

public struct WaveEvent: Hashable, Codable, Sendable {
    public var index: Int
    public var groups: [MatchedGroup] = []
    public var sweepCells: [Coord] = []
    public var effects: [EffectVisual] = []
    public var hitCells: [Coord] = []
    public var removed: [RemovedPiece] = []
    public var damaged: [DamageEvent] = []
    public var created: [RemovedPiece] = []
    public var switchesActivated: [Coord] = []
    public var shuttersOpened: [Coord] = []
    public var chargeGained: Int = 0
}

public enum GameEvent: Hashable, Codable, Sendable {
    case swapped(from: Coord, to: Coord)
    case rotated(fromQ: Int, toQ: Int)
    case keysExtracted([KeyExtraction])
    case wave(WaveEvent)
    case gravity([PieceMove])
    case refill([PieceSpawn])
    case shuffled([PieceMove])
    case turnSuggested
}

/// Шаг разрешения хода: событие и состояние поля ПОСЛЕ него.
public struct ResolutionStep: Hashable, Codable, Sendable {
    public var event: GameEvent
    public var board: Board
    public var q: Int
    public var charge: Int
    public var movesLeft: Int
    public var collected: [Int]
    public var extractedKeyIDs: [Int]
}

public enum ActionOutcome: Hashable, Codable, Sendable {
    case continuePlaying
    case won(stars: Int)
    case failed
}

public struct ActionResult: Sendable {
    public var state: GameState
    public var steps: [ResolutionStep]
    public var outcome: ActionOutcome
    public var wavesResolved: Int
    public var chargeGained: Int
    public var shuffled: Bool
    public var turnSuggested: Bool
}

public enum EngineError: Error, Equatable, Sendable {
    case notPlaying
    case duplicateAction
    case staleRevision
    case invalidSwap(String)
    case turnUnavailable
    case waveLimitExceeded
    case stageDataError(String)
}
