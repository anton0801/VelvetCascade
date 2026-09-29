// AppEnvironment.swift — сборка зависимостей (repositories, services, stores) и общие UI-состояния.

import SwiftUI
import VelvetDomain

@MainActor
final class AppEnvironment: ObservableObject {
    let store: ProgressStore
    let router: Router
    let levels: BundleLevelRepository
    let media: MediaManifestRepository
    let audio: AudioService
    let haptics: HapticsService
    let clock: Clock
    let isFixture: Bool

    /// Активная игровая сессия (одна).
    @Published var session: GameSession?
    /// Recovery для ошибок импорта/уровня (Save Failed показывается по store.pending).
    @Published var recovery: RecoveryKind?
    /// Импорт: превью после валидации.
    @Published var importPreview: ImportPreview?
    /// Источник для «Got It» Handbook (если вход из Pause — вернуться в Pause).
    @Published var handbookFromPause = false
    @Published var systemReduceMotion = UIAccessibility.isReduceMotionEnabled
    /// DEBUG: принудительная ширина для проверки 320 pt.
    @Published var forcedWidth: CGFloat?

    init(fixture: DebugFixture? = nil) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-VCUITestFreshProfile") {
            // UI-тесты: чистая установка без удаления приложения.
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: base.appendingPathComponent("VelvetCascade", isDirectory: true))
            UserDefaults.standard.removeObject(forKey: "vc.settings.v1")
        }
        #endif
        let clock: Clock = fixture?.clock ?? SystemClock()
        let repo = AtomicProgressRepository(inMemory: fixture != nil)
        let settingsRepo = SettingsRepository(inMemory: fixture != nil)
        self.clock = clock
        self.isFixture = fixture != nil
        store = ProgressStore(repo: repo, settingsRepo: settingsRepo, clock: clock)
        levels = BundleLevelRepository()
        media = MediaManifestRepository()
        audio = AudioService()
        haptics = HapticsService()
        router = Router(root: .home)
        applySettings(store.settings)
        store.onSettingsChanged = { [weak self] s in self?.applySettings(s) }
        if let fixture {
            fixture.apply(to: self)
        } else {
            router.reset([store.profile.onboardingCompleted ? .home : .welcome])
        }
        NotificationCenter.default.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.systemReduceMotion = UIAccessibility.isReduceMotionEnabled }
        }
    }

    func applySettings(_ s: AppSettings) {
        audio.apply(music: s.musicVolume, sfx: s.sfxVolume, ambience: s.ambienceVolume)
        haptics.enabled = s.haptics
    }

    var reduceMotion: Bool {
        switch store.settings.reduceMotion {
        case .on: return true
        case .off: return false
        case .system: return systemReduceMotion
        }
    }

    // MARK: Navigation helpers

    func tap() { audio.play(.uiTap) }
    func back() { audio.play(.uiBack); router.pop() }

    /// Play/Resume с Home, карты или Brief: Resume ведёт к Pause сохранённой попытки.
    func resumeActiveRun() {
        guard let run = store.profile.activeRun else { return }
        do {
            let level = try levels.load(run.levelID)
            guard level.levelVersion == run.levelVersion else {
                // Старая версия уровня: прогресс цел, попытку предложено начать заново.
                _ = store.abandonRun()
                router.push(.levelBrief(level: run.levelID))
                return
            }
            let s = GameSession(env: self, level: level, run: run)
            s.paused = true
            session = s
            router.push(.gameplay(runID: run.runID))
        } catch {
            recovery = .levelInvalid(levelID: run.levelID, diagnosticID: Self.diagnostic("LVL"))
        }
    }

    /// Старт уровня: проверка LevelDefinition → новый ActiveRun (замена только после подтверждения).
    func startLevel(_ id: Int, replaceConfirmed: Bool = false) {
        if let run = store.profile.activeRun, !replaceConfirmed {
            router.modal = .replaceRun(level: run.levelID == id ? id : id)
            pendingStartLevel = id
            return
        }
        do {
            let level = try levels.load(id)
            guard store.startRun(level: level), let run = store.profile.activeRun else { return }
            session = GameSession(env: self, level: level, run: run)
            audio.play(.curtainOpen)
            switch router.current {
            case .gameplay, .curtainCall, .oneMoreAct:
                router.replaceTop(.gameplay(runID: run.runID))
            default:
                router.push(.gameplay(runID: run.runID))
            }
        } catch {
            recovery = .levelInvalid(levelID: id, diagnosticID: Self.diagnostic("LVL"))
        }
    }

    var pendingStartLevel: Int?

    static func diagnostic(_ prefix: String) -> String {
        "VC-\(prefix)-" + String(UUID().uuidString.prefix(6))
    }

    func musicForCurrentRoute() {
        switch router.current {
        case .gameplay:
            if let s = session {
                audio.setMusic(s.level.worldID == 9 ? .finale : .gameplay)
                audio.setAmbience(.footlights)
            }
        case .daily, .dailyReward:
            audio.setAmbience(.theatre)
        default:
            audio.setMusic(.menu)
            audio.setAmbience(.theatre)
        }
    }

    // MARK: Lifecycle

    func didEnterBackground() {
        session?.enterBackground()
        audio.suspend()
    }

    func didBecomeActive() {
        audio.resume()
        musicForCurrentRoute()
        objectWillChange.send()
    }
}
