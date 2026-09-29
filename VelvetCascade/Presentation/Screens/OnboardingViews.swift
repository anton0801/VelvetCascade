// OnboardingViews.swift — 01 Welcome, 02 Match Tutorial, 03 Rotation Tutorial.

import SwiftUI
import VelvetDomain

struct PageDots: View {
    let index: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { i in
                Capsule().fill(i == index ? Palette.spotlightGold : Palette.mutedRose.opacity(0.4))
                    .frame(width: i == index ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index) of 3")
    }
}

// MARK: 01 Welcome

struct WelcomeView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        ZStack {
            BackgroundArt(name: "vc_onboarding_welcome")
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { skip() }.buttonStyle(TextLinkStyle(color: Palette.warmIvory))
                        .accessibilityHint("Go straight to the stage. Tips will appear in the first levels.")
                }
                .padding(.horizontal, 16)
                Text("Velvet Cascade")
                    .vcFont(.display)
                    .foregroundColor(Palette.warmIvory)
                    .shadow(color: .black.opacity(0.9), radius: 8, y: 2)
                    .padding(.horizontal, 18).padding(.vertical, 6)
                    .background(TitleBackdrop())
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                VStack(spacing: 16) {
                    Text("Every turn changes the stage.")
                        .vcFont(.title2)
                        .foregroundColor(Palette.warmIvory)
                        .multilineTextAlignment(.center)
                    Text("Match gems, charge the stage and let Vell turn it a quarter — the floor changes and the cascade begins.")
                        .vcFont(.body)
                        .foregroundColor(Palette.mutedRose)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    PageDots(index: 1)
                    Button("Begin") {
                        env.tap()
                        env.router.push(.matchTutorial)
                    }
                    .goldButton()
                }
                .padding(20)
                .background(
                    LinearGradient(colors: [Palette.deepVelvet.opacity(0), Palette.deepVelvet.opacity(0.85), Palette.deepVelvet],
                                   startPoint: .top, endPoint: .bottom)
                        .padding(.top, -60)
                        .ignoresSafeArea()
                )
                .padding(.bottom, 16)
            }
            .frame(maxWidth: Metrics.maxContentWidth)
        }
    }

    private func skip() {
        env.tap()
        env.store.completeOnboarding()
        env.router.reset([.home])
    }
}

// MARK: 02 Match Tutorial

struct MatchTutorialView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var holder = DemoHolder()
    @State private var step: Step = .before
    @State private var showBigger = false

    enum Step { case before, matched, bigger, biggerDone }

    var body: some View {
        ZStack {
            BackgroundArt(name: "vc_onboarding_match", dim: 0.2)
            VStack(spacing: 14) {
                HStack {
                    IconButton(glyph: .back, label: "Back") { env.back() }
                    Spacer()
                    Button("Skip") { skip() }.buttonStyle(TextLinkStyle(color: Palette.warmIvory))
                }
                .padding(.horizontal, 16)
                VStack(spacing: 6) {
                    Text("Make a match").vcFont(.title).foregroundColor(Palette.warmIvory).accessibilityAddTraits(.isHeader)
                    Text("Match four or more to charge the stage faster.")
                        .vcFont(.body).foregroundColor(Palette.warmIvory.opacity(0.9)).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(TitleBackdrop())
                .padding(.horizontal, 24)
                Spacer(minLength: 8)
                if let s = holder.session {
                    VStack(spacing: 12) {
                        if env.reduceMotion {
                            staticBeforeAfter
                        } else {
                            BoardView(session: s, viewport: min(240, UIScreen.main.bounds.width - 80),
                                      highContrast: env.store.settings.highContrastSymbols, gravityLabels: false)
                        }
                        StageChargeGauge(charge: s.hudCharge)
                            .frame(maxWidth: 240)
                        Text(caption).vcFont(.secondary).foregroundColor(Palette.warmIvory).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                HStack(spacing: 16) {
                    if step == .before || step == .bigger {
                        Button(step == .before ? "Show me" : "Show me again") { runDemo() }
                            .buttonStyle(TextLinkStyle())
                    }
                    if step == .matched || step == .biggerDone {
                        Button("Show a bigger match") { startBigger() }.buttonStyle(TextLinkStyle())
                    }
                }
                Spacer(minLength: 8)
                PageDots(index: 2)
                Button("Next") {
                    env.tap()
                    env.router.push(.rotationTutorial)
                }
                .goldButton()
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: Metrics.maxContentWidth)
        }
        .onAppear { setup() }
    }

    private var caption: String {
        switch step {
        case .before: return "Swipe the centre Heart up — or tap it, then tap the gem above."
        case .matched: return "Three Hearts! A match of three adds 1 charge."
        case .bigger: return "Swipe the Heart in the second row up to line up four."
        case .biggerDone: return "Four in a row adds 3 charge and leaves a LineSpark."
        }
    }

    private var staticBeforeAfter: some View {
        // Reduce Motion: статичные before/after вместо анимации.
        HStack(spacing: 12) {
            VStack { MiniGrid(rows: ["HDH", "BHC", "SDB"]); Text("Before").vcFont(.caption).foregroundColor(Palette.mutedRose) }
            Text("→").vcFont(.title2).foregroundColor(Palette.spotlightGold)
            VStack { MiniGrid(rows: ["HHH", "BDC", "SDB"], highlightRow: 0); Text("After").vcFont(.caption).foregroundColor(Palette.mutedRose) }
        }
    }

    private func setup() {
        guard holder.session == nil else { return }
        let s = GameSession.demo(env: env, state: DemoBoards.match3, id: -2)
        s.onDemoFinished = { _ in
            if step == .before { step = .matched } else if step == .bigger { step = .biggerDone }
        }
        holder.session = s
    }

    private func runDemo() {
        guard let s = holder.session else { return }
        if step == .bigger {
            s.demoPerform(.swap(from: DemoBoards.match4Swap.0, to: DemoBoards.match4Swap.1))
        } else {
            s.resetDemo(DemoBoards.match3)
            s.demoPerform(.swap(from: DemoBoards.match3Swap.0, to: DemoBoards.match3Swap.1))
        }
    }

    private func startBigger() {
        guard let s = holder.session else { return }
        s.resetDemo(DemoBoards.match4)
        step = .bigger
    }

    private func skip() {
        env.tap()
        env.store.completeOnboarding()
        env.router.reset([.home])
    }
}

/// Мягкая тёмная подложка под заголовок поверх художественного фона (текст не светится).
struct TitleBackdrop: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Palette.deepVelvet.opacity(0.72))
            .blur(radius: 6)
            .accessibilityHidden(true)
    }
}

final class DemoHolder: ObservableObject {
    @Published var session: GameSession?
}

/// Статичная мини-сетка токенов (Reduce Motion, Encore Rules).
struct MiniGrid: View {
    let rows: [String]
    var highlightRow: Int?
    var size: CGFloat = 32

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { y, row in
                HStack(spacing: 3) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, ch in
                        ZStack {
                            RoundedRectangle(cornerRadius: 5).fill(Palette.cellFill)
                            if let c = GemColor(letter: String(ch)) {
                                ArtImage(name: GemArt.name(c), maxPoints: size).frame(width: size * 0.8, height: size * 0.8)
                            }
                        }
                        .frame(width: size, height: size)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.spotlightGold, lineWidth: highlightRow == y ? 2 : 0))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: 03 Rotation Tutorial

struct RotationTutorialView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var holder = DemoHolder()
    @State private var done = false

    var body: some View {
        ZStack {
            BackgroundArt(name: "vc_onboarding_rotate", dim: 0.15)
            VStack(spacing: 12) {
                HStack {
                    IconButton(glyph: .back, label: "Back") { env.back() }
                    Spacer()
                }
                .padding(.horizontal, 16)
                VStack(spacing: 6) {
                    Text("Turn the stage").vcFont(.title).foregroundColor(Palette.warmIvory).accessibilityAddTraits(.isHeader)
                    Text("Clear the edge. Start a cascade.").vcFont(.body).foregroundColor(Palette.warmIvory.opacity(0.9))
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(TitleBackdrop())
                Spacer(minLength: 6)
                if let s = holder.session {
                    ZStack {
                        BoardView(session: s, viewport: min(240, UIScreen.main.bounds.width - 80),
                                  highContrast: env.store.settings.highContrastSymbols, gravityLabels: true)
                        if !env.reduceMotion { CurtainLayer(session: s, viewport: min(240, UIScreen.main.bounds.width - 80)) }
                    }
                    HStack(spacing: 12) {
                        ArtImage(name: "vc_turn_crown", maxPoints: 48).frame(width: 48, height: 48)
                        StageChargeGauge(charge: s.hudCharge)
                        GravityCompass(q: s.hudQ, previewQ: done ? nil : (s.hudQ + 1) % 4, showLabel: true)
                    }
                    .padding(.horizontal, 20)
                    Text(done ? "The stage turned. Pieces still fall toward the floor — the key dropped out through its exit."
                              : "The glowing edge will reach the floor. The exit on the right becomes active.")
                        .vcFont(.secondary).foregroundColor(Palette.warmIvory).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                }
                Spacer(minLength: 6)
                PageDots(index: 3)
                Text("A turn uses one move and a full charge.").vcFont(.caption).foregroundColor(Palette.mutedRose)
                Button(done ? "Try Again" : "Try a Turn") { tryTurn() }.velvetButton().padding(.horizontal, 20)
                Button("Let's Play") {
                    env.tap()
                    env.store.completeOnboarding()
                    env.router.reset([.home])
                }
                .goldButton()
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: Metrics.maxContentWidth)
        }
        .onAppear { setup() }
    }

    private func setup() {
        guard holder.session == nil else { return }
        let s = GameSession.demo(env: env, state: DemoBoards.rotate, id: -3)
        s.preview = GameEngine.previewTurn(DemoBoards.rotate)
        s.onDemoFinished = { _ in done = true }
        holder.session = s
    }

    private func tryTurn() {
        guard let s = holder.session else { return }
        env.audio.userInteracted()
        if done {
            s.resetDemo(DemoBoards.rotate)
            s.preview = GameEngine.previewTurn(DemoBoards.rotate)
            done = false
            return
        }
        s.preview = nil
        s.demoPerform(.rotate)
    }
}
