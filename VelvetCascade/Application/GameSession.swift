// GameSession.swift — сценарии игрового экрана: ExecuteAction, PreviewTurn, RequestHint, RestartRun, CommitResult.
//
// Порядок: Domain рассчитывает новое settled-состояние → ProgressStore атомарно сохраняет его
// (или результат с наградой) → renderer проигрывает события. События анимации Domain не меняют.
// Ввод блокируется до завершения commit и анимации. После background всегда Pause.

import SwiftUI
import VelvetDomain

struct BoardEffect: Identifiable, Equatable {
    enum Kind: Equatable {
        case line(Coord, VelvetDomain.Axis)
        case burst(Coord, Int)
        case band(Coord)
        case colorClear(Coord, [Coord])
        case allCells
        case sparks(Coord)
    }
    let id = UUID()
    let kind: Kind
}

@MainActor
final class GameSession: ObservableObject {
    enum Phase: Equatable { case idle, selected, resolving, rotating, committing, win, noMoves, error }

    unowned let env: AppEnvironment
    let level: LevelDefinition
    let runID: String

    /// Durable settled-модель (после commit).
    @Published private(set) var state: GameState
    // Отображение (renderer)
    @Published var board: Board
    @Published var displayAngle: Double
    @Published var hudMoves: Int
    @Published var hudCharge: Int
    @Published var hudCollected: [Int]
    @Published var hudExtracted: [Int]
    @Published var hudQ: Int
    @Published var phase: Phase = .idle
    @Published var selected: Coord?
    @Published var hintSwap: (Coord, Coord)?
    @Published var hintTurn = false
    @Published var turnSuggested = false
    @Published var preview: TurnPreview?
    @Published var paused = false
    @Published var effects: [BoardEffect] = []
    @Published var sweepHighlight: [Coord] = []
    @Published var spawnDrops: [Int: Int] = [:]
    @Published var exitingKeys: [Int: Direction] = [:]
    @Published var curtainsClosed = false
    @Published var beamVisible = false
    @Published var banner: TutorialStep?
    @Published var toast: String?
    @Published var freeHintReady = false
    @Published var invalidPair: (Coord, Coord)?
    @Published var infoCell: Coord?
    @Published var restartConfirm = false
    @Published var crossfadeToken = 0

    var hintsUsed: Int
    var pendingPause = false
    /// Демо (обучение, Handbook): тот же движок и renderer, изолировано от профиля.
    let isDemo: Bool
    var onDemoFinished: ((GameState) -> Void)?
    private var animationTask: Task<Void, Never>?
    private var idleTimer: Timer?
    private var idleSeconds = 0
    private var freeHintRevision: Int?
    private var shownTutorialTriggers = Set<String>()
    private var turnReadyAnnounced = false

    init(env: AppEnvironment, level: LevelDefinition, run: ActiveRun, demo: Bool = false) {
        self.env = env
        self.isDemo = demo
        self.level = level
        self.runID = run.runID
        self.state = run.state
        self.board = run.state.board
        self.displayAngle = GameSession.continuousAngle(run.state)
        self.hudMoves = run.state.movesLeft
        self.hudCharge = run.state.charge
        self.hudCollected = run.state.collected
        self.hudExtracted = run.state.extractedKeyIDs
        self.hudQ = run.state.q
        self.hintsUsed = run.hintsUsed
        turnReadyAnnounced = run.state.charge >= 12
        let firstVisit = !demo && run.state.revision == 0 && !env.store.profile.isCompleted(level.id)
        if firstVisit, let step = level.tutorialSteps.first(where: { $0.trigger == "start" }) {
            banner = step
            shownTutorialTriggers.insert("start")
        }
        if !demo { startIdleTimer() }
    }

    /// Демо-сессия на произвольном поле (n может быть 3…8).
    static func demo(env: AppEnvironment, state: GameState, id: Int = 0) -> GameSession {
        let level = LevelDefinition(
            id: id, campaignVersion: 1, worldID: 1, levelVersion: 1, title: "Demo", shape: "S6", n: state.board.n,
            mask: (0..<state.board.n).map { y in String((0..<state.board.n).map { x in state.board[Coord(x, y)].playable ? "1" : "0" }) },
            initialOrientation: 0, initialMoves: state.initialMoves, initialCharge: state.charge,
            fiveColorPalette: GemColor.allCases, initialOccupants: [], floors: [], overlays: [], blockers: [],
            exitPorts: state.exitPorts, shutterSwitchLinks: state.shutterLinks, objectives: state.objectives,
            rngAlgorithmVersion: 1, seed: state.rng.state, tutorialSteps: [], solutionTrace: [], authoredDifficulty: 1,
            playtestStatus: "demo", turnBrief: "0", requiredTurns: 0, newMechanic: nil, newMechanicTopic: nil)
        let run = ActiveRun(runID: "demo-\(id)", attemptID: "demo", levelID: id, levelVersion: 1, initialSeed: state.rng.state,
                            state: state, hintsUsed: 0, startedAt: Date())
        return GameSession(env: env, level: level, run: run, demo: true)
    }

    /// Перезапуск демо с исходного состояния.
    func resetDemo(_ s: GameState) {
        animationTask?.cancel()
        state = s
        board = s.board
        displayAngle = GameSession.continuousAngle(s)
        hudMoves = s.movesLeft
        hudCharge = s.charge
        hudCollected = s.collected
        hudExtracted = s.extractedKeyIDs
        hudQ = s.q
        effects = []
        sweepHighlight = []
        spawnDrops = [:]
        exitingKeys = [:]
        selected = nil
        preview = nil
        curtainsClosed = false
        beamVisible = false
        phase = .idle
    }

    /// Демо выполняет действие сразу (без профиля).
    func demoPerform(_ kind: GameActionKind) {
        perform(kind)
    }

    deinit {
        idleTimer?.invalidate()
        animationTask?.cancel()
    }

    var n: Int { level.n }

    /// Непрерывный угол сцены: каждый Turn добавляет +90° (по часовой стрелке), q = угол/90 mod 4.
    static func continuousAngle(_ s: GameState) -> Double {
        let initial = ((s.q - s.turnsUsed) % 4 + 4) % 4
        return Double(initial + s.turnsUsed) * 90
    }
    var isInputLocked: Bool { !(phase == .idle || phase == .selected) || paused || preview != nil || env.store.isCommitting }

    // MARK: Input

    /// Экранная клетка → локальная (inverseR).
    func localCell(fromScreen c: Coord) -> Coord {
        BoardTransform.toLocal(c, q: state.q, n: n)
    }

    func tap(local c: Coord) {
        guard !isInputLocked else { return }
        env.audio.userInteracted()
        dismissTransient()
        if let s = selected {
            if s == c { selected = nil; phase = .idle; return }
            if s.isOrthogonalNeighbor(of: c) {
                selected = nil
                phase = .idle
                attemptSwap(from: s, to: c)
                return
            }
        }
        if board.isPlayable(c), board[c].isSwappable {
            selected = c
            phase = .selected
            env.haptics.swap()
            env.audio.play(.uiTap)
        } else {
            selected = nil
            phase = .idle
            if board.isPlayable(c) { infoCell = c }
        }
    }

    func swipe(fromLocal c: Coord, screenDirection d: Direction) {
        guard !isInputLocked else { return }
        env.audio.userInteracted()
        dismissTransient()
        let local = BoardTransform.localDirection(fromScreen: d, q: state.q)
        selected = nil
        phase = .idle
        attemptSwap(from: c, to: c.offset(local))
    }

    func longPress(local c: Coord) {
        guard board.isPlayable(c) else { return }
        infoCell = c
    }

    private func dismissTransient() {
        infoCell = nil
        toast = nil
        if banner?.trigger == "start" { banner = nil }
    }

    func attemptSwap(from: Coord, to: Coord) {
        guard board.inBounds(to) else { return }
        if let reason = GameEngine.swapRejection(state, from: from, to: to) {
            // Invalid swap: вернуть фишки, не тратить move/charge/PRNG.
            invalidPair = (from, to)
            env.audio.play(.swapInvalid)
            env.haptics.invalid()
            if reason == "Keys can't be moved by hand" || reason == "Pinned pieces can't move" { toast = reason + "." }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.invalidPair = nil }
            return
        }
        perform(.swap(from: from, to: to))
    }

    // MARK: Turn preview (бесплатный)

    func openTurnPreview() {
        guard !isInputLocked else { return }
        env.audio.userInteracted()
        guard state.isTurnAvailable else {
            toast = state.movesLeft <= 0 ? "No moves left." : "Match gems to charge the stage."
            env.audio.play(.uiError)
            return
        }
        selected = nil
        phase = .idle
        preview = GameEngine.previewTurn(state)
        env.audio.play(.uiTap)
    }

    func cancelPreview() {
        preview = nil
        env.audio.play(.uiBack)
    }

    func confirmTurn() {
        guard let p = preview else { return }
        // Повторная проверка revision, charge и moves; двойной tap игнорируется.
        preview = nil
        guard state.isTurnAvailable, p.nextQ == (state.q + 1) % 4 else { return }
        perform(.rotate)
    }

    // MARK: Execute

    private func perform(_ kind: GameActionKind) {
        guard phase == .idle || phase == .selected else { return }
        let action = GameAction(id: UUID().uuidString, kind: kind, expectedRevision: state.revision)
        let result: ActionResult
        do {
            result = try GameEngine.apply(action, to: state)
        } catch EngineError.waveLimitExceeded {
            toast = "That move couldn't settle, so nothing was spent."
            return
        } catch EngineError.stageDataError {
            env.recovery = .levelInvalid(levelID: level.id, diagnosticID: AppEnvironment.diagnostic("STG"))
            return
        } catch {
            return
        }
        hintSwap = nil
        hintTurn = false
        turnSuggested = false
        if isDemo {
            state = result.state
            play(result, kind: kind)
            return
        }
        phase = .committing
        let apply: (Profile) -> Void = { [weak self] _ in
            guard let self else { return }
            self.state = result.state
            self.play(result, kind: kind)
        }
        let ok: Bool
        if result.state.status == .playing {
            ok = env.store.commit("save-run", { p in
                p.activeRun?.state = result.state
                p.activeRun?.hintsUsed = self.hintsUsed
            }, onSuccess: apply)
        } else {
            ok = commitOutcome(result.state, onSuccess: apply)
        }
        if !ok {
            // Save Failed: Recovery (Retry той же транзакции / Back к durable snapshot).
            phase = .idle
        }
    }

    private func commitOutcome(_ s: GameState, onSuccess: @escaping (Profile) -> Void) -> Bool {
        // Retry из Recovery повторит ту же транзакцию; после неё продолжится анимация.
        env.store.commitOutcome(level: level, state: s, onSuccess: onSuccess)
    }

    // MARK: Renderer

    private var motionReduced: Bool { env.reduceMotion }

    private func sleep(_ ms: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
    }

    private func play(_ result: ActionResult, kind: GameActionKind) {
        animationTask?.cancel()
        phase = kind == .rotate ? .rotating : .resolving
        idleSeconds = 0
        freeHintReady = false
        animationTask = Task { [weak self] in
            guard let self else { return }
            var waveIndex = 0
            for step in result.steps {
                if Task.isCancelled { break }
                await self.animate(step, waveIndex: &waveIndex)
            }
            self.finishAnimation(result)
        }
    }

    private func applyHUD(_ step: ResolutionStep) {
        hudMoves = step.movesLeft
        if step.charge > hudCharge { env.audio.play(.chargeTick) }
        hudCharge = step.charge
        hudCollected = step.collected
        hudExtracted = step.extractedKeyIDs
        hudQ = step.q
    }

    private func animate(_ step: ResolutionStep, waveIndex: inout Int) async {
        switch step.event {
        case .swapped:
            env.audio.play(.swapValid)
            env.haptics.swap()
            withAnimation(.easeInOut(duration: 0.16)) { board = step.board; applyHUD(step) }
            await sleep(170)

        case .rotated(_, let toQ):
            await animateRotation(to: toQ, step: step)

        case .keysExtracted(let list):
            for k in list { exitingKeys[k.occupantID] = k.direction }
            await sleep(16)
            env.audio.play(.keyExtract)
            withAnimation(.easeIn(duration: motionReduced ? 0.15 : 0.35)) { board = step.board; applyHUD(step) }
            for k in list { effects.append(BoardEffect(kind: .sparks(k.at))) }
            await sleep(motionReduced ? 180 : 380)
            effects.removeAll { if case .sparks = $0.kind { return true }; return false }

        case .wave(let w):
            waveIndex += 1
            await animateWave(w, step: step, index: waveIndex)

        case .gravity(let moves):
            let maxDist = moves.map { abs($0.to.x - $0.from.x) + abs($0.to.y - $0.from.y) }.max() ?? 1
            let dur = min(0.32, 0.18 + 0.03 * Double(maxDist))
            withAnimation(motionReduced ? .easeOut(duration: 0.12) : .easeIn(duration: dur)) { board = step.board; applyHUD(step) }
            await sleep((motionReduced ? 0.12 : dur) * 1000 + 10)
            env.audio.play(.gemLand)

        case .refill(let spawns):
            var drops: [Int: Int] = [:]
            for s in spawns { drops[s.occupant.id] = s.dropDistance }
            spawnDrops = drops
            await sleep(16)
            let dur = motionReduced ? 0.12 : 0.24
            withAnimation(.easeOut(duration: dur)) { board = step.board; applyHUD(step) }
            await sleep(dur * 1000 + 10)

        case .shuffled:
            toast = "No swaps left — the stage was reshuffled."
            withAnimation(.easeInOut(duration: motionReduced ? 0.15 : 0.45)) { board = step.board; applyHUD(step) }
            await sleep(motionReduced ? 200 : 500)

        case .turnSuggested:
            turnSuggested = true
            hintTurn = true
            toast = "No swaps left. Turn the stage to continue."
        }
    }

    private func animateRotation(to q: Int, step: ResolutionStep) async {
        env.audio.duck(for: 1.2)
        env.haptics.turn()
        if motionReduced {
            // Reduce Motion: crossfade до 200 ms между ориентациями, S21 пропускается, вместо S20/S22 — короткий S22.
            env.audio.play(.turnLock)
            withAnimation(.easeInOut(duration: 0.2)) {
                displayAngle = GameSession.continuousAngle(state)
                crossfadeToken += 1
                applyHUD(step)
            }
            await sleep(210)
            return
        }
        // 0 ms S20; 80…700 ms S21; 700 ms S22; 760 ms S23.
        env.audio.play(.turnStart)
        withAnimation(.easeInOut(duration: 0.3)) { curtainsClosed = true; beamVisible = true }
        await sleep(80)
        env.audio.play(.stageRotate)
        withAnimation(.easeInOut(duration: 0.62)) {
            displayAngle += 90
            applyHUD(step)
        }
        await sleep(620)
        env.audio.play(.turnLock)
        withAnimation(.easeInOut(duration: 0.3)) { curtainsClosed = false }
        await sleep(60)
        env.audio.play(.curtainSweep)
        withAnimation(.easeOut(duration: 0.4)) { beamVisible = false }
        await sleep(90)
    }

    private func animateWave(_ w: WaveEvent, step: ResolutionStep, index: Int) async {
        if !w.sweepCells.isEmpty {
            withAnimation(.easeOut(duration: 0.12)) { sweepHighlight = w.sweepCells }
            await sleep(motionReduced ? 80 : 180)
        }
        // Эффекты specials.
        var fx: [BoardEffect] = []
        for e in w.effects {
            switch e {
            case .line(let o, let a): fx.append(BoardEffect(kind: .line(o, a)))
            case .burst(let c, let r): fx.append(BoardEffect(kind: .burst(c, r)))
            case .band(let c): fx.append(BoardEffect(kind: .band(c)))
            case .colorClear(let o, _, let t): fx.append(BoardEffect(kind: .colorClear(o, t)))
            case .allCells: fx.append(BoardEffect(kind: .allCells))
            }
        }
        if !fx.isEmpty {
            effects.append(contentsOf: fx)
            if w.effects.contains(where: { if case .colorClear = $0 { return true }; if case .allCells = $0 { return true }; return false }) {
                env.audio.play(.prismClear)
            } else if w.effects.contains(where: { if case .burst = $0 { return true }; if case .band = $0 { return true }; return false }) {
                env.audio.play(.stageBurst)
            } else {
                env.audio.play(.lineSpark)
            }
            await sleep(motionReduced ? 90 : 190)
        }
        // Звуки wave агрегируются: один match/cascade, один звук каждого препятствия.
        if !w.groups.isEmpty {
            switch index {
            case 1: env.audio.play(.matchThree)
            case 2: env.audio.play(.cascadeTwo)
            case 3: env.audio.play(.cascadeThree)
            default: env.audio.play(.cascadeFour)
            }
        }
        if !w.created.isEmpty { env.audio.play(.specialCreate) }
        let layers = Set(w.damaged.map { $0.layer })
        if w.damaged.contains(where: { $0.layer == .crate && $0.remainingHP == 0 }) { env.audio.play(.crateBreak) }
        else if layers.contains(.crate) { env.audio.play(.crateHit) }
        if layers.contains(.ice) { env.audio.play(.iceCrack) }
        if layers.contains(.chain) { env.audio.play(.chainBreak) }
        if w.damaged.contains(where: { $0.layer == .plate && $0.remainingHP == 0 }) { env.audio.play(.plateClear) }
        if !w.switchesActivated.isEmpty { env.audio.play(.switchPress) }
        if !w.shuttersOpened.isEmpty { env.audio.play(.shutterOpen) }

        withAnimation(.easeOut(duration: motionReduced ? 0.1 : 0.14)) {
            board = step.board
            applyHUD(step)
            sweepHighlight = []
        }
        await sleep(motionReduced ? 110 : 160)
        effects.removeAll()
    }

    private func finishAnimation(_ result: ActionResult) {
        if isDemo {
            board = state.board
            hudMoves = state.movesLeft
            hudCharge = state.charge
            hudCollected = state.collected
            hudExtracted = state.extractedKeyIDs
            hudQ = state.q
            displayAngle = GameSession.continuousAngle(state)
            spawnDrops = [:]
            exitingKeys = [:]
            effects = []
            sweepHighlight = []
            phase = .idle
            onDemoFinished?(state)
            return
        }
        board = state.board
        hudMoves = state.movesLeft
        hudCharge = state.charge
        hudCollected = state.collected
        hudExtracted = state.extractedKeyIDs
        hudQ = state.q
        displayAngle = GameSession.continuousAngle(state)
        spawnDrops = [:]
        exitingKeys = [:]
        effects = []
        sweepHighlight = []
        idleSeconds = 0
        freeHintReady = false
        switch state.status {
        case .won:
            phase = .win
            env.haptics.success()
            env.audio.duck(for: 2.5)
            env.audio.play(.levelWin)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showResult() }
        case .failed:
            phase = .noMoves
            env.audio.duck(for: 2)
            env.audio.play(.levelFail)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showResult() }
        case .playing:
            phase = .idle
            if result.turnSuggested { turnSuggested = true; hintTurn = true }
            if state.charge >= 12 && !turnReadyAnnounced {
                turnReadyAnnounced = true
                env.audio.play(.turnReady)
                triggerTutorial("chargeFull")
                UIAccessibility.post(notification: .announcement, argument: "Stage Charge full. Turn Stage is ready.")
            }
            if state.charge < 12 { turnReadyAnnounced = false }
            if case .rotate = lastKind(result) { triggerTutorial("afterTurn") }
            announceState()
            if pendingPause { pendingPause = false; pause() }
        }
    }

    private func lastKind(_ r: ActionResult) -> GameActionKind? {
        for s in r.steps { if case .rotated = s.event { return .rotate } }
        return nil
    }

    private func announceState() {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let goals = state.objectives.map { $0.spokenGoal(state.remaining(for: $0)) }.joined(separator: ", ")
        UIAccessibility.post(notification: .announcement,
                             argument: "\(state.movesLeft) moves. \(goals). Charge \(state.charge) of 12. Gravity \(state.gravity.label).")
    }

    private func triggerTutorial(_ trigger: String) {
        guard !shownTutorialTriggers.contains(trigger), !env.store.profile.isCompleted(level.id),
              let step = level.tutorialSteps.first(where: { $0.trigger == trigger }) else { return }
        shownTutorialTriggers.insert(trigger)
        banner = step
    }

    private func showResult() {
        #if DEBUG
        if env.isFixture {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("outcome-\(level.id).txt")
            try? "\(state.status.rawValue) movesLeft=\(state.movesLeft) turns=\(state.turnsUsed) balance=\(env.store.profile.hintBalance)".write(to: url, atomically: true, encoding: .utf8)
        }
        #endif
        // Результат заменяет экран игры: Back с экрана результата и следующего брифинга ведёт на карту.
        if state.status == .won { env.router.replaceTop(.curtainCall(runID: runID)) } else { env.router.replaceTop(.oneMoreAct(runID: runID)) }
    }

    // MARK: Hint

    var hintButtonTitle: String {
        freeHintReady || freeHintRevision == state.revision ? "Free Hint" : "Hint • \(env.store.profile.hintBalance)"
    }

    /// Подсказка: бесплатная после 15 с бездействия (и повторно на той же revision), иначе 1 Hint Ticket —
    /// списывается только после показа допустимого действия.
    func requestHint() {
        guard !isInputLocked else { return }
        env.audio.userInteracted()
        let free = freeHintReady || freeHintRevision == state.revision
        guard free || env.store.profile.hintBalance > 0 else {
            toast = "No Hint Tickets left. A free hint appears after 15 seconds."
            env.audio.play(.uiError)
            return
        }
        guard let h = HintPolicy.suggest(for: state) else {
            toast = "No legal action to suggest."
            return
        }
        switch h {
        case .swap(let a, let b):
            hintSwap = (a, b)
            hintTurn = false
        case .turn:
            hintTurn = true
            hintSwap = nil
        }
        env.audio.play(.hintReveal)
        if free {
            freeHintRevision = state.revision
        } else {
            if env.store.spendHint() {
                hintsUsed += 1
                freeHintRevision = state.revision
            }
        }
        freeHintReady = false
        idleSeconds = 0
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickIdle() }
        }
    }

    /// Таймер не идёт в Pause, Help, preview, animation или background.
    private func tickIdle() {
        guard phase == .idle || phase == .selected, !paused, preview == nil, UIApplication.shared.applicationState == .active,
              env.router.current == .gameplay(runID: runID), env.router.modal == nil, state.status == .playing else { return }
        idleSeconds += 1
        if idleSeconds >= 15 && !freeHintReady { freeHintReady = true }
    }

    // MARK: Pause / restart / background

    /// Pause после settled commit; во время resolve — pending.
    func pause() {
        if phase == .resolving || phase == .rotating || phase == .committing {
            pendingPause = true
            return
        }
        preview = nil
        selected = nil
        paused = true
        env.audio.play(.uiTap)
    }

    func resume() {
        paused = false
        idleSeconds = 0
        env.audio.play(.uiTap)
    }

    func enterBackground() {
        // Модель уже сохранена до анимации; восстановить settled state без очереди старых событий.
        animationTask?.cancel()
        if phase == .resolving || phase == .rotating {
            finishAnimationSilently()
        }
        preview = nil
        if state.status == .playing { paused = true }
    }

    private func finishAnimationSilently() {
        board = state.board
        hudMoves = state.movesLeft
        hudCharge = state.charge
        hudCollected = state.collected
        hudExtracted = state.extractedKeyIDs
        hudQ = state.q
        displayAngle = GameSession.continuousAngle(state)
        effects = []
        sweepHighlight = []
        curtainsClosed = false
        beamVisible = false
        spawnDrops = [:]
        exitingKeys = [:]
        switch state.status {
        case .playing: phase = .idle
        case .won: phase = .win; showResult()
        case .failed: phase = .noMoves; showResult()
        }
    }

    /// Restart: новый attemptID с тем же seed, полем и charge; использованные Hint Tickets не возвращаются.
    func restart() {
        restartConfirm = false
        paused = false
        env.startLevel(level.id, replaceConfirmed: true)
    }

    func objectiveRemaining(_ o: ObjectiveDef) -> Int {
        switch o {
        case .collect(let c, let t): return max(0, t - hudCollected[c.rawValue])
        case .plates: return board.remainingPlateCells
        case .keys: return state.initialKeyIDs.filter { !hudExtracted.contains($0) }.count
        }
    }
}
