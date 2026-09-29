// DebugFixture.swift — DEBUG-фикстуры для визуальной приёмки (screenshots всех 22 экранов и состояний).
// Работают на in-memory репозиториях, не меняют production profile и не создаются в release-сборке.
// Запуск: xcrun simctl launch <device> app.VelvetCascade -VCFixture <name> [-VCWidth 320]

import Foundation
import SwiftUI
import VelvetDomain

#if !DEBUG
/// Release: фикстуры отсутствуют (заглушка только для сигнатуры AppEnvironment).
struct DebugFixture {
    var clock: Clock? { nil }
    @MainActor func apply(to env: AppEnvironment) {}
}
#else
extension Notification.Name {
    static let vcDebugDailySpin = Notification.Name("vcDebugDailySpin")
}

struct DebugFixture {
    let name: String
    var clock: Clock?
    var forcedWidth: CGFloat?

    /// Сценарий действий: "swap:x,y>x,y;turn;preview;hint;pause;wait:1.5" (локальные координаты).
    var script: [String] = []

    static func fromLaunchArguments() -> DebugFixture? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-VCFixture"), i + 1 < args.count else { return nil }
        var f = DebugFixture(name: args[i + 1])
        // Фиксированное время: 2026-09-29 12:00 UTC.
        f.clock = FixedClock(Date(timeIntervalSince1970: 1_790_683_200))
        if let w = args.firstIndex(of: "-VCWidth"), w + 1 < args.count, let v = Double(args[w + 1]) { f.forcedWidth = CGFloat(v) }
        if let a = args.firstIndex(of: "-VCScript"), a + 1 < args.count { f.script = args[a + 1].split(separator: ";").map(String.init) }
        return f
    }

    // MARK: Profiles

    static func profile(completed: Int, stars: Int = 3, tickets: Int = 3) -> Profile {
        var p = Profile.fresh()
        p.onboardingCompleted = true
        p.hintBalance = tickets
        for id in stride(from: 1, through: completed, by: 1) {
            let s = id % 7 == 0 ? max(1, stars - 1) : stars
            p.bestByLevel[String(id)] = LevelBest(stars: s, minMovesUsed: 12, levelVersion: 1, turnsUsed: 1)
            p.attemptsSummary[String(id)] = AttemptSummary(attempts: 1 + id % 3, wins: 1, lastPlayed: Date(timeIntervalSince1970: 1_790_600_000))
            p.firstClearLedger.append("\(id):1")
        }
        return p
    }

    @MainActor
    func runScript(_ env: AppEnvironment) {
        guard !script.isEmpty else { return }
        let steps = script
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            env.audio.userInteracted()
            for cmd in steps {
                let parts = cmd.split(separator: ":", maxSplits: 1).map(String.init)
                let arg = parts.count > 1 ? parts[1] : ""
                if parts[0] == "wait" {
                    try? await Task.sleep(nanoseconds: UInt64((Double(arg) ?? 1) * 1_000_000_000))
                    continue
                }
                if parts[0] == "dailyspin" {
                    NotificationCenter.default.post(name: .vcDebugDailySpin, object: nil)
                    continue
                }
                // Ждать settled-состояния (конец commit и анимации), как реальный игрок.
                var guardCount = 0
                let needsPreview = parts[0] == "turn"
                while let s = env.session, (s.phase != .idle && s.phase != .selected) || (s.preview != nil && !needsPreview), guardCount < 150 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guardCount += 1
                }
                guard let s = env.session else { continue }
                switch parts[0] {
                case "swap":
                    let pts = arg.split(separator: ">").map { $0.split(separator: ",").compactMap { Int($0) } }
                    if pts.count == 2, pts[0].count == 2, pts[1].count == 2 {
                        s.attemptSwap(from: Coord(pts[0][0], pts[0][1]), to: Coord(pts[1][0], pts[1][1]))
                    }
                case "tap":
                    let p = arg.split(separator: ",").compactMap { Int($0) }
                    if p.count == 2 { s.tap(local: Coord(p[0], p[1])) }
                case "preview": s.openTurnPreview()
                case "turn": s.confirmTurn()
                case "hint": s.requestHint()
                case "pause": s.pause()
                case "solve", "solveall":
                    // Эталонный solutionTrace уровня: один шаг или весь trace подряд.
                    let range: [Int] = parts[0] == "solveall" ? Array(0..<s.level.solutionTrace.count) : [Int(arg) ?? 0]
                    for i in range where i < s.level.solutionTrace.count {
                        var g = 0
                        while (s.phase != .idle && s.phase != .selected) || s.preview != nil, g < 150 {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            g += 1
                        }
                        guard s.state.status == .playing, let k = s.level.solutionTrace[i].gameAction else { break }
                        switch k {
                        case .swap(let a, let b): s.attemptSwap(from: a, to: b)
                        case .rotate:
                            s.openTurnPreview()
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            s.confirmTurn()
                        }
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                default: break
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    @MainActor
    func apply(to env: AppEnvironment) {
        env.forcedWidth = forcedWidth
        if ProcessInfo.processInfo.arguments.contains("-VCReduceMotion") {
            env.store.settings.reduceMotion = .on
        }
        defer { runScript(env) }
        let store = env.store
        let router = env.router
        let day = store.currentDay

        func startGame(_ levelID: Int, profile p: Profile, mutate: ((inout GameState) -> Void)? = nil) {
            store.replaceForFixture(p)
            guard let level = try? env.levels.load(levelID) else { return }
            var state = LevelFactory.initialState(for: level)
            mutate?(&state)
            let run = ActiveRun(runID: "fixture-\(levelID)", attemptID: "fixture", levelID: levelID, levelVersion: level.levelVersion,
                                initialSeed: level.seed, state: state, hintsUsed: 0, startedAt: Date())
            var p2 = store.profile
            p2.activeRun = run
            store.replaceForFixture(p2)
            let s = GameSession(env: env, level: level, run: run)
            s.banner = nil
            env.session = s
            router.reset([.home, .worldMap(world: level.worldID), .gameplay(runID: run.runID)])
        }

        func rotate(_ s: inout GameState, times: Int) {
            for k in 0..<times {
                s.charge = 12
                if let r = try? GameEngine.apply(GameAction(id: "fx-rot-\(k)", kind: .rotate), to: s, recordSteps: false) { s = r.state }
            }
        }

        func result(_ levelID: Int, won: Bool, stars: Int, firstClear: Bool, credited: Int, prev: LevelBest?, completedBefore: Int) {
            var p = DebugFixture.profile(completed: completedBefore)
            guard let level = try? env.levels.load(levelID) else { return }
            let moves = level.initialMoves
            let movesLeft: Int = {
                switch stars {
                case 3: return (moves * 30 + 99) / 100 + 2
                case 2: return (moves * 15 + 99) / 100
                default: return 1
                }
            }()
            if won {
                p.bestByLevel[String(levelID)] = LevelBest(stars: max(stars, prev?.stars ?? 0), minMovesUsed: moves - movesLeft, levelVersion: 1, turnsUsed: 2)
            }
            p.lastResult = LastResult(runID: "fixture", levelID: levelID, won: won, stars: won ? stars : 0, movesLeft: won ? movesLeft : 0,
                                      movesUsed: won ? moves - movesLeft : moves, turnsUsed: 2,
                                      remaining: level.objectives.map { RemainingObjective(objective: $0, remaining: won ? 0 : 3) },
                                      firstClear: firstClear, creditedTickets: credited, previousBest: prev,
                                      worldUnlocked: won && levelID % 20 == 0 ? levelID / 20 + 1 : nil, campaignCompleted: levelID == 180 && won)
            store.replaceForFixture(p)
            router.reset([.home, .worldMap(world: level.worldID), won ? .curtainCall(runID: "fixture") : .oneMoreAct(runID: "fixture")])
        }

        func daily(collected: Bool, symbols: [GemColor] = [.bell, .bell, .star], balance: Int = 3) -> Profile {
            var p = DebugFixture.profile(completed: 12, tickets: balance)
            if collected {
                let nominal = DailyRewardPolicy.nominalReward(for: symbols)
                let credited = DailyRewardPolicy.creditedAmount(nominal: nominal, oldBalance: balance)
                p.highestClaimedDay = day
                p.hintBalance = balance + credited
                p.recentReceipts = [DailyReceipt(id: "fixture-receipt", dayIndex: day, symbols: symbols, nominalReward: nominal,
                                                 creditedAmount: credited, claimedAtUTC: store.clock.now(), acknowledged: false, schemaVersion: 1)]
            } else {
                p.highestClaimedDay = day - 1
            }
            return p
        }

        switch name {
        // 01–03
        case "welcome":
            store.replaceForFixture(.fresh()); router.reset([.welcome])
        case "match": store.replaceForFixture(.fresh()); router.reset([.welcome, .matchTutorial])
        case "rotate": store.replaceForFixture(.fresh()); router.reset([.welcome, .matchTutorial, .rotationTutorial])
        // 04
        case "home_new":
            var p = Profile.fresh(); p.onboardingCompleted = true; p.highestClaimedDay = day - 1
            store.replaceForFixture(p); router.reset([.home])
        case "home_resume":
            var p = DebugFixture.profile(completed: 33)
            if let level = try? env.levels.load(34) {
                p.activeRun = ActiveRun(runID: "fx", attemptID: "fx", levelID: 34, levelVersion: 1, initialSeed: level.seed,
                                        state: LevelFactory.initialState(for: level), hintsUsed: 0, startedAt: Date())
            }
            p.highestClaimedDay = day
            store.replaceForFixture(p); router.reset([.home])
        case "home_complete":
            var p = DebugFixture.profile(completed: 180, tickets: 57); p.highestClaimedDay = day - 1
            store.replaceForFixture(p); router.reset([.home])
        // 05
        case "worlds_new": store.replaceForFixture(DebugFixture.profile(completed: 0)); router.reset([.home, .worlds])
        case "worlds_mid": store.replaceForFixture(DebugFixture.profile(completed: 87)); router.reset([.home, .worlds])
        case "worlds_all": store.replaceForFixture(DebugFixture.profile(completed: 180)); router.reset([.home, .worlds])
        // 06
        case "map_mid": store.replaceForFixture(DebugFixture.profile(completed: 29)); router.reset([.home, .worlds, .worldMap(world: 2)])
        case "map_locked": store.replaceForFixture(DebugFixture.profile(completed: 3)); router.reset([.home, .worlds, .worldMap(world: 1)])
        // 07
        case "brief_new": store.replaceForFixture(DebugFixture.profile(completed: 60)); router.reset([.home, .worldMap(world: 4), .levelBrief(level: 61)])
        case "brief_replay": store.replaceForFixture(DebugFixture.profile(completed: 14)); router.reset([.home, .worldMap(world: 1), .levelBrief(level: 5)])
        case "brief_invalid":
            env.levels.forcedInvalidLevel = 42
            store.replaceForFixture(DebugFixture.profile(completed: 41)); router.reset([.home, .worldMap(world: 3), .levelBrief(level: 42)])
        // 08
        case "game_6x6": startGame(1, profile: DebugFixture.profile(completed: 0))
        case "game_8x8": startGame(81, profile: DebugFixture.profile(completed: 80))
        case "game_ring": startGame(141, profile: DebugFixture.profile(completed: 140))
        case "game_split": startGame(125, profile: DebugFixture.profile(completed: 124))
        case "game_q1": startGame(52, profile: DebugFixture.profile(completed: 51)) { rotate(&$0, times: 1) }
        case "game_q2": startGame(62, profile: DebugFixture.profile(completed: 61)) { rotate(&$0, times: 2) }
        case "game_q3": startGame(102, profile: DebugFixture.profile(completed: 101)) { rotate(&$0, times: 3) }
        case "game_moves1": startGame(17, profile: DebugFixture.profile(completed: 16)) { $0.movesLeft = 1 }
        case "game_hc":
            var p = DebugFixture.profile(completed: 30); _ = p
            store.settings.highContrastSymbols = true
            p = DebugFixture.profile(completed: 30)
            startGame(31, profile: p)
        case "game_hint":
            startGame(9, profile: DebugFixture.profile(completed: 8))
            env.session?.requestHint()
        case "game_tutorial":
            store.replaceForFixture(Profile.fresh())
            startGame(21, profile: DebugFixture.profile(completed: 20))
            env.session?.banner = env.session?.level.tutorialSteps.first
        case let n where n.hasPrefix("level_"):
            let id = Int(n.dropFirst("level_".count)) ?? 1
            startGame(id, profile: DebugFixture.profile(completed: id - 1))
        // 09
        case "preview_key": startGame(21, profile: DebugFixture.profile(completed: 20)); env.session?.openTurnPreview()
        case "preview_split": startGame(122, profile: DebugFixture.profile(completed: 121)) { $0.charge = 12 }; env.session?.openTurnPreview()
        // 10
        case "pause": startGame(45, profile: DebugFixture.profile(completed: 44)); env.session?.paused = true
        case "restart_confirm": startGame(45, profile: DebugFixture.profile(completed: 44)); env.session?.restartConfirm = true
        // 11
        case "win_3": result(7, won: true, stars: 3, firstClear: true, credited: 1, prev: nil, completedBefore: 6)
        case "win_2": result(33, won: true, stars: 2, firstClear: true, credited: 1, prev: nil, completedBefore: 32)
        case "win_1_repeat": result(12, won: true, stars: 1, firstClear: false, credited: 0,
                                    prev: LevelBest(stars: 3, minMovesUsed: 14, levelVersion: 1, turnsUsed: 1), completedBefore: 30)
        case "win_20": result(20, won: true, stars: 3, firstClear: true, credited: 1, prev: nil, completedBefore: 19)
        case "win_180": result(180, won: true, stars: 2, firstClear: true, credited: 1, prev: nil, completedBefore: 179)
        case "win_cap": result(15, won: true, stars: 3, firstClear: true, credited: 0, prev: nil, completedBefore: 14)
        // 12
        case "fail": result(26, won: false, stars: 0, firstClear: false, credited: 0, prev: nil, completedBefore: 25)
        // 13
        case "new_theatre":
            store.replaceForFixture(DebugFixture.profile(completed: 40)); router.reset([.home, .newTheatre(world: 3, final: false)])
        case "final_bow":
            store.replaceForFixture(DebugFixture.profile(completed: 180)); router.reset([.home, .newTheatre(world: 9, final: true)])
        // 14–15, 21
        case "daily_ready": store.replaceForFixture(daily(collected: false)); router.reset([.home, .daily])
        case "daily_collected":
            var p = daily(collected: true); p.recentReceipts[0].acknowledged = true
            store.replaceForFixture(p); router.reset([.home, .daily])
        case "daily_restored": store.replaceForFixture(daily(collected: true, symbols: [.clover, .heart, .star])); router.reset([.home, .daily])
        case "daily_error":
            store.replaceForFixture(daily(collected: false))
            router.reset([.home, .daily])
            store.repo.injectWriteFailure = true
            _ = store.claimDaily(symbols: [.heart, .heart, .diamond], day: day)
        case "reward_mixed": store.replaceForFixture(daily(collected: true, symbols: [.heart, .diamond, .star])); router.reset([.home, .daily, .dailyReward(receiptID: "fixture-receipt")])
        case "reward_pair": store.replaceForFixture(daily(collected: true, symbols: [.bell, .star, .bell])); router.reset([.home, .daily, .dailyReward(receiptID: "fixture-receipt")])
        case "reward_triple": store.replaceForFixture(daily(collected: true, symbols: [.clover, .clover, .clover])); router.reset([.home, .daily, .dailyReward(receiptID: "fixture-receipt")])
        case "reward_cap": store.replaceForFixture(daily(collected: true, symbols: [.star, .star, .heart], balance: 1_000_000)); router.reset([.home, .daily, .dailyReward(receiptID: "fixture-receipt")])
        case "rules": store.replaceForFixture(daily(collected: false)); router.reset([.home, .daily]); router.modal = .dailyRules
        // 16
        case let n where n.hasPrefix("handbook_"):
            store.replaceForFixture(DebugFixture.profile(completed: 5))
            let t = HandbookTopic(rawValue: String(n.dropFirst("handbook_".count))) ?? .matches
            router.reset([.home, .handbook(topic: t)])
        // 17–19, 22
        case "settings": store.replaceForFixture(DebugFixture.profile(completed: 12)); router.reset([.home, .settings])
        case "credits": store.replaceForFixture(DebugFixture.profile(completed: 12)); router.reset([.home, .settings, .credits])
        case "import_valid", "import_run":
            store.replaceForFixture(DebugFixture.profile(completed: 12))
            var src = DebugFixture.profile(completed: 64, tickets: 11)
            if name == "import_run", let level = try? env.levels.load(65) {
                src.activeRun = ActiveRun(runID: "fx", attemptID: "fx", levelID: 65, levelVersion: 1, initialSeed: level.seed,
                                          state: LevelFactory.initialState(for: level), hintsUsed: 0, startedAt: Date())
            }
            if let (data, fileName) = try? BackupCodec.export(src, now: store.clock.now()),
               let preview = try? BackupCodec.validate(data: data, fileName: "VelvetCascade_Backup_with_a_rather_long_descriptive_name_" + fileName,
                                                       levels: env.levels, now: store.clock.now()) {
                env.importPreview = preview
            }
            router.reset([.home, .settings, .importReview])
        case "reset":
            store.replaceForFixture(DebugFixture.profile(completed: 12)); router.reset([.home, .settings]); router.modal = .resetConfirm
        // 20
        case "recovery_save":
            startGame(8, profile: DebugFixture.profile(completed: 7))
            store.repo.injectWriteFailure = true
            _ = store.saveRun(env.session!.state)
        case "recovery_import":
            store.replaceForFixture(DebugFixture.profile(completed: 12)); router.reset([.home, .settings])
            env.recovery = .importInvalid(diagnosticID: "VC-IMP-7F3A21", reason: ImportError.checksumMismatch.reason)
        case "recovery_level":
            store.replaceForFixture(DebugFixture.profile(completed: 41)); router.reset([.home, .worldMap(world: 3)])
            env.recovery = .levelInvalid(levelID: 42, diagnosticID: "VC-LVL-42B7C0")
        case "recovery_restore":
            store.replaceForFixture(DebugFixture.profile(completed: 12)); router.reset([.home])
            store.loadIssue = .restoreBackup(diagnosticID: "VC-LOAD-19D2E4")
        case "gallery_1", "gallery":
            store.replaceForFixture(DebugFixture.profile(completed: 12)); router.reset([.gallery(page: 1)])
        case "gallery_2", "gallery_3", "gallery_4":
            store.replaceForFixture(DebugFixture.profile(completed: 12)); router.reset([.gallery(page: Int(String(name.last!)) ?? 2)])
        default:
            store.replaceForFixture(DebugFixture.profile(completed: 12)); router.reset([.home])
        }
    }
}
#endif
