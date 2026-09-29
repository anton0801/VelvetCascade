// Geometry.swift — локальные координаты поля, поворот сцены и направление гравитации.
//
// Модель хранит поле в локальных координатах (x вправо, y вниз). Поворот сцены по
// часовой стрелке НЕ переписывает координаты: renderer применяет R(x, y) = (N−1−y, x)
// ровно q раз, а локальная гравитация меняется Down → Right → Up → Left.

public struct Coord: Hashable, Codable, Comparable, CustomStringConvertible, Sendable {
    public var x: Int
    public var y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// Row-major порядок (y, x) — используется для детерминированных очередей.
    public static func < (lhs: Coord, rhs: Coord) -> Bool {
        lhs.y != rhs.y ? lhs.y < rhs.y : lhs.x < rhs.x
    }

    public func offset(_ d: Direction) -> Coord {
        let v = d.vector
        return Coord(x + v.dx, y + v.dy)
    }

    public func isOrthogonalNeighbor(of other: Coord) -> Bool {
        abs(x - other.x) + abs(y - other.y) == 1
    }

    public var description: String { "(\(x),\(y))" }
}

/// Локальное направление на поле.
public enum Direction: Int, Codable, CaseIterable, Sendable {
    case down = 0
    case right = 1
    case up = 2
    case left = 3

    public var vector: (dx: Int, dy: Int) {
        switch self {
        case .down: return (0, 1)
        case .right: return (1, 0)
        case .up: return (0, -1)
        case .left: return (-1, 0)
        }
    }

    public var opposite: Direction {
        switch self {
        case .down: return .up
        case .up: return .down
        case .left: return .right
        case .right: return .left
        }
    }

    public var isVertical: Bool { self == .down || self == .up }

    /// Локальная гравитация для ориентации q (0…3).
    public static func gravity(forOrientation q: Int) -> Direction {
        Direction(rawValue: ((q % 4) + 4) % 4)!
    }

    /// Минимальное число поворотов по часовой стрелке от q=0, после которых локальная
    /// гравитация совпадает с этим направлением (Down=0, Right=1, Up=2, Left=3).
    public var clockwiseTurnsFromRest: Int { rawValue }

    public var label: String {
        switch self {
        case .down: return "Down"
        case .right: return "Right"
        case .up: return "Up"
        case .left: return "Left"
        }
    }
}

/// Преобразование локальных координат в экранные для ориентации q.
public enum BoardTransform {
    /// Один поворот по часовой стрелке: R(x, y) = (N−1−y, x).
    public static func rotateOnce(_ c: Coord, n: Int) -> Coord {
        Coord(n - 1 - c.y, c.x)
    }

    /// Обратный поворот: R⁻¹(x, y) = (y, N−1−x).
    public static func inverseRotateOnce(_ c: Coord, n: Int) -> Coord {
        Coord(c.y, n - 1 - c.x)
    }

    /// Локальная клетка → экранная клетка при ориентации q.
    public static func toScreen(_ c: Coord, q: Int, n: Int) -> Coord {
        var r = c
        for _ in 0..<(((q % 4) + 4) % 4) { r = rotateOnce(r, n: n) }
        return r
    }

    /// Экранная клетка → локальная клетка (inverseR) — для hit testing.
    public static func toLocal(_ c: Coord, q: Int, n: Int) -> Coord {
        var r = c
        for _ in 0..<(((q % 4) + 4) % 4) { r = inverseRotateOnce(r, n: n) }
        return r
    }

    /// Экранное направление → локальное (для swipe). Направление поворачивается как вектор.
    public static func localDirection(fromScreen d: Direction, q: Int) -> Direction {
        // Поворот вектора по часовой стрелке D(dx,dy)=(−dy,dx) переводит локальное в экранное:
        // right→down, down→left, left→up, up→right — в порядке enum это индекс −1.
        // Обратное преобразование D⁻¹ — индекс +1 за каждый поворот.
        Direction(rawValue: (((d.rawValue + q) % 4) + 4) % 4)!
    }

    /// Локальное направление → экранное.
    public static func screenDirection(fromLocal d: Direction, q: Int) -> Direction {
        Direction(rawValue: (((d.rawValue - q) % 4) + 4) % 4)!
    }
}
