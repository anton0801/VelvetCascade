// Pieces.swift — occupants, floors, overlays и blockers игровой клетки.

/// Пять базовых фишек. Порядок — фиксированный tie-break (Heart, Diamond, Clover, Bell, Star).
public enum GemColor: Int, Codable, CaseIterable, Comparable, Sendable {
    case heart = 0
    case diamond = 1
    case clover = 2
    case bell = 3
    case star = 4

    public static func < (lhs: GemColor, rhs: GemColor) -> Bool { lhs.rawValue < rhs.rawValue }

    public var name: String {
        switch self {
        case .heart: return "Heart"
        case .diamond: return "Diamond"
        case .clover: return "Clover"
        case .bell: return "Bell"
        case .star: return "Star"
        }
    }

    public var letter: String {
        switch self {
        case .heart: return "H"
        case .diamond: return "D"
        case .clover: return "C"
        case .bell: return "B"
        case .star: return "S"
        }
    }

    public init?(letter: String) {
        switch letter.uppercased() {
        case "H": self = .heart
        case "D": self = .diamond
        case "C": self = .clover
        case "B": self = .bell
        case "S": self = .star
        default: return nil
        }
    }
}

/// Локальная ось луча LineSpark.
public enum Axis: Int, Codable, Sendable {
    case horizontal = 0
    case vertical = 1
}

public enum OccupantKind: Hashable, Codable, Sendable {
    case gem(GemColor)
    case lineSpark(GemColor, Axis)
    case stageBurst(GemColor)
    case prism
    case key(Int)

    /// Цвет для совпадений и целей. Prism и Key цвета не имеют.
    public var baseColor: GemColor? {
        switch self {
        case .gem(let c), .lineSpark(let c, _), .stageBurst(let c): return c
        case .prism, .key: return nil
        }
    }

    public var isSpecial: Bool {
        switch self {
        case .lineSpark, .stageBurst, .prism: return true
        case .gem, .key: return false
        }
    }

    public var isKey: Bool {
        if case .key = self { return true }
        return false
    }

    public var keyID: Int? {
        if case .key(let id) = self { return id }
        return nil
    }

    public var isOrdinaryGem: Bool {
        if case .gem = self { return true }
        return false
    }

    /// Фиксированный порядок эффектов для устойчивой очереди активаций.
    var effectOrder: Int {
        switch self {
        case .lineSpark: return 0
        case .stageBurst: return 1
        case .prism: return 2
        case .gem: return 3
        case .key: return 4
        }
    }
}

public struct Occupant: Hashable, Codable, Sendable {
    /// Устойчивый идентификатор: сохраняется при падении, новый refill/special получает новый ID.
    public var id: Int
    public var kind: OccupantKind

    public init(id: Int, kind: OccupantKind) {
        self.id = id
        self.kind = kind
    }
}

/// Покрытие пола.
public enum Floor: Hashable, Codable, Sendable {
    /// Velvet Plate HP1–2.
    case plate(hp: Int)
    /// Switch Plate: group — индекс группы створок (A=0, B=1, C=2); active — включена до конца попытки.
    case switchPlate(group: Int, active: Bool)
}

/// Overlay закрепляет gem и запрещает swap.
public enum Overlay: Hashable, Codable, Sendable {
    case ice(hp: Int)
    case chain(hp: Int)

    public var hp: Int {
        switch self {
        case .ice(let hp), .chain(let hp): return hp
        }
    }
}

/// Блокирующее состояние клетки (без спрятанного под ним gem).
public enum Blocker: Hashable, Codable, Sendable {
    case crate(hp: Int)
    case shutter(group: Int)
    case wall
}

public struct Cell: Hashable, Codable, Sendable {
    /// Клетка принадлежит mask.
    public var playable: Bool
    public var occupant: Occupant?
    public var floor: Floor?
    public var overlay: Overlay?
    public var blocker: Blocker?

    public init(playable: Bool, occupant: Occupant? = nil, floor: Floor? = nil,
                overlay: Overlay? = nil, blocker: Blocker? = nil) {
        self.playable = playable
        self.occupant = occupant
        self.floor = floor
        self.overlay = overlay
        self.blocker = blocker
    }

    public static let void = Cell(playable: false)

    /// Клетка, по которой перемещаются подвижные occupants (участвует в сегментах гравитации).
    @inline(__always) public var isFlow: Bool {
        playable && blocker == nil && overlay == nil
    }

    /// Закреплённый occupant (ice/chain).
    @inline(__always) public var isPinned: Bool { overlay != nil }

    /// Можно ли переставить этот occupant рукой.
    public var isSwappable: Bool {
        guard playable, blocker == nil, overlay == nil, let occ = occupant else { return false }
        return !occ.kind.isKey
    }

    public var plateHP: Int {
        if case .plate(let hp)? = floor { return hp }
        return 0
    }
}
