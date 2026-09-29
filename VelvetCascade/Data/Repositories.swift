// Repositories.swift — Data-слой: атомарное хранилище профиля с backup, настройки, уровни и манифесты.
//
// Хранение: versioned local JSON snapshot. Запись: temporary-write → fsync → replace, перед заменой
// предыдущая исправная версия копируется в backup. Одна последовательная очередь записи исключает
// конкурентное начисление. Ошибка записи не меняет durable snapshot.

import Foundation
import VelvetDomain

enum StorageError: Error, Equatable {
    case writeFailed(String)
    case encodeFailed
    case injected
}

enum ProfileLoadOutcome {
    case loaded(Profile)
    case fresh(Profile)
    /// Основной файл повреждён; найден проверенный backup — предложить восстановление.
    case needsRestore(backup: Profile, diagnosticID: String)
    /// Нет ни основного, ни backup: не обнулять молча, а сообщить.
    case unrecoverable(diagnosticID: String)
}

final class AtomicProgressRepository {
    let directory: URL
    var mainURL: URL { directory.appendingPathComponent("profile.json") }
    var backupURL: URL { directory.appendingPathComponent("profile.backup.json") }
    private let queue = DispatchQueue(label: "app.VelvetCascade.progress-write")
    /// DEBUG fixture: принудительная ошибка записи (Recovery → Save Failed).
    var injectWriteFailure = false
    let inMemory: Bool
    private var memoryData: Data?

    init(directory: URL? = nil, inMemory: Bool = false) {
        self.inMemory = inMemory
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("VelvetCascade", isDirectory: true)
        }
        if !inMemory {
            try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func load() -> ProfileLoadOutcome {
        if inMemory {
            if let d = memoryData, let p = try? Self.decoder.decode(Profile.self, from: d) { return .loaded(p) }
            return .fresh(.fresh())
        }
        let fm = FileManager.default
        let mainExists = fm.fileExists(atPath: mainURL.path)
        if mainExists, let data = try? Data(contentsOf: mainURL), let p = decodeValid(data) {
            return .loaded(p)
        }
        let diag = "VC-LOAD-" + String(UUID().uuidString.prefix(8))
        if fm.fileExists(atPath: backupURL.path), let data = try? Data(contentsOf: backupURL), let p = decodeValid(data) {
            if mainExists { return .needsRestore(backup: p, diagnosticID: diag) }
            return .loaded(p)
        }
        if mainExists { return .unrecoverable(diagnosticID: diag) }
        return .fresh(.fresh())
    }

    private func decodeValid(_ data: Data) -> Profile? {
        guard let p = try? Self.decoder.decode(Profile.self, from: data), p.schemaVersion == Profile.currentSchema else { return nil }
        return p
    }

    /// Атомарная запись. Синхронна относительно вызывающего (выполняется на очереди записи).
    func save(_ profile: Profile) throws {
        try queue.sync {
            if injectWriteFailure { throw StorageError.injected }
            guard let data = try? Self.encoder.encode(profile) else { throw StorageError.encodeFailed }
            if inMemory { memoryData = data; return }
            let fm = FileManager.default
            let tmp = directory.appendingPathComponent("profile.\(UUID().uuidString).tmp")
            do {
                try data.write(to: tmp, options: [.atomic])
                if let h = FileHandle(forWritingAtPath: tmp.path) { try? h.synchronize(); try? h.close() }
                if fm.fileExists(atPath: mainURL.path) {
                    // Предыдущая исправная версия → backup.
                    if let old = try? Data(contentsOf: mainURL), decodeValid(old) != nil {
                        let btmp = directory.appendingPathComponent("backup.\(UUID().uuidString).tmp")
                        try old.write(to: btmp, options: [.atomic])
                        if fm.fileExists(atPath: backupURL.path) {
                            _ = try fm.replaceItemAt(backupURL, withItemAt: btmp)
                        } else {
                            try fm.moveItem(at: btmp, to: backupURL)
                        }
                    }
                    _ = try fm.replaceItemAt(mainURL, withItemAt: tmp)
                } else {
                    try fm.moveItem(at: tmp, to: mainURL)
                }
            } catch {
                try? fm.removeItem(at: tmp)
                throw StorageError.writeFailed((error as NSError).domain + ":" + String((error as NSError).code))
            }
        }
    }

    func restoreBackup() throws -> Profile {
        guard let data = try? Data(contentsOf: backupURL), let p = decodeValid(data) else {
            throw StorageError.writeFailed("backup-unreadable")
        }
        try save(p)
        return p
    }

    func archiveBackup() {
        guard !inMemory else { return }
        let fm = FileManager.default
        let archived = directory.appendingPathComponent("profile.backup.archived.\(Int(Date().timeIntervalSince1970)).json")
        try? fm.copyItem(at: backupURL, to: archived)
    }

    func wipeCorruptedMain() {
        guard !inMemory else { return }
        let fm = FileManager.default
        let quarantine = directory.appendingPathComponent("profile.corrupt.\(Int(Date().timeIntervalSince1970)).json")
        try? fm.moveItem(at: mainURL, to: quarantine)
    }
}

final class SettingsRepository {
    private let key = "vc.settings.v1"
    let defaults: UserDefaults
    let inMemory: Bool
    private var memory = AppSettings()

    init(defaults: UserDefaults = .standard, inMemory: Bool = false) {
        self.defaults = defaults
        self.inMemory = inMemory
    }

    func load() -> AppSettings {
        if inMemory { return memory }
        guard let data = defaults.data(forKey: key), let s = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return s
    }

    func save(_ s: AppSettings) {
        if inMemory { memory = s; return }
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
    }
}

// MARK: - Levels

enum LevelLoadError: Error {
    case missing(Int)
    case corrupt(Int, String)
    case invalid(Int, [String])
}

final class BundleLevelRepository {
    private var cache: [Int: LevelDefinition] = [:]
    private let lock = NSLock()
    let bundle: Bundle
    /// DEBUG fixture: уровень, который принудительно считается повреждённым.
    var forcedInvalidLevel: Int?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func url(for id: Int) -> URL? {
        bundle.url(forResource: String(format: "level_%03d", id), withExtension: "json")
    }

    /// Загрузка без полной валидации (для карты мира).
    func summary(_ id: Int) -> LevelDefinition? {
        try? load(id, validate: false)
    }

    /// Загрузка с проверкой LevelDefinition до запуска.
    func load(_ id: Int, validate: Bool = true) throws -> LevelDefinition {
        lock.lock()
        if let d = cache[id] {
            lock.unlock()
            if validate { try check(d) }
            return d
        }
        lock.unlock()
        guard let url = url(for: id) else { throw LevelLoadError.missing(id) }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw LevelLoadError.missing(id) }
        let def: LevelDefinition
        do { def = try JSONDecoder().decode(LevelDefinition.self, from: data) } catch {
            throw LevelLoadError.corrupt(id, "decode")
        }
        lock.lock()
        cache[id] = def
        lock.unlock()
        if validate { try check(def) }
        return def
    }

    private func check(_ def: LevelDefinition) throws {
        if forcedInvalidLevel == def.id { throw LevelLoadError.invalid(def.id, ["debug-fixture"]) }
        let issues = LevelValidator.validate(def, campaignVersion: Profile.campaignVersion)
        if !issues.isEmpty { throw LevelLoadError.invalid(def.id, issues.map { $0.code }) }
    }
}

// MARK: - Media manifests

struct NormRect: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

struct ArtManifestEntry: Codable {
    var id: String
    var file: String
    var displayRole: String?
    var pixelWidth: Int
    var pixelHeight: Int
    var hasAlpha: Bool
    var provenance: String
    var qaStatus: String?
    var reelRects: [NormRect]?
    var faceRect: NormRect?
}

struct AudioManifestEntry: Codable {
    var id: String
    var kind: String?
    var bus: String
    var runtimeFile: String
    var priority: String
    var eventMapping: String?
    var isLoop: Bool?
    var provider: String
    var model: String?
    var qaStatus: String?
    var pitchVariantsSemitones: [Double]?
}

struct AudioManifest: Codable {
    var entries: [AudioManifestEntry]
    var releaseReady: Bool?
}

final class MediaManifestRepository {
    let art: [ArtManifestEntry]
    let audio: [AudioManifestEntry]

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "art_manifest", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let entries = try? JSONDecoder().decode([ArtManifestEntry].self, from: data) {
            art = entries
        } else {
            art = []
        }
        if let url = bundle.url(forResource: "audio_manifest", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode(AudioManifest.self, from: data) {
            audio = m.entries
        } else {
            audio = []
        }
    }

    var reelRects: [NormRect] {
        art.first { $0.id == "VC23" }?.reelRects ?? [
            NormRect(x: 0.17, y: 0.36, w: 0.19, h: 0.36),
            NormRect(x: 0.405, y: 0.36, w: 0.19, h: 0.36),
            NormRect(x: 0.64, y: 0.36, w: 0.19, h: 0.36),
        ]
    }

    var elevenLabsCount: Int { audio.filter { $0.provider.hasPrefix("ElevenLabs") }.count }
    var substituteCount: Int { audio.filter { !$0.provider.hasPrefix("ElevenLabs") }.count }
    var artProvenanceSummary: [String] { Array(Set(art.map { $0.provenance })).sorted() }
}
