// Board.swift — поле N×N с mask и слоями клеток, линии и сегменты гравитации.

public struct Board: Hashable, Codable, Sendable {
    public let n: Int
    public var cells: [Cell]

    public init(n: Int, cells: [Cell]) {
        precondition(cells.count == n * n, "cells.count must be n*n")
        self.n = n
        self.cells = cells
    }

    public init(n: Int, mask: (Coord) -> Bool) {
        self.n = n
        var cells: [Cell] = []
        cells.reserveCapacity(n * n)
        for y in 0..<n {
            for x in 0..<n {
                cells.append(Cell(playable: mask(Coord(x, y))))
            }
        }
        self.cells = cells
    }

    @inline(__always) public func index(_ c: Coord) -> Int { c.y * n + c.x }
    @inline(__always) public func coord(_ i: Int) -> Coord { Coord(i % n, i / n) }

    @inline(__always) public func inBounds(_ c: Coord) -> Bool {
        c.x >= 0 && c.y >= 0 && c.x < n && c.y < n
    }

    /// Клетка входит в mask.
    @inline(__always) public func isPlayable(_ c: Coord) -> Bool {
        inBounds(c) && cells[index(c)].playable
    }

    public subscript(_ c: Coord) -> Cell {
        get { cells[index(c)] }
        set { cells[index(c)] = newValue }
    }

    public var allCoords: [Coord] {
        (0..<(n * n)).map { coord($0) }
    }

    public var playableCoords: [Coord] {
        (0..<(n * n)).compactMap { cells[$0].playable ? coord($0) : nil }
    }

    /// Все линии вдоль направления гравитации; каждая линия — индексы клеток от upstream к downstream.
    public func lines(along g: Direction) -> [[Int]] {
        var result: [[Int]] = []
        result.reserveCapacity(n)
        for k in 0..<n {
            var line: [Int] = []
            line.reserveCapacity(n)
            for t in 0..<n {
                let c: Coord
                switch g {
                case .down: c = Coord(k, t)
                case .up: c = Coord(k, n - 1 - t)
                case .right: c = Coord(t, k)
                case .left: c = Coord(n - 1 - t, k)
                }
                line.append(index(c))
            }
            result.append(line)
        }
        return result
    }

    /// Сегменты гравитации: непрерывные участки flow-клеток в каждой линии
    /// (void, wall, crate, closed shutter и закреплённые ice/chain делят линии).
    /// Порядок: линии по индексу, сегменты от upstream к downstream, клетки от upstream к downstream.
    public func segments(along g: Direction) -> [[Int]] {
        var result: [[Int]] = []
        for line in lines(along: g) {
            var current: [Int] = []
            for i in line {
                if cells[i].isFlow {
                    current.append(i)
                } else if !current.isEmpty {
                    result.append(current)
                    current = []
                }
            }
            if !current.isEmpty { result.append(current) }
        }
        return result
    }

    /// Frontier-клетки Curtain Sweep: последняя по направлению падения клетка каждого сегмента.
    public func sweepFrontier(along g: Direction) -> [Int] {
        segments(along: g).map { $0.last! }
    }

    public func occupantIndex(id: Int) -> Int? {
        cells.firstIndex { $0.occupant?.id == id }
    }

    /// Количество оставшихся целевых клеток Velvet Plate (а не сумма HP).
    public var remainingPlateCells: Int {
        cells.reduce(0) { $0 + ($1.plateHP > 0 ? 1 : 0) }
    }

    public var remainingPlateHP: Int {
        cells.reduce(0) { $0 + $1.plateHP }
    }

    public var keyCoords: [(keyID: Int, coord: Coord)] {
        var r: [(Int, Coord)] = []
        for i in 0..<cells.count {
            if let id = cells[i].occupant?.kind.keyID { r.append((id, coord(i))) }
        }
        return r
    }
}
