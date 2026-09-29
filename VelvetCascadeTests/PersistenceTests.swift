// PersistenceTests.swift — хранилище, транзакции, Daily, импорт/экспорт, уровни из бандла.

import XCTest
import VelvetDomain
@testable import VelvetCascade

@MainActor
final class ProgressStoreTests: XCTestCase {
    var clock: FixedClock!
    var store: ProgressStore!

    override func setUp() async throws {
        clock = FixedClock(Date(timeIntervalSince1970: 1_790_683_200))   // 2026-09-29 12:00 UTC
        store = ProgressStore(repo: AtomicProgressRepository(inMemory: true), settingsRepo: SettingsRepository(inMemory: true), clock: clock)
    }

    func level(_ id: Int) throws -> LevelDefinition { try BundleLevelRepository().load(id) }

    func testNewProfileDefaults() {
        XCTAssertEqual(store.profile.completedLevels, 0)
        XCTAssertEqual(store.profile.hintBalance, 3)
        XCTAssertNil(store.profile.activeRun)
        XCTAssertEqual(store.profile.currentLevel, 1)
        XCTAssertTrue(store.profile.isWorldUnlocked(1))
        XCTAssertFalse(store.profile.isWorldUnlocked(2))
    }

    func testWinCommitsBestUnlockAndFirstClearOnce() throws {
        let def = try level(1)
        XCTAssertTrue(store.startRun(level: def))
        var s = LevelFactory.initialState(for: def)
        s.status = .won
        s.movesLeft = def.initialMoves - 5
        XCTAssertTrue(store.commitOutcome(level: def, state: s))
        XCTAssertEqual(store.profile.hintBalance, 4)
        XCTAssertEqual(store.profile.best(1)?.stars, 3)
        XCTAssertTrue(store.profile.isUnlocked(2))
        XCTAssertNil(store.profile.activeRun)
        XCTAssertEqual(store.profile.lastResult?.firstClear, true)
        // Повторная победа: без повторной награды, best не понижается.
        XCTAssertTrue(store.startRun(level: def))
        s.movesLeft = 0
        XCTAssertTrue(store.commitOutcome(level: def, state: s))
        XCTAssertEqual(store.profile.hintBalance, 4)
        XCTAssertEqual(store.profile.best(1)?.stars, 3)
        XCTAssertEqual(store.profile.best(1)?.minMovesUsed, 5)
        XCTAssertEqual(store.profile.lastResult?.firstClear, false)
        XCTAssertEqual(store.profile.attemptsSummary["1"]?.attempts, 2)
        XCTAssertEqual(store.profile.attemptsSummary["1"]?.wins, 2)
    }

    func testFailKeepsBestAndDoesNotReward() throws {
        let def = try level(2)
        var p = store.profile
        p.bestByLevel["1"] = LevelBest(stars: 3, minMovesUsed: 4, levelVersion: 1, turnsUsed: 0)
        p.bestByLevel["2"] = LevelBest(stars: 2, minMovesUsed: 9, levelVersion: 1, turnsUsed: 0)
        store.replaceForFixture(p)
        XCTAssertTrue(store.startRun(level: def))
        var s = LevelFactory.initialState(for: def)
        s.status = .failed
        XCTAssertTrue(store.commitOutcome(level: def, state: s))
        XCTAssertEqual(store.profile.best(2)?.stars, 2)
        XCTAssertEqual(store.profile.hintBalance, 3)
        XCTAssertEqual(store.profile.lastResult?.won, false)
    }

    func testWorld20UnlocksNextWorldAndNot181() throws {
        var p = DebugFixture.profile(completed: 19)
        store.replaceForFixture(p)
        let def = try level(20)
        XCTAssertTrue(store.startRun(level: def))
        var s = LevelFactory.initialState(for: def)
        s.status = .won
        XCTAssertTrue(store.commitOutcome(level: def, state: s))
        XCTAssertTrue(store.profile.isWorldUnlocked(2))
        XCTAssertEqual(store.profile.lastResult?.worldUnlocked, 2)
        p = DebugFixture.profile(completed: 179)
        store.replaceForFixture(p)
        let last = try level(180)
        XCTAssertTrue(store.startRun(level: last))
        var f = LevelFactory.initialState(for: last)
        f.status = .won
        XCTAssertTrue(store.commitOutcome(level: last, state: f))
        XCTAssertNil(store.profile.lastResult?.worldUnlocked)
        XCTAssertEqual(store.profile.lastResult?.campaignCompleted, true)
        XCTAssertTrue(store.profile.campaignComplete)
        XCTAssertNil(store.profile.currentLevel)
    }

    func testTicketCapOnFirstClear() throws {
        var p = store.profile
        p.hintBalance = HintEconomy.maxBalance
        store.replaceForFixture(p)
        let def = try level(1)
        XCTAssertTrue(store.startRun(level: def))
        var s = LevelFactory.initialState(for: def)
        s.status = .won
        XCTAssertTrue(store.commitOutcome(level: def, state: s))
        XCTAssertEqual(store.profile.hintBalance, HintEconomy.maxBalance)
        XCTAssertEqual(store.profile.lastResult?.creditedTickets, 0)
        XCTAssertTrue(store.profile.firstClearLedger.contains("1:1"))
    }

    func testDailyOncePerUTCDayAndAtomicReceipt() {
        XCTAssertTrue(store.dailyEligible)
        guard let r = store.claimDaily(symbols: [.heart, .heart, .heart], day: store.currentDay) else { return XCTFail() }
        XCTAssertEqual(r.nominalReward, 5)
        XCTAssertEqual(store.profile.hintBalance, 8)
        XCTAssertEqual(store.profile.highestClaimedDay, store.currentDay)
        XCTAssertFalse(store.dailyEligible)
        XCTAssertNil(store.claimDaily())
        XCTAssertEqual(store.unacknowledgedReceipt?.id, r.id)
        store.acknowledge(receiptID: r.id)
        XCTAssertNil(store.unacknowledgedReceipt)
        // Перевод часов назад — бонус недоступен.
        clock.date = clock.date.addingTimeInterval(-86_400 * 3)
        XCTAssertFalse(store.dailyEligible)
        // Следующий UTC-день.
        clock.date = Date(timeIntervalSince1970: Double((r.dayIndex + 1) * 86_400) + 5)
        XCTAssertTrue(store.dailyEligible)
    }

    func testDailyCapAtMaxBalance() {
        var p = store.profile
        p.hintBalance = HintEconomy.maxBalance - 1
        store.replaceForFixture(p)
        let r = store.claimDaily(symbols: [.star, .star, .star], day: store.currentDay)
        XCTAssertEqual(r?.creditedAmount, 1)
        XCTAssertEqual(store.profile.hintBalance, HintEconomy.maxBalance)
    }

    func testSaveFailureKeepsDurableSnapshotAndRetryUsesSameTransaction() {
        let before = store.profile
        store.repo.injectWriteFailure = true
        XCTAssertNil(store.claimDaily(symbols: [.bell, .star, .clover], day: store.currentDay))
        XCTAssertEqual(store.profile, before)
        XCTAssertNotNil(store.pending)
        let txID = store.pending!.id
        store.repo.injectWriteFailure = false
        XCTAssertTrue(store.retryPending())
        XCTAssertEqual(store.profile.lastTransactionID, txID)
        XCTAssertEqual(store.profile.hintBalance, 4)
        XCTAssertNil(store.pending)
        // Повтор той же транзакции не начисляет повторно.
        XCTAssertTrue(store.retryPending())
        XCTAssertEqual(store.profile.hintBalance, 4)
    }

    func testDiscardPendingReturnsToDurableSnapshot() {
        store.repo.injectWriteFailure = true
        XCTAssertFalse(store.resetProgress())
        store.discardPending()
        XCTAssertNil(store.pending)
        XCTAssertEqual(store.profile.hintBalance, 3)
    }

    func testResetKeepsDailyWatermarkAndReceipts() {
        _ = store.claimDaily(symbols: [.bell, .bell, .star], day: store.currentDay)
        var p = store.profile
        p.bestByLevel["1"] = LevelBest(stars: 3, minMovesUsed: 5, levelVersion: 1, turnsUsed: 0)
        p.hintBalance = 42
        store.replaceForFixture(p)
        XCTAssertTrue(store.resetProgress())
        XCTAssertEqual(store.profile.completedLevels, 0)
        XCTAssertEqual(store.profile.hintBalance, 3)
        XCTAssertEqual(store.profile.highestClaimedDay, store.currentDay)
        XCTAssertEqual(store.profile.recentReceipts.count, 1)
        XCTAssertNil(store.profile.activeRun)
        XCTAssertFalse(store.dailyEligible)
    }

    func testImportNeverLowersHighWatermarkAndKeepsTodayReceipt() throws {
        _ = store.claimDaily(symbols: [.bell, .bell, .star], day: store.currentDay)
        var src = DebugFixture.profile(completed: 30, tickets: 9)
        src.highestClaimedDay = store.currentDay - 10
        let (data, name) = try BackupCodec.export(src, now: clock.now())
        let preview = try BackupCodec.validate(data: data, fileName: name, levels: BundleLevelRepository(), now: clock.now())
        XCTAssertTrue(store.applyImport(preview))
        XCTAssertEqual(store.profile.completedLevels, 30)
        XCTAssertEqual(store.profile.hintBalance, 9)
        XCTAssertEqual(store.profile.highestClaimedDay, store.currentDay)
        XCTAssertTrue(store.profile.recentReceipts.contains { $0.dayIndex == store.currentDay })
    }
}

final class BackupCodecTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_683_200)
    let levels = BundleLevelRepository()

    func testRoundTripAndFileName() throws {
        let p = DebugFixture.profile(completed: 45, tickets: 12)
        let (data, name) = try BackupCodec.export(p, now: now)
        XCTAssertEqual(name, "VelvetCascade_Backup_2026-09-29.json")
        XCTAssertLessThan(data.count, BackupCodec.maxBytes)
        let pr = try BackupCodec.validate(data: data, fileName: name, levels: levels, now: now)
        XCTAssertEqual(pr.completedLevels, 45)
        XCTAssertEqual(pr.hintTickets, 12)
        XCTAssertEqual(pr.stars, p.totalStars)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertFalse(text.lowercased().contains("api"))
    }

    func testChecksumMismatchRejected() throws {
        let (data, name) = try BackupCodec.export(DebugFixture.profile(completed: 5), now: now)
        var text = String(data: data, encoding: .utf8)!
        text = text.replacingOccurrences(of: "\"hintBalance\" : 3", with: "\"hintBalance\" : 999")
        XCTAssertThrowsError(try BackupCodec.validate(data: Data(text.utf8), fileName: name, levels: levels, now: now)) {
            XCTAssertEqual($0 as? ImportError, .checksumMismatch)
        }
    }

    func testUnknownSchemaTooLargeAndGarbage() {
        XCTAssertThrowsError(try BackupCodec.validate(data: Data("{\"schemaVersion\": 9}".utf8), fileName: "x", levels: levels, now: now)) {
            XCTAssertEqual($0 as? ImportError, .unknownSchema)
        }
        XCTAssertThrowsError(try BackupCodec.validate(data: Data(repeating: 32, count: BackupCodec.maxBytes + 1), fileName: "x", levels: levels, now: now)) {
            XCTAssertEqual($0 as? ImportError, .tooLarge)
        }
        XCTAssertThrowsError(try BackupCodec.validate(data: Data("not json".utf8), fileName: "x", levels: levels, now: now)) {
            XCTAssertEqual($0 as? ImportError, .unreadable)
        }
    }

    private func roundTrip(_ mutate: (inout Profile) -> Void) throws -> ImportPreview {
        var p = DebugFixture.profile(completed: 10)
        mutate(&p)
        let (data, name) = try BackupCodec.export(p, now: now)
        return try BackupCodec.validate(data: data, fileName: name, levels: levels, now: now)
    }

    func testInvalidValuesRejected() {
        XCTAssertThrowsError(try roundTrip { $0.bestByLevel["181"] = LevelBest(stars: 1, minMovesUsed: 1, levelVersion: 1, turnsUsed: 0) })
        XCTAssertThrowsError(try roundTrip { $0.bestByLevel["3"]?.stars = 4 })
        XCTAssertThrowsError(try roundTrip { $0.hintBalance = 1_000_001 })
        XCTAssertThrowsError(try roundTrip { $0.hintBalance = -1 })
        XCTAssertThrowsError(try roundTrip { $0.bestByLevel["50"] = LevelBest(stars: 1, minMovesUsed: 1, levelVersion: 1, turnsUsed: 0) })  // пропуск последовательности
        XCTAssertThrowsError(try roundTrip { $0.firstClearLedger.append("1:1") })   // duplicate
        XCTAssertThrowsError(try roundTrip {
            $0.recentReceipts = [DailyReceipt(id: "a", dayIndex: 1, symbols: [.heart, .heart, .heart], nominalReward: 2,
                                              creditedAmount: 2, claimedAtUTC: Date(timeIntervalSince1970: 1_780_000_000), acknowledged: true, schemaVersion: 1)]
        })
        XCTAssertThrowsError(try roundTrip { $0.createdAt = Date(timeIntervalSince1970: 100) })
    }

    func testIncompatibleActiveRunIsDroppedButProgressImported() throws {
        let def = try levels.load(11)
        let pr = try roundTrip { p in
            p.activeRun = ActiveRun(runID: "r", attemptID: "a", levelID: 11, levelVersion: 99, initialSeed: def.seed,
                                    state: LevelFactory.initialState(for: def), hintsUsed: 0, startedAt: Date(timeIntervalSince1970: 1_790_000_000))
        }
        XCTAssertEqual(pr.droppedIncompatibleRun, 11)
        XCTAssertNil(pr.profile.activeRun)
        XCTAssertEqual(pr.completedLevels, 10)
    }

    func testCorruptActiveRunBoardRejected() throws {
        let def = try levels.load(11)
        XCTAssertThrowsError(try roundTrip { p in
            var s = LevelFactory.initialState(for: def)
            s.board.cells[0].playable = !s.board.cells[0].playable
            s.q = 7
            p.activeRun = ActiveRun(runID: "r", attemptID: "a", levelID: 11, levelVersion: 1, initialSeed: def.seed,
                                    state: s, hintsUsed: 0, startedAt: Date(timeIntervalSince1970: 1_790_000_000))
        })
    }
}

final class AtomicRepositoryTests: XCTestCase {
    func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("vc-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testSaveLoadAndBackupRotation() throws {
        let dir = tempDir()
        let repo = AtomicProgressRepository(directory: dir)
        var p = Profile.fresh()
        p.hintBalance = 7
        try repo.save(p)
        p.hintBalance = 8
        try repo.save(p)
        guard case .loaded(let loaded) = repo.load() else { return XCTFail() }
        XCTAssertEqual(loaded.hintBalance, 8)
        let backup = try AtomicProgressRepository.decoder.decode(Profile.self, from: Data(contentsOf: repo.backupURL))
        XCTAssertEqual(backup.hintBalance, 7)
    }

    func testCorruptMainOffersVerifiedBackupWithoutErasing() throws {
        let dir = tempDir()
        let repo = AtomicProgressRepository(directory: dir)
        var p = Profile.fresh()
        p.hintBalance = 5
        try repo.save(p)
        try repo.save(p)
        try Data("{broken".utf8).write(to: repo.mainURL)
        guard case .needsRestore(let backup, _) = repo.load() else { return XCTFail() }
        XCTAssertEqual(backup.hintBalance, 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.mainURL.path))
    }

    func testCorruptWithoutBackupIsReportedNotReset() throws {
        let dir = tempDir()
        let repo = AtomicProgressRepository(directory: dir)
        try Data("garbage".utf8).write(to: repo.mainURL)
        guard case .unrecoverable = repo.load() else { return XCTFail() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.mainURL.path))
    }

    func testUnknownSchemaTreatedAsUnreadable() throws {
        let dir = tempDir()
        let repo = AtomicProgressRepository(directory: dir)
        var p = Profile.fresh()
        p.schemaVersion = 99
        try AtomicProgressRepository.encoder.encode(p).write(to: repo.mainURL)
        guard case .unrecoverable = repo.load() else { return XCTFail() }
    }
}

final class BundledLevelTests: XCTestCase {
    /// Все 180 уровней в бандле: валидны, воспроизводимы движком, 9×20, уникальные поля.
    func testAll180LevelsValidateAndReplay() throws {
        let repo = BundleLevelRepository()
        var boards = Set<String>()
        for id in 1...180 {
            let def = try repo.load(id)
            XCTAssertEqual(def.id, id)
            XCTAssertEqual(def.worldID, (id - 1) / 20 + 1)
            XCTAssertTrue(LevelValidator.validate(def).isEmpty, "L\(id)")
            let r = LevelValidator.replay(def)
            XCTAssertTrue(r.ok, "L\(id): \(r.failure ?? "")")
            if def.turnBrief.contains("!") {
                XCTAssertGreaterThanOrEqual(def.solutionTrace.filter { $0.action == "rotate" }.count, def.requiredTurns, "L\(id)")
            }
            boards.insert(def.initialOccupants.map { "\($0.x)\($0.y)\($0.type)\($0.color?.rawValue ?? -1)" }.joined())
        }
        XCTAssertEqual(boards.count, 180)
        XCTAssertNil(repo.url(for: 181))
    }

    func testMediaManifestsResolve() {
        let m = MediaManifestRepository()
        XCTAssertEqual(m.art.count, 40)
        for e in m.art { XCTAssertNotNil(Bundle.main.url(forResource: (e.file as NSString).deletingPathExtension, withExtension: "png"), e.file) }
        XCTAssertEqual(m.audio.count, 44)
        for e in m.audio {
            let base = (e.runtimeFile as NSString).deletingPathExtension, ext = (e.runtimeFile as NSString).pathExtension
            XCTAssertNotNil(Bundle.main.url(forResource: base, withExtension: ext), e.runtimeFile)
        }
        XCTAssertEqual(m.reelRects.count, 3)
    }

    func testSecureRandomBounded() {
        var seen = Set<UInt32>()
        for _ in 0..<500 {
            let v = SecureRandom.uniform(below: 5)
            XCTAssertLessThan(v, 5)
            seen.insert(v)
        }
        XCTAssertEqual(seen.count, 5)
    }
}
