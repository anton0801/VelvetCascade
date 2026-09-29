// ProfileModels.swift — версионированный профиль игрока, активная попытка, daily receipts, настройки.

import Foundation
import VelvetDomain

struct LevelBest: Codable, Equatable {
    var stars: Int
    var minMovesUsed: Int
    var levelVersion: Int
    var turnsUsed: Int
}

struct AttemptSummary: Codable, Equatable {
    var attempts: Int = 0
    var wins: Int = 0
    var lastPlayed: Date?
}

/// Незавершённая попытка (максимум одна). Хранит полное settled-состояние вместе с PRNG.
struct ActiveRun: Codable, Equatable {
    var runID: String
    var attemptID: String
    var levelID: Int
    var levelVersion: Int
    var initialSeed: UInt64
    var state: GameState
    var hintsUsed: Int
    var startedAt: Date

    var revision: Int { state.revision }
}

struct DailyReceipt: Codable, Equatable, Identifiable {
    var id: String
    var dayIndex: Int64
    var symbols: [GemColor]
    var nominalReward: Int
    var creditedAmount: Int
    var claimedAtUTC: Date
    var acknowledged: Bool
    var schemaVersion: Int
}

/// Итог последней завершённой попытки — позволяет показать тот же экран результата после перезапуска.
struct LastResult: Codable, Equatable {
    var runID: String
    var levelID: Int
    var won: Bool
    var stars: Int
    var movesLeft: Int
    var movesUsed: Int
    var turnsUsed: Int
    var remaining: [RemainingObjective]
    var firstClear: Bool
    var creditedTickets: Int
    var previousBest: LevelBest?
    var worldUnlocked: Int?
    var campaignCompleted: Bool
}

struct RemainingObjective: Codable, Equatable {
    var objective: ObjectiveDef
    var remaining: Int
}

struct Profile: Codable, Equatable {
    static let currentSchema = 1
    static let campaignVersion = 1

    var schemaVersion: Int = Profile.currentSchema
    var campaignVersion: Int = Profile.campaignVersion
    var onboardingCompleted: Bool = false
    /// Ключ — levelID в виде строки (стабильная JSON-сериализация).
    var bestByLevel: [String: LevelBest] = [:]
    var attemptsSummary: [String: AttemptSummary] = [:]
    /// «levelID:campaignVersion» — первое прохождение уже вознаграждено.
    var firstClearLedger: [String] = []
    var hintBalance: Int = HintEconomy.startingBalance
    var activeRun: ActiveRun?
    var lastResult: LastResult?
    var highestClaimedDay: Int64?
    var recentReceipts: [DailyReceipt] = []
    var createdAt: Date = Date()
    /// Последняя успешно записанная транзакция: повтор записи с тем же ID не применяется дважды.
    var lastTransactionID: String?

    static func fresh() -> Profile { Profile() }

    // MARK: Derived (вычисляются из результатов уровней, а не хранятся отдельно)

    var completedLevels: Int { bestByLevel.count }
    var totalStars: Int { bestByLevel.values.reduce(0) { $0 + $1.stars } }

    func best(_ levelID: Int) -> LevelBest? { bestByLevel[String(levelID)] }
    func isCompleted(_ levelID: Int) -> Bool { bestByLevel[String(levelID)] != nil }

    /// Уровни открываются последовательно: 1 и каждый следующий после пройденного предыдущего.
    func isUnlocked(_ levelID: Int) -> Bool {
        levelID == 1 || isCompleted(levelID - 1) || isCompleted(levelID)
    }

    func isWorldUnlocked(_ worldID: Int) -> Bool {
        worldID == 1 || isCompleted(20 * (worldID - 1))
    }

    /// Текущий уровень кампании: первый не пройденный открытый; после 180 — nil.
    var currentLevel: Int? {
        for id in 1...180 where !isCompleted(id) { return isUnlocked(id) ? id : nil }
        return nil
    }

    var campaignComplete: Bool { (1...180).allSatisfy { isCompleted($0) } }

    var currentWorld: Int {
        if let c = currentLevel { return (c - 1) / 20 + 1 }
        return 9
    }

    func worldCompleted(_ worldID: Int) -> Int {
        ((worldID - 1) * 20 + 1...worldID * 20).filter { isCompleted($0) }.count
    }

    func worldStars(_ worldID: Int) -> Int {
        ((worldID - 1) * 20 + 1...worldID * 20).reduce(0) { $0 + (best($1)?.stars ?? 0) }
    }

    var todayReceipt: DailyReceipt? {
        guard let h = highestClaimedDay else { return nil }
        return recentReceipts.last { $0.dayIndex == h }
    }
}

enum ReduceMotionSetting: String, Codable, CaseIterable {
    case system, on, off

    var title: String {
        switch self {
        case .system: return "System"
        case .on: return "On"
        case .off: return "Off"
        }
    }
}

/// Настройки хранятся отдельно от профиля и активной попытки.
struct AppSettings: Codable, Equatable {
    var musicVolume: Double = 0.45
    var sfxVolume: Double = 0.70
    var ambienceVolume: Double = 0.20
    var haptics: Bool = true
    var reduceMotion: ReduceMotionSetting = .system
    var highContrastSymbols: Bool = false
    var gravityLabels: Bool = true
    /// Pause mute запоминает прежнюю ненулевую громкость.
    var lastNonZeroMusic: Double = 0.45
    var lastNonZeroSFX: Double = 0.70
}

enum WorldCatalog {
    static let names = ["Ruby Rehearsal", "Keyhole Wings", "Prop Workshop", "Frosted Gallery", "Chain Loft",
                        "Clockwork Curtains", "Split Stage", "Moonlit Rotation", "Grand Cascade"]
    static let taglines = ["Swap, charge and turn the stage.", "Keys and oriented exits.", "Crates and brass baffles.",
                           "Ice that pins the gems.", "Chains and hanging props.", "Switches and shutters.",
                           "Two pavilions, many inlets.", "Inner balconies and long orbits.", "Every rule, one grand finale."]

    static func name(_ world: Int) -> String { names[max(0, min(8, world - 1))] }
    static func tagline(_ world: Int) -> String { taglines[max(0, min(8, world - 1))] }
    static func background(_ world: Int) -> String { String(format: "vc_world_%02d", max(1, min(9, world))) }
    static func range(_ world: Int) -> ClosedRange<Int> { ((world - 1) * 20 + 1)...(world * 20) }
    static func world(ofLevel id: Int) -> Int { (id - 1) / 20 + 1 }
}
