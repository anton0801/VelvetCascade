// Level.swift — контракт LevelDefinition (bundle JSON) и его части.

import Foundation

public struct ExitPort: Hashable, Codable, Sendable {
    public var x: Int
    public var y: Int
    /// Внешнее локальное направление: сосед по нему лежит вне mask.
    public var direction: Direction
    /// Ключ, для которого предназначен выход (brief: «отдельный порт на ключ»); nil — любой ключ.
    public var keyID: Int?

    public init(x: Int, y: Int, direction: Direction, keyID: Int? = nil) {
        self.x = x
        self.y = y
        self.direction = direction
        self.keyID = keyID
    }

    public var coord: Coord { Coord(x, y) }

    public func accepts(keyID id: Int) -> Bool { keyID == nil || keyID == id }
}

public struct ShutterSwitchLink: Hashable, Codable, Sendable {
    /// Индекс группы (A=0, B=1, C=2) — отображается glyph в ромбовидном badge.
    public var group: Int
    public var switches: [Coord]
    public var shutters: [Coord]

    public init(group: Int, switches: [Coord], shutters: [Coord]) {
        self.group = group
        self.switches = switches
        self.shutters = shutters
    }

    public static func glyph(for group: Int) -> String {
        ["A", "B", "C", "D", "E"][max(0, min(4, group))]
    }
}

public enum ObjectiveDef: Hashable, Codable, Sendable {
    case collect(color: GemColor, target: Int)
    case plates
    case keys

    private enum CodingKeys: String, CodingKey { case type, color, target }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "collect":
            let color = try c.decode(GemColor.self, forKey: .color)
            let target = try c.decode(Int.self, forKey: .target)
            self = .collect(color: color, target: target)
        case "plates": self = .plates
        case "keys": self = .keys
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown objective \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .collect(let color, let target):
            try c.encode("collect", forKey: .type)
            try c.encode(color, forKey: .color)
            try c.encode(target, forKey: .target)
        case .plates: try c.encode("plates", forKey: .type)
        case .keys: try c.encode("keys", forKey: .type)
        }
    }

    public var typeKey: String {
        switch self {
        case .collect: return "collect"
        case .plates: return "plates"
        case .keys: return "keys"
        }
    }
}

/// Размещение стартового occupant.
public struct OccupantPlacement: Hashable, Codable, Sendable {
    public var x: Int
    public var y: Int
    /// "gem" | "key" | "lineSpark" | "stageBurst" | "prism"
    public var type: String
    public var color: GemColor?
    public var keyID: Int?
    public var axis: Axis?

    public init(x: Int, y: Int, type: String, color: GemColor? = nil, keyID: Int? = nil, axis: Axis? = nil) {
        self.x = x
        self.y = y
        self.type = type
        self.color = color
        self.keyID = keyID
        self.axis = axis
    }

    public var coord: Coord { Coord(x, y) }

    public func kind() -> OccupantKind? {
        switch type {
        case "gem": return color.map { .gem($0) }
        case "key": return keyID.map { .key($0) }
        case "lineSpark":
            guard let color, let axis else { return nil }
            return .lineSpark(color, axis)
        case "stageBurst": return color.map { .stageBurst($0) }
        case "prism": return .prism
        default: return nil
        }
    }

    public static func from(_ kind: OccupantKind, at c: Coord) -> OccupantPlacement {
        switch kind {
        case .gem(let col): return OccupantPlacement(x: c.x, y: c.y, type: "gem", color: col)
        case .key(let id): return OccupantPlacement(x: c.x, y: c.y, type: "key", keyID: id)
        case .lineSpark(let col, let ax): return OccupantPlacement(x: c.x, y: c.y, type: "lineSpark", color: col, axis: ax)
        case .stageBurst(let col): return OccupantPlacement(x: c.x, y: c.y, type: "stageBurst", color: col)
        case .prism: return OccupantPlacement(x: c.x, y: c.y, type: "prism")
        }
    }
}

public struct FloorPlacement: Hashable, Codable, Sendable {
    public var x: Int
    public var y: Int
    /// "plate" | "switch"
    public var type: String
    public var hp: Int?
    public var group: Int?

    public init(x: Int, y: Int, type: String, hp: Int? = nil, group: Int? = nil) {
        self.x = x
        self.y = y
        self.type = type
        self.hp = hp
        self.group = group
    }

    public var coord: Coord { Coord(x, y) }
}

public struct OverlayPlacement: Hashable, Codable, Sendable {
    public var x: Int
    public var y: Int
    /// "ice" | "chain"
    public var type: String
    public var hp: Int

    public init(x: Int, y: Int, type: String, hp: Int) {
        self.x = x
        self.y = y
        self.type = type
        self.hp = hp
    }

    public var coord: Coord { Coord(x, y) }
}

public struct BlockerPlacement: Hashable, Codable, Sendable {
    public var x: Int
    public var y: Int
    /// "crate" | "wall" | "shutter"
    public var type: String
    public var hp: Int?
    public var group: Int?

    public init(x: Int, y: Int, type: String, hp: Int? = nil, group: Int? = nil) {
        self.x = x
        self.y = y
        self.type = type
        self.hp = hp
        self.group = group
    }

    public var coord: Coord { Coord(x, y) }
}

/// Шаг эталонного решения: Swap(from,to) или Rotate с ожидаемым hash settled-состояния.
public struct TraceAction: Hashable, Codable, Sendable {
    /// "swap" | "rotate"
    public var action: String
    public var from: Coord?
    public var to: Coord?
    public var hash: String

    public init(action: String, from: Coord? = nil, to: Coord? = nil, hash: String) {
        self.action = action
        self.from = from
        self.to = to
        self.hash = hash
    }

    public var gameAction: GameActionKind? {
        switch action {
        case "rotate": return .rotate
        case "swap":
            guard let from, let to else { return nil }
            return .swap(from: from, to: to)
        default: return nil
        }
    }
}

/// Обучающая подсказка внутри уровня.
public struct TutorialStep: Hashable, Codable, Sendable {
    /// "start" | "chargeFull" | "afterTurn" | "specialCreated" | "keyNearPort" | "fewMoves"
    public var trigger: String
    public var title: String
    public var text: String
    /// Клетки для подсветки (локальные), необязательно.
    public var highlight: [Coord]?

    public init(trigger: String, title: String, text: String, highlight: [Coord]? = nil) {
        self.trigger = trigger
        self.title = title
        self.text = text
        self.highlight = highlight
    }
}

public struct LevelDefinition: Hashable, Codable, Sendable {
    public var id: Int
    public var campaignVersion: Int
    public var worldID: Int
    public var levelVersion: Int
    public var title: String
    /// Код формы из brief: S6, S8, C7, C8, X7, D7, U8, T8, R8.
    public var shape: String
    public var n: Int
    /// N строк из '1'/'0'.
    public var mask: [String]
    public var initialOrientation: Int
    public var initialMoves: Int
    public var initialCharge: Int
    public var fiveColorPalette: [GemColor]
    public var initialOccupants: [OccupantPlacement]
    public var floors: [FloorPlacement]
    public var overlays: [OverlayPlacement]
    public var blockers: [BlockerPlacement]
    public var exitPorts: [ExitPort]
    public var shutterSwitchLinks: [ShutterSwitchLink]
    public var objectives: [ObjectiveDef]
    public var rngAlgorithmVersion: Int
    public var seed: UInt64
    public var tutorialSteps: [TutorialStep]
    public var solutionTrace: [TraceAction]
    public var authoredDifficulty: Int
    public var playtestStatus: String
    /// Brief-обозначение поворотов: "0", "1", "2!", "1*" …
    public var turnBrief: String
    /// Геометрический минимум clockwise Turn для выходов (0, если выходов нет).
    public var requiredTurns: Int
    /// Новая механика для Level Brief ("Ice", "Keys & Exits"…), если уровень её вводит.
    public var newMechanic: String?
    /// Handbook-тема новой механики.
    public var newMechanicTopic: String?

    public init(id: Int, campaignVersion: Int, worldID: Int, levelVersion: Int, title: String, shape: String,
                n: Int, mask: [String], initialOrientation: Int, initialMoves: Int, initialCharge: Int,
                fiveColorPalette: [GemColor], initialOccupants: [OccupantPlacement], floors: [FloorPlacement],
                overlays: [OverlayPlacement], blockers: [BlockerPlacement], exitPorts: [ExitPort],
                shutterSwitchLinks: [ShutterSwitchLink], objectives: [ObjectiveDef], rngAlgorithmVersion: Int,
                seed: UInt64, tutorialSteps: [TutorialStep], solutionTrace: [TraceAction], authoredDifficulty: Int,
                playtestStatus: String, turnBrief: String, requiredTurns: Int, newMechanic: String?,
                newMechanicTopic: String?) {
        self.id = id
        self.campaignVersion = campaignVersion
        self.worldID = worldID
        self.levelVersion = levelVersion
        self.title = title
        self.shape = shape
        self.n = n
        self.mask = mask
        self.initialOrientation = initialOrientation
        self.initialMoves = initialMoves
        self.initialCharge = initialCharge
        self.fiveColorPalette = fiveColorPalette
        self.initialOccupants = initialOccupants
        self.floors = floors
        self.overlays = overlays
        self.blockers = blockers
        self.exitPorts = exitPorts
        self.shutterSwitchLinks = shutterSwitchLinks
        self.objectives = objectives
        self.rngAlgorithmVersion = rngAlgorithmVersion
        self.seed = seed
        self.tutorialSteps = tutorialSteps
        self.solutionTrace = solutionTrace
        self.authoredDifficulty = authoredDifficulty
        self.playtestStatus = playtestStatus
        self.turnBrief = turnBrief
        self.requiredTurns = requiredTurns
        self.newMechanic = newMechanic
        self.newMechanicTopic = newMechanicTopic
    }

    public func maskContains(_ c: Coord) -> Bool {
        guard c.y >= 0, c.y < mask.count, c.x >= 0 else { return false }
        let row = Array(mask[c.y])
        guard c.x < row.count else { return false }
        return row[c.x] == "1"
    }

    public var initialKeyIDs: [Int] {
        initialOccupants.compactMap { $0.type == "key" ? $0.keyID : nil }.sorted()
    }
}

/// Стандартные формы кампании — определяются координатами, не картинкой.
public enum ShapeCatalog {
    public static func size(of shape: String) -> Int {
        switch shape {
        case "S6": return 6
        case "C7", "X7", "D7": return 7
        default: return 8
        }
    }

    public static func contains(shape: String, _ c: Coord) -> Bool {
        let n = size(of: shape)
        guard c.x >= 0, c.y >= 0, c.x < n, c.y < n else { return false }
        let x = c.x, y = c.y
        switch shape {
        case "S6", "S8":
            return true
        case "C7", "C8":
            // Corner Cut: убрать верхние правые 2×2 и нижние левые 2×2.
            if x >= n - 2 && y <= 1 { return false }
            if x <= 1 && y >= n - 2 { return false }
            return true
        case "X7":
            return (2...4).contains(x) || (2...4).contains(y)
        case "D7":
            return abs(x - 3) + abs(y - 3) <= 4
        case "U8":
            return x <= 1 || x >= 6 || y >= 5
        case "T8":
            return x <= 2 || x >= 5 || (3...4).contains(y)
        case "R8":
            return !((3...4).contains(x) && (3...4).contains(y))
        default:
            return false
        }
    }

    public static func maskRows(shape: String) -> [String] {
        let n = size(of: shape)
        return (0..<n).map { y in
            String((0..<n).map { x in contains(shape: shape, Coord(x, y)) ? Character("1") : Character("0") })
        }
    }
}
