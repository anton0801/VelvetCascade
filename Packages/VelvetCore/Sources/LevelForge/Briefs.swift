// Briefs.swift — разбор 180 level briefs (docs/spec/LEVEL_BRIEFS.csv).

import Foundation
import VelvetDomain

struct KeySpec: Hashable {
    var direction: Direction
}

struct Brief {
    var id: Int
    var worldID: Int
    var worldName: String
    var title: String
    var shape: String
    var moves: Int
    var charge: Int
    var objectivesRaw: String
    var obstaclesRaw: String
    var turnBrief: String
    var designFocus: String

    // Разобранные цели
    var collect: [(GemColor, Int)] = []
    var platesHP1 = 0
    var platesHP2 = 0
    var keys: [KeySpec] = []

    // Разобранные препятствия
    var crates1 = 0, crates2 = 0
    var ice1 = 0, ice2 = 0
    var chains = 0
    var walls = 0
    var shutterCells = 0, switchCells = 0

    var plannedTurns: Int {
        Int(turnBrief.filter { $0.isNumber }) ?? 0
    }
    var turnsRequired: Bool { turnBrief.contains("!") }
    var tutorialTurn: Bool { turnBrief.contains("*") }
    var hasPlates: Bool { platesHP1 + platesHP2 > 0 }
}

enum BriefParser {
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n":
                    row.append(field); field = ""
                    if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                    row = []
                case "\r": break
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func load(path: String) throws -> [Brief] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let rows = parseCSV(text)
        guard let header = rows.first else { return [] }
        func idx(_ name: String) -> Int { header.firstIndex(of: name)! }
        var briefs: [Brief] = []
        for r in rows.dropFirst() where r.count >= header.count {
            var b = Brief(id: Int(r[idx("level_id")])!, worldID: Int(r[idx("world_id")])!,
                          worldName: r[idx("world_name")], title: r[idx("title")], shape: r[idx("shape")],
                          moves: Int(r[idx("initial_moves")])!, charge: Int(r[idx("initial_charge")])!,
                          objectivesRaw: r[idx("objectives")], obstaclesRaw: r[idx("obstacles")],
                          turnBrief: r[idx("turn_brief")], designFocus: r[idx("design_focus")])
            parseObjectives(&b)
            parseObstacles(&b)
            briefs.append(b)
        }
        return briefs.sorted { $0.id < $1.id }
    }

    static func directions(_ letters: String, count: Int) -> [Direction] {
        let ds: [Direction] = letters.compactMap {
            switch $0 {
            case "R": return .right
            case "U": return .up
            case "L": return .left
            case "D": return .down
            default: return nil
            }
        }
        // Перечисленные направления по одному, остаток повторяет первое (K3RU → R, R, U).
        var result = ds
        while result.count < count { result.append(ds[0]) }
        return Array(result.prefix(count)).sorted { $0.rawValue < $1.rawValue }
    }

    static func parseObjectives(_ b: inout Brief) {
        for tok in b.objectivesRaw.split(separator: "+").map(String.init) {
            let t = tok.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("K") {
                let digits = t.dropFirst().prefix { $0.isNumber }
                let count = Int(digits) ?? 1
                let letters = String(t.dropFirst(1 + digits.count))
                b.keys = directions(letters, count: count).map { KeySpec(direction: $0) }
            } else if t.hasPrefix("V") {
                let parts = t.dropFirst().split(separator: "/").compactMap { Int($0) }
                b.platesHP1 = parts.first ?? 0
                b.platesHP2 = parts.count > 1 ? parts[1] : 0
            } else if let color = GemColor(letter: String(t.prefix(1))), let n = Int(t.dropFirst()) {
                b.collect.append((color, n))
            }
        }
    }

    static func parseObstacles(_ b: inout Brief) {
        let raw = b.obstaclesRaw.trimmingCharacters(in: .whitespaces)
        guard raw != "—" && raw != "-" && !raw.isEmpty else { return }
        for tok in raw.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            func pair(_ prefix: String) -> (Int, Int) {
                let parts = tok.dropFirst(prefix.count).split(separator: "/").compactMap { Int($0) }
                return (parts.first ?? 0, parts.count > 1 ? parts[1] : 0)
            }
            if tok.hasPrefix("Cr") { let p = pair("Cr"); b.crates1 = p.0; b.crates2 = p.1 }
            else if tok.hasPrefix("Ic") { let p = pair("Ic"); b.ice1 = p.0; b.ice2 = p.1 }
            else if tok.hasPrefix("Ch") { b.chains = pair("Ch").0 }
            else if tok.hasPrefix("Sh") { let p = pair("Sh"); b.shutterCells = p.0; b.switchCells = p.1 }
            else if tok.hasPrefix("W") { b.walls = pair("W").0 }
        }
    }
}
