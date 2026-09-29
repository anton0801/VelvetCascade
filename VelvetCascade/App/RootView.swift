// RootView.swift — отображение текущего маршрута, модальных состояний и Recovery.

import SwiftUI
import VelvetDomain

struct RootView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var router: Router
    @EnvironmentObject var store: ProgressStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.deepVelvet.ignoresSafeArea()
                screen(router.current)
                    .id(router.current)
                    .transition(env.reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: router.transitionForward ? .trailing : .leading)),
                        removal: .opacity))
                    .frame(width: env.forcedWidth ?? geo.size.width)
                    .frame(maxWidth: .infinity)

                if let m = router.modal { modal(m) }
                if store.pending != nil {
                    RecoveryView(kind: .saveFailed(diagnosticID: store.pendingDiagnosticID))
                }
                if let r = env.recovery ?? store.loadIssue {
                    RecoveryView(kind: r)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background: env.didEnterBackground()
            case .active: env.didBecomeActive()
            default: break
            }
        }
        .onChange(of: router.current) { _ in env.musicForCurrentRoute() }
        .simultaneousGesture(TapGesture().onEnded { env.audio.userInteracted() })
    }

    @ViewBuilder
    private func screen(_ r: Route) -> some View {
        switch r {
        case .welcome: WelcomeView()
        case .matchTutorial: MatchTutorialView()
        case .rotationTutorial: RotationTutorialView()
        case .home: HomeView()
        case .worlds: WorldsView()
        case .worldMap(let w): WorldMapView(world: w)
        case .levelBrief(let id): LevelBriefView(levelID: id)
        case .gameplay:
            if let s = env.session { GameplayView(session: s) } else { HomeView() }
        case .curtainCall: CurtainCallView()
        case .oneMoreAct: OneMoreActView()
        case .newTheatre(let w, let final): NewTheatreView(world: w, isFinal: final)
        case .daily: DailyEncoreView()
        case .dailyReward(let id): EncoreRewardView(receiptID: id)
        case .handbook(let topic): StageHandbookView(initialTopic: topic)
        case .settings: SettingsView()
        case .credits: CreditsView()
        case .importReview: ImportReviewView()
        #if DEBUG
        case .gallery(let page): ComponentGallery(page: page)
        #endif
        }
    }

    @ViewBuilder
    private func modal(_ m: ModalRoute) -> some View {
        switch m {
        case .dailyRules: EncoreRulesView()
        case .resetConfirm: ResetConfirmationView()
        case .replaceRun(let level): ReplaceRunView(currentLevel: level)
        case .recovery: RecoveryView(kind: .saveFailed(diagnosticID: store.pendingDiagnosticID))
        }
    }
}

/// «Replace your current attempt?» — замена активной попытки только после подтверждения.
struct ReplaceRunView: View {
    @EnvironmentObject var env: AppEnvironment
    let currentLevel: Int

    var body: some View {
        ModalScrim(dismissOnTapOutside: nil) {
            TheatrePanel {
                VStack(spacing: 14) {
                    Text("Replace your current attempt?").vcFont(.title2).foregroundColor(Palette.warmIvory)
                        .multilineTextAlignment(.center)
                    Text("Your saved attempt on Level \(env.store.profile.activeRun?.levelID ?? currentLevel) will be replaced. Your best results will stay.")
                        .vcFont(.body).foregroundColor(Palette.mutedRose).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Keep Current") {
                        env.router.modal = nil
                        env.pendingStartLevel = nil
                    }
                    .goldButton()
                    Button("Replace") {
                        env.router.modal = nil
                        if let id = env.pendingStartLevel {
                            env.pendingStartLevel = nil
                            env.startLevel(id, replaceConfirmed: true)
                        }
                    }
                    .velvetButton(destructive: true)
                }
            }
        }
    }
}
