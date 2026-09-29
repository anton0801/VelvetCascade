// BackupCodec.swift — экспорт/импорт прогресса одним JSON с checksum.
//
// Checksum (SHA-256 канонической сериализации профиля) — обнаружение повреждения, не защита от владельца.
// Все проверки выполняются ДО изменения базы. Код и пути из JSON не выполняются.

import CryptoKit
import Foundation
import VelvetDomain

struct BackupEnvelope: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var profile: Profile
    var checksum: String
}

struct ImportPreview: Equatable {
    var fileName: String
    var exportDate: Date
    var completedLevels: Int
    var stars: Int
    var hintTickets: Int
    var activeLevel: Int?
    /// Незавершённая попытка из старой levelVersion: прогресс импортируется, попытку предложено начать заново.
    var droppedIncompatibleRun: Int?
    var profile: Profile
}

enum ImportError: Error, Equatable {
    case tooLarge
    case unreadable
    case unknownSchema
    case checksumMismatch
    case invalid(String)

    var reason: String {
        switch self {
        case .tooLarge: return "The file is larger than 2 MB."
        case .unreadable: return "The file is not a Velvet Cascade backup."
        case .unknownSchema: return "This backup was made by an unknown version."
        case .checksumMismatch: return "The file appears to be damaged."
        case .invalid: return "The progress data in this file is inconsistent."
        }
    }
}

enum BackupCodec {
    static let maxBytes = 2 * 1024 * 1024

    static func canonicalProfileData(_ p: Profile) throws -> Data {
        try AtomicProgressRepository.encoder.encode(p)
    }

    static func checksum(_ p: Profile) throws -> String {
        let digest = SHA256.hash(data: try canonicalProfileData(p))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func fileName(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "VelvetCascade_Backup_\(f.string(from: date)).json"
    }

    /// Экспорт без API-ключей и медиа.
    static func export(_ profile: Profile, now: Date = Date()) throws -> (data: Data, fileName: String) {
        let env = BackupEnvelope(schemaVersion: Profile.currentSchema, exportedAt: now, profile: profile,
                                 checksum: try checksum(profile))
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        let data = try e.encode(env)
        guard data.count <= maxBytes else { throw ImportError.tooLarge }
        return (data, fileName(for: now))
    }

    static func validate(data: Data, fileName: String, levels: BundleLevelRepository, now: Date = Date()) throws -> ImportPreview {
        guard data.count <= maxBytes else { throw ImportError.tooLarge }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ImportError.unreadable }
        guard let schema = json["schemaVersion"] as? Int else { throw ImportError.unreadable }
        guard schema == Profile.currentSchema else { throw ImportError.unknownSchema }
        let env: BackupEnvelope
        do { env = try AtomicProgressRepository.decoder.decode(BackupEnvelope.self, from: data) } catch {
            throw ImportError.unreadable
        }
        var p = env.profile
        guard p.schemaVersion == Profile.currentSchema else { throw ImportError.unknownSchema }
        guard (try? checksum(p)) == env.checksum else { throw ImportError.checksumMismatch }
        guard p.campaignVersion == Profile.campaignVersion else { throw ImportError.invalid("campaign") }

        let earliest = Date(timeIntervalSince1970: 1_577_836_800)   // 2020-01-01
        let latest = now.addingTimeInterval(86_400 * 2)
        func validDate(_ d: Date?) -> Bool {
            guard let d else { return true }
            let t = d.timeIntervalSince1970
            return t.isFinite && d >= earliest && d <= latest
        }
        guard validDate(env.exportedAt), validDate(p.createdAt) else { throw ImportError.invalid("timestamp") }
        guard (0...HintEconomy.maxBalance).contains(p.hintBalance) else { throw ImportError.invalid("hints") }

        for (k, best) in p.bestByLevel {
            guard let id = Int(k), (1...180).contains(id) else { throw ImportError.invalid("level id") }
            guard (1...3).contains(best.stars) else { throw ImportError.invalid("stars") }
            guard (0...200).contains(best.minMovesUsed), (0...50).contains(best.turnsUsed), best.levelVersion >= 1 else {
                throw ImportError.invalid("best")
            }
        }
        for (k, a) in p.attemptsSummary {
            guard let id = Int(k), (1...180).contains(id) else { throw ImportError.invalid("attempt id") }
            guard a.attempts >= 0, a.wins >= 0, a.wins <= a.attempts, a.attempts < 1_000_000, validDate(a.lastPlayed) else {
                throw ImportError.invalid("attempts")
            }
        }
        // Уровни открываются последовательно: пройденный уровень N требует пройденного N−1.
        for k in p.bestByLevel.keys {
            let id = Int(k)!
            if id > 1 && p.bestByLevel[String(id - 1)] == nil { throw ImportError.invalid("sequence") }
        }
        guard Set(p.firstClearLedger).count == p.firstClearLedger.count else { throw ImportError.invalid("ledger dup") }
        for entry in p.firstClearLedger {
            let parts = entry.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (1...180).contains(parts[0]), parts[1] >= 1 else { throw ImportError.invalid("ledger") }
        }
        guard Set(p.recentReceipts.map { $0.id }).count == p.recentReceipts.count, p.recentReceipts.count <= 60 else {
            throw ImportError.invalid("receipts")
        }
        for r in p.recentReceipts {
            guard r.symbols.count == 3, r.dayIndex >= 0, r.nominalReward == DailyRewardPolicy.nominalReward(for: r.symbols),
                  (0...r.nominalReward).contains(r.creditedAmount), validDate(r.claimedAtUTC) else {
                throw ImportError.invalid("receipt")
            }
        }
        if let h = p.highestClaimedDay, h < 0 { throw ImportError.invalid("day") }

        var dropped: Int?
        if let run = p.activeRun {
            guard (1...180).contains(run.levelID), p.isUnlocked(run.levelID) else { throw ImportError.invalid("run level") }
            if let def = try? levels.load(run.levelID), def.levelVersion == run.levelVersion {
                guard isConsistent(run.state, with: def) else { throw ImportError.invalid("run board") }
            } else {
                // Несовместимая попытка старой версии уровня: прогресс сохраняем, попытку — нет.
                dropped = run.levelID
                p.activeRun = nil
            }
        }
        p.lastResult = nil
        return ImportPreview(fileName: fileName, exportDate: env.exportedAt, completedLevels: p.completedLevels,
                             stars: p.totalStars, hintTickets: p.hintBalance, activeLevel: p.activeRun?.levelID,
                             droppedIncompatibleRun: dropped, profile: p)
    }

    /// Маска, слои, ориентация, charge и ходы сохранённой попытки согласованы с уровнем.
    static func isConsistent(_ s: GameState, with def: LevelDefinition) -> Bool {
        guard s.levelID == def.id, s.board.n == def.n, s.board.cells.count == def.n * def.n else { return false }
        guard (0...3).contains(s.q), (0...GameState.maxCharge).contains(s.charge) else { return false }
        guard (0...def.initialMoves).contains(s.movesLeft), s.collected.count == 5, s.collected.allSatisfy({ $0 >= 0 }) else { return false }
        for y in 0..<def.n {
            for x in 0..<def.n {
                let c = Coord(x, y)
                let cell = s.board[c]
                if cell.playable != def.maskContains(c) { return false }
                if !cell.playable && (cell.occupant != nil || cell.blocker != nil || cell.overlay != nil || cell.floor != nil) { return false }
                if cell.blocker != nil && (cell.occupant != nil || cell.overlay != nil) { return false }
                if cell.overlay != nil && cell.occupant == nil { return false }
                if case .ice(let hp)? = cell.overlay, !(1...2).contains(hp) { return false }
                if case .crate(let hp)? = cell.blocker, !(1...2).contains(hp) { return false }
                if case .plate(let hp)? = cell.floor, !(1...2).contains(hp) { return false }
            }
        }
        let keyIDs = s.board.keyCoords.map { $0.keyID }
        guard Set(keyIDs).count == keyIDs.count, keyIDs.allSatisfy({ def.initialKeyIDs.contains($0) }) else { return false }
        return s.extractedKeyIDs.allSatisfy { def.initialKeyIDs.contains($0) }
    }
}
