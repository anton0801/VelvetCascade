// MatchResolver.swift — поиск runs и connected match groups, выбор special.

public enum SpecialKind: Hashable, Sendable {
    case lineSpark(Axis)
    case stageBurst
    case prism
}

public struct MatchGroupInfo: Hashable, Sendable {
    public var color: GemColor
    /// Индексы клеток группы, отсортированы row-major.
    public var cells: [Int]
    public var maxRun: Int
    public var hasHorizontal: Bool
    public var hasVertical: Bool
    /// Ось самого длинного run (для LineSpark).
    public var longestAxis: Axis

    public var size: Int { cells.count }

    /// Run3 — нет; Run4 — LineSpark; T/L ≥5 без straight5 — Burst; straight ≥5 — Prism (приоритет).
    public var special: SpecialKind? {
        if maxRun >= 5 { return .prism }
        if hasHorizontal && hasVertical { return .stageBurst }
        if maxRun == 4 { return .lineSpark(longestAxis) }
        return nil
    }
}

public enum ChargePolicy {
    public static let perSwapCap = 6
    public static let perTurnCap = 4

    /// Размер группы 3→1, 4→3, ≥5→5.
    public static func gain(forGroupSize size: Int) -> Int {
        if size >= 5 { return 5 }
        if size == 4 { return 3 }
        if size == 3 { return 1 }
        return 0
    }
}

public enum MatchResolver {
    /// Цвет клетки для совпадений: -1, если цвета нет.
    @inline(__always)
    static func colorCode(_ cell: Cell) -> Int {
        guard cell.playable, cell.blocker == nil, let occ = cell.occupant, let c = occ.kind.baseColor else { return -1 }
        return c.rawValue
    }

    public static func colorGrid(_ board: Board) -> [Int] {
        board.cells.map { colorCode($0) }
    }

    /// Все connected groups (объединение пересекающихся runs одного цвета), отсортированы по первой клетке.
    public static func findGroups(_ board: Board) -> [MatchGroupInfo] {
        let n = board.n
        let colors = colorGrid(board)
        struct Run { var cells: [Int]; var horizontal: Bool }
        var runs: [Run] = []

        for y in 0..<n {
            var x = 0
            while x < n {
                let c = colors[y * n + x]
                if c < 0 { x += 1; continue }
                var e = x + 1
                while e < n && colors[y * n + e] == c { e += 1 }
                if e - x >= 3 { runs.append(Run(cells: (x..<e).map { y * n + $0 }, horizontal: true)) }
                x = e
            }
        }
        for x in 0..<n {
            var y = 0
            while y < n {
                let c = colors[y * n + x]
                if c < 0 { y += 1; continue }
                var e = y + 1
                while e < n && colors[e * n + x] == c { e += 1 }
                if e - y >= 3 { runs.append(Run(cells: (y..<e).map { $0 * n + x }, horizontal: false)) }
                y = e
            }
        }
        if runs.isEmpty { return [] }

        // Union-find по runs: runs, делящие клетку, объединяются (цвет у общей клетки один).
        var parent = Array(0..<runs.count)
        func find(_ a: Int) -> Int {
            var a = a
            while parent[a] != a { parent[a] = parent[parent[a]]; a = parent[a] }
            return a
        }
        var owner = [Int](repeating: -1, count: n * n)
        for (ri, run) in runs.enumerated() {
            for cell in run.cells {
                if owner[cell] >= 0 {
                    let a = find(owner[cell]), b = find(ri)
                    if a != b { parent[b] = a }
                } else {
                    owner[cell] = ri
                }
            }
        }
        var byRoot: [Int: [Int]] = [:]
        for ri in 0..<runs.count { byRoot[find(ri), default: []].append(ri) }

        var groups: [MatchGroupInfo] = []
        for (_, runIdx) in byRoot {
            var cellSet = Set<Int>()
            var maxRun = 0
            var hasH = false, hasV = false
            var longestAxis: Axis = .horizontal
            for ri in runIdx {
                let r = runs[ri]
                cellSet.formUnion(r.cells)
                if r.horizontal { hasH = true } else { hasV = true }
                if r.cells.count > maxRun {
                    maxRun = r.cells.count
                    longestAxis = r.horizontal ? .horizontal : .vertical
                }
            }
            let sorted = cellSet.sorted()
            let color = GemColor(rawValue: colors[sorted[0]])!
            groups.append(MatchGroupInfo(color: color, cells: sorted, maxRun: maxRun,
                                         hasHorizontal: hasH, hasVertical: hasV, longestAxis: longestAxis))
        }
        groups.sort { $0.cells[0] < $1.cells[0] }
        return groups
    }

    /// Создаёт ли обмен двух обычных фишек run ≥3 (быстрая локальная проверка).
    public static func swapCreatesMatch(_ colors: [Int], n: Int, _ a: Int, _ b: Int) -> Bool {
        var colors = colors
        colors.swapAt(a, b)
        return hasRunThrough(colors, n: n, a) || hasRunThrough(colors, n: n, b)
    }

    @inline(__always)
    static func hasRunThrough(_ colors: [Int], n: Int, _ i: Int) -> Bool {
        let c = colors[i]
        if c < 0 { return false }
        let x = i % n, y = i / n
        var cnt = 1
        var t = x - 1
        while t >= 0 && colors[y * n + t] == c { cnt += 1; t -= 1 }
        t = x + 1
        while t < n && colors[y * n + t] == c { cnt += 1; t += 1 }
        if cnt >= 3 { return true }
        cnt = 1
        t = y - 1
        while t >= 0 && colors[t * n + x] == c { cnt += 1; t -= 1 }
        t = y + 1
        while t < n && colors[t * n + x] == c { cnt += 1; t += 1 }
        return cnt >= 3
    }

    public static func hasAnyMatch(_ board: Board) -> Bool {
        let n = board.n
        let colors = colorGrid(board)
        for i in 0..<(n * n) where colors[i] >= 0 {
            let x = i % n, y = i / n
            if x + 2 < n && colors[i + 1] == colors[i] && colors[i + 2] == colors[i] { return true }
            if y + 2 < n && colors[i + n] == colors[i] && colors[i + 2 * n] == colors[i] { return true }
        }
        return false
    }
}
