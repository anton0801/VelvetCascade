// ProgressStore.swift — Application-слой: атомарные сценарии профиля.
//
// Каждое изменение применяется к копии durable snapshot и публикуется ТОЛЬКО после успешной записи.
// При ошибке записи копия сохраняется как pending transaction: Retry повторяет ту же запись
// (тот же transactionID), не применяя изменение повторно. Награды не выдаются до durable commit.

import Foundation
import SwiftUI
import VelvetDomain

struct PendingTransaction: Identifiable {
    let id: String
    let label: String
    let profile: Profile
    let onSuccess: (Profile) -> Void
}

enum RecoveryKind: Equatable {
    case saveFailed(diagnosticID: String)
    case importInvalid(diagnosticID: String, reason: String)
    case levelInvalid(levelID: Int, diagnosticID: String)
    case restoreBackup(diagnosticID: String)
    case unrecoverable(diagnosticID: String)
}

@MainActor
final class ProgressStore: ObservableObject {
    @Published private(set) var profile: Profile
    @Published var settings: AppSettings {
        didSet { settingsRepo.save(settings); onSettingsChanged?(settings) }
    }
    @Published private(set) var isCommitting = false
    @Published var pending: PendingTransaction?
    /// Сообщение о загрузке (восстановление backup / неустранимое повреждение).
    @Published var loadIssue: RecoveryKind?
    private var restorableBackup: Profile?

    let repo: AtomicProgressRepository
    let settingsRepo: SettingsRepository
    let clock: Clock
    var onSettingsChanged: ((AppSettings) -> Void)?

    init(repo: AtomicProgressRepository, settingsRepo: SettingsRepository, clock: Clock) {
        self.repo = repo
        self.settingsRepo = settingsRepo
        self.clock = clock
        self.settings = settingsRepo.load()
        switch repo.load() {
        case .loaded(let p): profile = p
        case .fresh(let p): profile = p
        case .needsRestore(let backup, let diag):
            profile = .fresh()
            restorableBackup = backup
            loadIssue = .restoreBackup(diagnosticID: diag)
        case .unrecoverable(let diag):
            profile = .fresh()
            loadIssue = .unrecoverable(diagnosticID: diag)
        }
    }

    /// DEBUG fixtures: заменить профиль без записи на диск production.
    func replaceForFixture(_ p: Profile) {
        profile = p
        try? repo.save(p)
    }

    // MARK: Transactions

    @discardableResult
    func commit(_ label: String, _ mutate: (inout Profile) -> Void, onSuccess: @escaping (Profile) -> Void = { _ in }) -> Bool {
        var next = profile
        mutate(&next)
        let tx = UUID().uuidString
        next.lastTransactionID = tx
        return write(PendingTransaction(id: tx, label: label, profile: next, onSuccess: onSuccess))
    }

    private func write(_ t: PendingTransaction) -> Bool {
        isCommitting = true
        defer { isCommitting = false }
        do {
            try repo.save(t.profile)
            profile = t.profile
            pending = nil
            t.onSuccess(t.profile)
            return true
        } catch {
            pending = t
            return false
        }
    }

    /// Save Retry: та же транзакция и тот же transactionID.
    @discardableResult
    func retryPending() -> Bool {
        guard let t = pending else { return true }
        if profile.lastTransactionID == t.id { pending = nil; return true }
        return write(t)
    }

    /// Back: вернуться к durable snapshot; несохранённое действие отбрасывается.
    func discardPending() { pending = nil }

    var pendingDiagnosticID: String {
        "VC-SAVE-" + String((pending?.id ?? "00000000").prefix(8))
    }

    // MARK: Load recovery

    func restoreBackup() -> Bool {
        guard let b = restorableBackup else { return false }
        do {
            try repo.save(b)
            profile = b
            restorableBackup = nil
            loadIssue = nil
            return true
        } catch {
            return false
        }
    }

    /// Отказ от восстановления: проверенный backup переносится в архив (не удаляется и не перезаписывается).
    func declineRestore() {
        repo.archiveBackup()
        restorableBackup = nil
        loadIssue = nil
    }

    /// Явный выбор пользователя после неустранимого повреждения (не автоматически).
    func startNewProfileAfterCorruption() {
        repo.wipeCorruptedMain()
        _ = commit("new-profile") { $0 = .fresh() }
        restorableBackup = nil
        loadIssue = nil
    }

    // MARK: Onboarding

    func completeOnboarding() {
        commit("onboarding") { $0.onboardingCompleted = true }
    }

    // MARK: Runs

    func startRun(level: LevelDefinition) -> Bool {
        let state = LevelFactory.initialState(for: level)
        let run = ActiveRun(runID: UUID().uuidString, attemptID: UUID().uuidString, levelID: level.id,
                            levelVersion: level.levelVersion, initialSeed: level.seed, state: state,
                            hintsUsed: 0, startedAt: clock.now())
        return commit("start-run") { p in
            p.activeRun = run
            p.lastResult = nil
            var a = p.attemptsSummary[String(level.id)] ?? AttemptSummary()
            a.attempts += 1
            a.lastPlayed = self.clock.now()
            p.attemptsSummary[String(level.id)] = a
        }
    }

    func saveRun(_ state: GameState, hintsUsed: Int? = nil) -> Bool {
        guard profile.activeRun != nil else { return false }
        return commit("save-run") { p in
            p.activeRun?.state = state
            if let h = hintsUsed { p.activeRun?.hintsUsed = h }
        }
    }

    /// Hint Ticket списывается только после показа допустимого действия.
    func spendHint() -> Bool {
        guard profile.hintBalance > 0 else { return false }
        return commit("spend-hint") { p in
            p.hintBalance -= 1
            p.activeRun?.hintsUsed += 1
        }
    }

    func abandonRun() -> Bool {
        commit("abandon-run") { $0.activeRun = nil }
    }

    /// Result + best + unlock + first-clear ledger + reward — одной транзакцией до показа экрана.
    func commitOutcome(level: LevelDefinition, state: GameState, onSuccess: @escaping (Profile) -> Void = { _ in }) -> Bool {
        let won = state.status == .won
        let key = String(level.id)
        return commit(won ? "win" : "fail", { p in
            let prevBest = p.bestByLevel[key]
            var stars = 0
            var firstClear = false
            var credited = 0
            var unlocked: Int?
            if won {
                stars = WinPolicy.stars(initialMoves: state.initialMoves, movesLeft: state.movesLeft)
                var best = prevBest ?? LevelBest(stars: 0, minMovesUsed: Int.max, levelVersion: level.levelVersion, turnsUsed: state.turnsUsed)
                if best.levelVersion != level.levelVersion {
                    best = LevelBest(stars: 0, minMovesUsed: Int.max, levelVersion: level.levelVersion, turnsUsed: state.turnsUsed)
                }
                if stars > best.stars || state.movesUsed < best.minMovesUsed { best.turnsUsed = state.turnsUsed }
                best.stars = max(best.stars, stars)
                best.minMovesUsed = min(best.minMovesUsed, state.movesUsed)
                p.bestByLevel[key] = best
                var a = p.attemptsSummary[key] ?? AttemptSummary(attempts: 1)
                a.wins += 1
                a.lastPlayed = self.clock.now()
                p.attemptsSummary[key] = a
                let ledgerKey = "\(level.id):\(Profile.campaignVersion)"
                if !p.firstClearLedger.contains(ledgerKey) {
                    p.firstClearLedger.append(ledgerKey)
                    firstClear = true
                    let r = HintEconomy.credit(HintEconomy.firstClearReward, to: p.hintBalance)
                    p.hintBalance = r.newBalance
                    credited = r.credited
                }
                if level.id % 20 == 0 && level.id < 180 && prevBest == nil { unlocked = level.id / 20 + 1 }
            }
            let remaining = state.objectives.map { RemainingObjective(objective: $0, remaining: state.remaining(for: $0)) }
            p.lastResult = LastResult(runID: p.activeRun?.runID ?? UUID().uuidString, levelID: level.id, won: won,
                                      stars: stars, movesLeft: state.movesLeft, movesUsed: state.movesUsed,
                                      turnsUsed: state.turnsUsed, remaining: remaining, firstClear: firstClear,
                                      creditedTickets: credited, previousBest: prevBest, worldUnlocked: unlocked,
                                      campaignCompleted: won && level.id == 180 && prevBest == nil)
            p.activeRun = nil
        }, onSuccess: onSuccess)
    }

    // MARK: Daily Encore

    var currentDay: Int64 { DailyRewardPolicy.dayIndex(unixTime: clock.now().timeIntervalSince1970) }

    var dailyEligible: Bool {
        DailyRewardPolicy.isEligible(currentDay: currentDay, highestClaimedDay: profile.highestClaimedDay)
    }

    var nextDailyDate: Date {
        DailyRewardPolicy.nextEligibleDate(highestClaimedDay: max(profile.highestClaimedDay ?? currentDay, currentDay - 1))
    }

    /// Free Spin: проверить день → системный криптографический RNG → одна транзакция (receipt+balance+day).
    func claimDaily() -> DailyReceipt? {
        let day = currentDay
        guard DailyRewardPolicy.isEligible(currentDay: day, highestClaimedDay: profile.highestClaimedDay) else { return nil }
        let symbols = SecureRandom.dailySymbols()
        return claimDaily(symbols: symbols, day: day)
    }

    func claimDaily(symbols: [GemColor], day: Int64) -> DailyReceipt? {
        let nominal = DailyRewardPolicy.nominalReward(for: symbols)
        let credited = DailyRewardPolicy.creditedAmount(nominal: nominal, oldBalance: profile.hintBalance)
        let receipt = DailyReceipt(id: UUID().uuidString, dayIndex: day, symbols: symbols, nominalReward: nominal,
                                   creditedAmount: credited, claimedAtUTC: clock.now(), acknowledged: false,
                                   schemaVersion: 1)
        let ok = commit("daily-claim") { p in
            p.hintBalance += credited
            p.highestClaimedDay = max(p.highestClaimedDay ?? day, day)
            p.recentReceipts.append(receipt)
            if p.recentReceipts.count > 30 { p.recentReceipts.removeFirst(p.recentReceipts.count - 30) }
        }
        return ok ? receipt : nil
    }

    func receipt(id: String) -> DailyReceipt? { profile.recentReceipts.first { $0.id == id } }

    /// Непризнанный receipt (crash после commit) — показать ту же тройку, не начислять заново.
    var unacknowledgedReceipt: DailyReceipt? { profile.recentReceipts.last { !$0.acknowledged } }

    func acknowledge(receiptID: String) {
        commit("daily-ack") { p in
            if let i = p.recentReceipts.firstIndex(where: { $0.id == receiptID }) { p.recentReceipts[i].acknowledged = true }
        }
    }

    // MARK: Import / Reset

    func applyImport(_ preview: ImportPreview) -> Bool {
        let local = profile
        return commit("import") { p in
            var imported = preview.profile
            // High-watermark не понижается; уже начисленный локальный receipt сегодняшнего дня сохраняется.
            imported.highestClaimedDay = max(local.highestClaimedDay ?? -1, imported.highestClaimedDay ?? -1)
            if imported.highestClaimedDay == -1 { imported.highestClaimedDay = nil }
            var receipts = imported.recentReceipts
            for r in local.recentReceipts where !receipts.contains(where: { $0.id == r.id || $0.dayIndex == r.dayIndex }) {
                receipts.append(r)
            }
            receipts.sort { $0.dayIndex < $1.dayIndex }
            if receipts.count > 30 { receipts.removeFirst(receipts.count - 30) }
            imported.recentReceipts = receipts
            imported.onboardingCompleted = true
            imported.lastResult = nil
            p = imported
        }
    }

    /// Сброс: campaign, run, attempts и hint balance; settings, highestClaimedDay и receipts остаются.
    func resetProgress() -> Bool {
        let keepDay = profile.highestClaimedDay
        let keepReceipts = profile.recentReceipts
        return commit("reset") { p in
            var fresh = Profile.fresh()
            fresh.onboardingCompleted = true
            fresh.highestClaimedDay = keepDay
            fresh.recentReceipts = keepReceipts
            p = fresh
        }
    }
}
