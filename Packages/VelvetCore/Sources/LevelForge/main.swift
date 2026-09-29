// LevelForge — генерация, решение, валидация и отчёт по 180 уровням Velvet Cascade.
//
//   swift run -c release LevelForge build  --root <repo> [--levels 1-180] [--jobs N]
//   swift run -c release LevelForge verify --root <repo>
//
// build: для каждого brief строит раскладку, ищет решение beam-search солвером на Domain-движке,
// измеряет процент побед бота без подглядывания в refill, при необходимости корректирует ходы
// (каждое изменение логируется) и пишет VelvetCascade/Resources/Levels/level_XXX.json.
// verify: структурная валидация + воспроизведение solutionTrace всех JSON с проверкой hash.

import Foundation
import VelvetDomain

struct ForgeRecord: Codable {
    var id: Int
    var title: String
    var world: Int
    var shape: String
    var briefMoves: Int
    var finalMoves: Int
    var targetScale: Double
    var attemptUsed: Int
    var attemptsTried: Int
    var solutionLength: Int
    var solutionTurns: Int
    var solverStars: Int
    var requiredTurns: Int
    var turnBrief: String
    var botWinRate: Double
    var botAvgMovesOnWin: Double
    var adjustments: [String]
    var status: String
    var seconds: Double
}

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

func parseRange(_ s: String?) -> [Int] {
    guard let s else { return Array(1...180) }
    var r: [Int] = []
    for part in s.split(separator: ",") {
        let b = part.split(separator: "-").compactMap { Int($0) }
        if b.count == 2 { r += Array(b[0]...b[1]) } else if let v = b.first { r.append(v) }
    }
    return r
}

/// Целевой диапазон процента побед бота (мир → сложнее; спокойные слоты 1/11/17 — легче; 20 — финал).
func targetBand(_ brief: Brief) -> (lo: Double, hi: Double) {
    let slot = (brief.id - 1) % 20 + 1
    let base: [Int: (Double, Double)] = [1: (0.80, 1.0), 2: (0.66, 0.92), 3: (0.62, 0.9), 4: (0.58, 0.88),
                                         5: (0.54, 0.86), 6: (0.52, 0.85), 7: (0.48, 0.82), 8: (0.46, 0.8),
                                         9: (0.42, 0.78)]
    var (lo, hi) = base[brief.worldID] ?? (0.5, 0.85)
    if [1, 11, 17].contains(slot) { lo = min(0.9, lo + 0.15); hi = 1.0 }
    if slot == 20 { lo -= 0.1; hi -= 0.08 }
    if brief.worldID == 1 && slot <= 5 { lo = 0.9; hi = 1.0 }
    return (lo, hi)
}

func encoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return e
}

func solveBudget(_ brief: Brief) -> (width: Int, seconds: Double) {
    brief.keys.isEmpty ? (40, 25) : (64, 45)
}

struct Candidate {
    var notes: [String] = []
    var layout: Layout
    var occupants: [OccupantPlacement]
    var def: LevelDefinition
    var sol: SolveResult
    var attempt: Int
    var options: LayoutOptions
}

func trySolve(_ def: LevelDefinition, _ brief: Brief) -> SolveResult? {
    let b = solveBudget(brief)
    return Solver.solve(def, width: b.width, deadline: Date().addingTimeInterval(b.seconds))
}

func findCandidates(_ brief: Brief, options base: LayoutOptions, adjustments: inout [String], tried: inout Int, limit: Int) -> [Candidate] {
    var found: [Candidate] = []
    for countScale in [base.countScale, base.countScale * 0.85, base.countScale * 0.7] {
        var opts = base
        opts.countScale = countScale
        for attempt in 0..<10 {
            if found.count >= limit { break }
            tried += 1
            guard let (layout, occ) = Layout.build(brief: brief, attempt: attempt, options: opts) else { continue }
            for factor in [1.0, 1.15, 1.3] {
                let moves = Int((Double(opts.movesOverride ?? brief.moves) * factor).rounded(.up))
                let def = layout.makeDefinition(occ, moves: moves, targetScale: opts.targetScale)
                guard LevelValidator.validate(def).isEmpty else { break }
                if let sol = trySolve(def, brief) {
                    var o = opts
                    o.movesOverride = moves
                    var c = Candidate(layout: layout, occupants: occ, def: def, sol: sol, attempt: attempt, options: o)
                    c.notes = []
                    if countScale < base.countScale - 0.001 {
                        c.notes.append("obstacle/plate counts ×\(countScale): brief quantities do not fit the \(brief.shape) mask together with keys/exits (placement failed at full count)")
                    }
                    if factor > 1.0 {
                        c.notes.append("moves \(opts.movesOverride ?? brief.moves)→\(moves): solver found no solution with the brief budget on this layout")
                    }
                    found.append(c)
                    break
                }
            }
        }
        if !found.isEmpty { break }
    }
    return found
}

func findCandidate(_ brief: Brief, options base: LayoutOptions, adjustments: inout [String], tried: inout Int) -> Candidate? {
    guard let c = findCandidates(brief, options: base, adjustments: &adjustments, tried: &tried, limit: 1).first else { return nil }
    adjustments += c.notes
    return c
}

func forge(_ brief: Brief, levelsDir: URL) -> ForgeRecord {
    let t0 = Date()
    var adjustments: [String] = []
    var tried = 0
    let band = targetBand(brief)
    func failed(_ why: String) -> ForgeRecord {
        ForgeRecord(id: brief.id, title: brief.title, world: brief.worldID, shape: brief.shape,
                    briefMoves: brief.moves, finalMoves: 0, targetScale: 1, attemptUsed: -1,
                    attemptsTried: tried, solutionLength: 0, solutionTurns: 0, solverStars: 0,
                    requiredTurns: 0, turnBrief: brief.turnBrief, botWinRate: 0, botAvgMovesOnWin: 0,
                    adjustments: adjustments + ["FAILED: \(why)"], status: "failed",
                    seconds: Date().timeIntervalSince(t0))
    }
    // Несколько решаемых раскладок; выбрать ближайшую к целевому диапазону сложности.
    let pool = findCandidates(brief, options: LayoutOptions(), adjustments: &adjustments, tried: &tried, limit: 4)
    guard !pool.isEmpty else { return failed("no solvable layout found") }
    let mid = (band.lo + band.hi) / 2
    var scored: [(Candidate, (rate: Double, avgMovesOnWin: Double))] = []
    for c in pool {
        let r = Solver.botWinRate(c.def, runs: 24)
        scored.append((c, r))
        if r.rate >= band.lo && r.rate <= band.hi { break }
    }
    scored.sort { abs($0.1.rate - mid) < abs($1.1.rate - mid) }
    var cand = scored[0].0
    var bot = scored[0].1
    adjustments += cand.notes
    let hasCollect = !brief.collect.isEmpty
    let hasKeys = !brief.keys.isEmpty
    // Балансировка: сложность поднимается целями/дистанцией ключа, ходы — вторичный рычаг.
    for _ in 0..<9 {
        if bot.rate >= band.lo - 0.04 && bot.rate <= band.hi + 0.04 { break }
        var opts = cand.options
        var why = ""
        let moves = opts.movesOverride ?? brief.moves
        if bot.rate > band.hi {
            if hasCollect && opts.targetScale < 1.7 {
                opts.targetScale = min(1.7, opts.targetScale * 1.2)
                why = "targets ×\(String(format: "%.2f", opts.targetScale))"
            } else if hasKeys && opts.distanceBoost < 2 {
                opts.distanceBoost += 1
                why = "key distance +\(opts.distanceBoost)"
            } else if brief.hasPlates && opts.plateSpread < 2 {
                opts.plateSpread += 1
                why = "plates moved toward the edges (spread \(opts.plateSpread))"
            } else if brief.platesHP1 > 0 && opts.plateHardening < 1.0 {
                opts.plateHardening = min(1.0, opts.plateHardening + 0.5)
                why = "\(Int(opts.plateHardening * 100))% of HP1 plates made HP2"
            } else if Double(moves) > Double(brief.moves) * 0.8 {
                opts.movesOverride = max(Int(Double(brief.moves) * 0.8), Int(Double(moves) * 0.9))
                why = "moves \(moves)→\(opts.movesOverride!)"
            } else { break }
            why += String(format: " (bot win rate %.0f%% above target band %.0f–%.0f%%)", bot.rate * 100, band.lo * 100, band.hi * 100)
        } else {
            if opts.targetScale > 1.0 {
                opts.targetScale = max(1.0, opts.targetScale / 1.12)
                why = "targets ×\(String(format: "%.2f", opts.targetScale))"
            } else if hasKeys && opts.distanceBoost > -1 {
                opts.distanceBoost -= 1
                why = "key distance \(opts.distanceBoost)"
            } else if opts.countScale > 0.71 && Double(moves) >= Double(brief.moves) * 1.12 {
                opts.countScale = max(0.7, opts.countScale - 0.15)
                why = "obstacle/plate counts ×\(String(format: "%.2f", opts.countScale))"
            } else if Double(moves) < Double(brief.moves) * 1.5 {
                opts.movesOverride = Int((Double(moves) * 1.12).rounded(.up))
                why = "moves \(moves)→\(opts.movesOverride!)"
            } else if hasCollect && opts.targetScale > 0.75 {
                opts.targetScale *= 0.9
                why = "targets ×\(String(format: "%.2f", opts.targetScale))"
            } else { break }
            why += String(format: " (bot win rate %.0f%% below target band %.0f–%.0f%%)", bot.rate * 100, band.lo * 100, band.hi * 100)
        }
        // Новая дистанция ключа меняет раскладку; иначе раскладка сохраняется.
        var next: Candidate?
        if opts.distanceBoost != cand.options.distanceBoost || opts.plateSpread != cand.options.plateSpread
            || opts.plateHardening != cand.options.plateHardening || opts.countScale != cand.options.countScale {
            var dummy = 0
            var adj: [String] = []
            next = findCandidate(brief, options: opts, adjustments: &adj, tried: &dummy)
            if next != nil && !adj.isEmpty { why += "; " + adj.joined(separator: "; ") }
        } else {
            let def = cand.layout.makeDefinition(cand.occupants, moves: opts.movesOverride ?? brief.moves, targetScale: opts.targetScale)
            if let sol = trySolve(def, brief) {
                next = Candidate(layout: cand.layout, occupants: cand.occupants, def: def, sol: sol, attempt: cand.attempt, options: opts)
            }
        }
        guard let n = next else { break }
        let nb = Solver.botWinRate(n.def, runs: 24)
        adjustments.append(why)
        cand = n
        bot = nb
    }

    var def = cand.def
    let sol = cand.sol
    def.solutionTrace = sol.trace
    let turns = sol.trace.filter { $0.action == "rotate" }.count
    let stars = WinPolicy.stars(initialMoves: def.initialMoves, movesLeft: sol.finalState.movesLeft)
    def.playtestStatus = String(format: "solver-verified; automated bot win rate %.0f%% (24 runs, no refill peeking); manual playtest not performed", bot.rate * 100)
    let replay = LevelValidator.replay(def)
    var status = replay.ok ? "ok" : "replay-failed: \(replay.failure ?? "?")"
    if brief.turnsRequired && turns < def.requiredTurns { status = "turn-requirement-violated" }
    if brief.turnsRequired && def.requiredTurns != brief.plannedTurns { status += "; required-turns \(def.requiredTurns)≠brief \(brief.plannedTurns)" }
    if bot.rate < band.lo - 0.041 || bot.rate > band.hi + 0.041 { status += String(format: "; outside-band(%.0f%%)", bot.rate * 100) }
    let url = levelsDir.appendingPathComponent(String(format: "level_%03d.json", brief.id))
    if let data = try? encoder().encode(def) { try? data.write(to: url, options: .atomic) }
    return ForgeRecord(id: brief.id, title: brief.title, world: brief.worldID, shape: brief.shape,
                       briefMoves: brief.moves, finalMoves: def.initialMoves, targetScale: cand.options.targetScale,
                       attemptUsed: cand.attempt, attemptsTried: tried, solutionLength: sol.trace.count,
                       solutionTurns: turns, solverStars: stars, requiredTurns: def.requiredTurns,
                       turnBrief: brief.turnBrief, botWinRate: bot.rate, botAvgMovesOnWin: bot.avgMovesOnWin,
                       adjustments: adjustments, status: status, seconds: Date().timeIntervalSince(t0))
}

func runBuild(root: URL) {
    let csv = root.appendingPathComponent("docs/spec/LEVEL_BRIEFS.csv").path
    let levelsDir = root.appendingPathComponent("VelvetCascade/Resources/Levels")
    try? FileManager.default.createDirectory(at: levelsDir, withIntermediateDirectories: true)
    let reportDir = root.appendingPathComponent("Production/LevelForge")
    try? FileManager.default.createDirectory(at: reportDir, withIntermediateDirectories: true)
    guard let briefs = try? BriefParser.load(path: csv) else { print("Cannot read \(csv)"); exit(1) }
    let ids = Set(parseRange(arg("--levels")))
    let todo = briefs.filter { ids.contains($0.id) }
    let jobs = Int(arg("--jobs") ?? "") ?? max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
    print("Forging \(todo.count) levels with \(jobs) jobs…")
    let lock = NSLock()
    var records: [ForgeRecord] = []
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = jobs
    for b in todo {
        queue.addOperation {
            let r = forge(b, levelsDir: levelsDir)
            lock.lock()
            records.append(r)
            print(String(format: "L%03d %-26@ %@ moves %d→%d sol %d (turns %d, req %d) bot %.0f%% %.1fs",
                         r.id, r.title as NSString, r.status as NSString, r.briefMoves, r.finalMoves,
                         r.solutionLength, r.solutionTurns, r.requiredTurns, r.botWinRate * 100, r.seconds))
            fflush(stdout)
            lock.unlock()
        }
    }
    queue.waitUntilAllOperationsAreFinished()
    records.sort { $0.id < $1.id }
    // Сливаем с предыдущими записями других уровней.
    let reportURL = reportDir.appendingPathComponent("forge_report.json")
    var all: [Int: ForgeRecord] = [:]
    if let data = try? Data(contentsOf: reportURL), let old = try? JSONDecoder().decode([ForgeRecord].self, from: data) {
        for r in old { all[r.id] = r }
    }
    for r in records { all[r.id] = r }
    let merged = all.values.sorted { $0.id < $1.id }
    if let data = try? encoder().encode(merged) { try? data.write(to: reportURL, options: .atomic) }
    let failed = merged.filter { $0.status != "ok" }
    print("Done. \(merged.count) records, \(failed.count) not ok: \(failed.map { "\($0.id):\($0.status)" })")
}

func runVerify(root: URL) {
    let levelsDir = root.appendingPathComponent("VelvetCascade/Resources/Levels")
    var ok = 0
    var problems: [String] = []
    var hashes = Set<String>()
    for id in 1...180 {
        let url = levelsDir.appendingPathComponent(String(format: "level_%03d.json", id))
        guard let data = try? Data(contentsOf: url) else { problems.append("L\(id): missing"); continue }
        guard let def = try? JSONDecoder().decode(LevelDefinition.self, from: data) else { problems.append("L\(id): decode"); continue }
        if def.id != id { problems.append("L\(id): id mismatch") }
        let issues = LevelValidator.validate(def)
        if !issues.isEmpty { problems.append("L\(id): \(issues.map { $0.description }.joined(separator: "; "))") }
        let r = LevelValidator.replay(def)
        if !r.ok { problems.append("L\(id): replay \(r.failure ?? "")") }
        let turns = def.solutionTrace.filter { $0.action == "rotate" }.count
        if def.turnBrief.contains("!") && turns < def.requiredTurns { problems.append("L\(id): required turns") }
        if def.solutionTrace.count > def.initialMoves { problems.append("L\(id): trace longer than moves") }
        let boardSig = def.initialOccupants.map { "\($0.x),\($0.y),\($0.type),\($0.color?.rawValue ?? -1)" }.joined(separator: "|")
        if !hashes.insert(boardSig).inserted { problems.append("L\(id): duplicate board") }
        if issues.isEmpty && r.ok { ok += 1 }
    }
    print("Verified \(ok)/180 levels OK")
    for p in problems { print("  " + p) }
    exit(problems.isEmpty ? 0 : 1)
}

let root = URL(fileURLWithPath: arg("--root") ?? FileManager.default.currentDirectoryPath)
switch CommandLine.arguments.dropFirst().first {
case "build": runBuild(root: root)
case "verify": runVerify(root: root)
case "diagnose": runDiagnose(root: root, id: Int(arg("--level") ?? "1") ?? 1)
case "botdebug": runBotDebug(root: root, id: Int(arg("--level") ?? "1") ?? 1, seed: UInt64(arg("--seed") ?? "1") ?? 1)
case "inspect": runInspect(root: root, id: Int(arg("--level") ?? "1") ?? 1)
default:
    print("usage: LevelForge build|verify --root <repo> [--levels 1-20] [--jobs N]")
}
