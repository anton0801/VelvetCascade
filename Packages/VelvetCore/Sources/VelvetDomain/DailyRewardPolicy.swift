// DailyRewardPolicy.swift — математика Daily Encore (3 барабана × 5 равновероятных символов).
//
// Все три разные: 60/125 = 48% → 1 ticket; ровно два одинаковых (любые позиции): 60/125 = 48% → 2;
// все три одинаковые: 5/125 = 4% → 5. Ожидание 1.64. Triple проверяется раньше pair.
// Тип символа не меняет награду. Нет взвешенных лент, near-miss, streak и платного повтора.

import Foundation

public enum DailyOutcomeKind: String, Codable, CaseIterable, Sendable {
    case mixed
    case pair
    case triple

    public var nominalReward: Int {
        switch self {
        case .mixed: return DailyRewardPolicy.mixedReward
        case .pair: return DailyRewardPolicy.pairReward
        case .triple: return DailyRewardPolicy.tripleReward
        }
    }

    public var outcomesOf125: Int {
        switch self {
        case .mixed: return 60
        case .pair: return 60
        case .triple: return 5
        }
    }

    public var probabilityPercent: Int { outcomesOf125 * 100 / 125 }

    public var title: String {
        switch self {
        case .mixed: return "Mixed"
        case .pair: return "Pair"
        case .triple: return "Triple"
        }
    }
}

public enum DailyRewardPolicy {
    public static let mixedReward = 1
    public static let pairReward = 2
    public static let tripleReward = 5
    public static let symbolCount = 5
    public static let reelCount = 3
    public static let secondsPerDay: Int64 = 86_400

    public static func classify(_ symbols: [GemColor]) -> DailyOutcomeKind {
        precondition(symbols.count == 3)
        if symbols[0] == symbols[1] && symbols[1] == symbols[2] { return .triple }
        if symbols[0] == symbols[1] || symbols[1] == symbols[2] || symbols[0] == symbols[2] { return .pair }
        return .mixed
    }

    public static func nominalReward(for symbols: [GemColor]) -> Int {
        classify(symbols).nominalReward
    }

    /// Фактическое зачисление с учётом верхней границы баланса.
    public static func creditedAmount(nominal: Int, oldBalance: Int, cap: Int = HintEconomy.maxBalance) -> Int {
        max(0, min(nominal, cap - oldBalance))
    }

    /// dayIndex = floor(unixTime / 86400) — календарный UTC-день.
    public static func dayIndex(unixTime: TimeInterval) -> Int64 {
        Int64((unixTime / Double(secondsPerDay)).rounded(.down))
    }

    /// Разрешён ли запуск: новый профиль (nil) — да при валидной дате; иначе currentDay > highestClaimedDay.
    public static func isEligible(currentDay: Int64, highestClaimedDay: Int64?) -> Bool {
        guard currentDay >= 0 else { return false }
        guard let h = highestClaimedDay else { return true }
        return currentDay > h
    }

    /// Момент следующего допустимого запуска (00:00 UTC дня после highestClaimedDay).
    public static func nextEligibleDate(highestClaimedDay: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval((highestClaimedDay + 1) * secondsPerDay))
    }
}

public enum HintEconomy {
    public static let startingBalance = 3
    public static let maxBalance = 1_000_000
    public static let firstClearReward = 1

    public static func credit(_ amount: Int, to balance: Int) -> (newBalance: Int, credited: Int) {
        let credited = max(0, min(amount, maxBalance - balance))
        return (balance + credited, credited)
    }
}
