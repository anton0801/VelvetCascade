// DailyViews.swift — 14 Daily Encore, 15 Encore Reward, 21 Encore Rules.
//
// Free Spin: блокировка повторного tap → проверка дня → системный криптографический random → одна транзакция
// (receipt+balance+highestClaimedDay) → только после commit анимация уже определённого результата.
// Прерывание/Skip не меняет итог; Continue лишь отмечает acknowledged.

import SwiftUI
import VelvetDomain

/// VC23 + три clipped ReelWindow по измеренным reelRects; symbols масштабируются вместе с корпусом (aspectFit).
struct DailyMachine: View {
    let size: CGFloat
    let rects: [NormRect]
    let symbols: [GemColor]
    /// nil — статично; иначе время старта вращения.
    var spinStart: Date?
    var startSymbols: [GemColor] = [.heart, .diamond, .star]
    var reduceMotion = false

    static let stopTimes: [Double] = [1.35, 1.75, 2.15]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArtImage(name: "vc_daily_machine", maxPoints: size).frame(width: size, height: size)
            ForEach(0..<3, id: \.self) { i in
                let r = rects[i]
                ReelWindow(symbol: symbols[i], start: startSymbols[i], stopAfter: DailyMachine.stopTimes[i],
                           loops: 5 + i * 2, spinStart: spinStart, reduceMotion: reduceMotion)
                    .frame(width: r.w * size, height: r.h * size)
                    .offset(x: r.x * size, y: r.y * size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily Encore machine")
        .accessibilityValue(spinStart == nil ? symbols.map { $0.name }.joined(separator: ", ") : "Spinning")
    }
}

/// UI17: кремовая поверхность, мягкие тени сверху/снизу, центр ярче; итоговый symbol 72–78% ширины окна.
struct ReelWindow: View {
    let symbol: GemColor
    let start: GemColor
    let stopAfter: Double
    let loops: Int
    let spinStart: Date?
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let spacing = w * 0.9
            ZStack {
                LinearGradient(colors: [Color(hex: 0xEADBC0), Palette.warmIvory, Color(hex: 0xEADBC0)], startPoint: .top, endPoint: .bottom)
                if let t0 = spinStart, !reduceMotion {
                    TimelineView(.animation) { tl in
                        let t = tl.date.timeIntervalSince(t0)
                        strip(t: t, w: w, h: h, spacing: spacing)
                    }
                } else if let t0 = spinStart, reduceMotion {
                    // Reduce Motion: fade 150 ms к результату, без прокрутки.
                    TimelineView(.animation) { tl in
                        let t = tl.date.timeIntervalSince(t0)
                        ZStack {
                            token(start, w: w).opacity(t < 0.15 ? 1 - t / 0.15 : 0)
                            token(symbol, w: w).opacity(t < 0.15 ? t / 0.15 : 1)
                        }
                        .position(x: w / 2, y: h / 2)
                    }
                } else {
                    token(symbol, w: w).position(x: w / 2, y: h / 2)
                }
                LinearGradient(colors: [Color.black.opacity(0.28), .clear, .clear, Color.black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func token(_ c: GemColor, w: CGFloat) -> some View {
        ArtImage(name: GemArt.name(c), maxPoints: w * 0.76).frame(width: w * 0.75, height: w * 0.75)
    }

    /// Позиция ленты: ease-out от стартового символа к итоговому за stopAfter секунд.
    private func strip(t: Double, w: CGFloat, h: CGFloat, spacing: CGFloat) -> some View {
        let startIdx = Double(start.rawValue)
        let delta = Double(((symbol.rawValue - start.rawValue) % 5 + 5) % 5)
        let total = Double(loops * 5) + delta
        let x = min(1, max(0, t / stopAfter))
        let eased = 1 - pow(1 - x, 3)
        let pos = startIdx + total * eased
        let speed = total * 3 * pow(1 - x, 2) / stopAfter
        let base = Int(floor(pos))
        let frac = pos - Double(base)
        let bounce = t > stopAfter ? sin(min(1, (t - stopAfter) / 0.18) * .pi) * 0.06 : 0
        return ZStack {
            ForEach(-2...2, id: \.self) { k in
                let idx = ((base + k) % 5 + 5) % 5
                token(GemColor(rawValue: idx)!, w: w)
                    .position(x: w / 2, y: h / 2 + (CGFloat(k) - CGFloat(frac) - CGFloat(bounce)) * spacing)
            }
        }
        .blur(radius: min(4, CGFloat(speed) * 0.25))
    }
}

struct DailyEncoreView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore
    @State private var spinStart: Date?
    @State private var receipt: DailyReceipt?
    @State private var spring = false
    @State private var navigated = false
    @State private var saveError = false

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width - 40, 320)
            ZStack {
                BackgroundArt(name: "vc_world_01", dim: 0.35)
                VStack(spacing: 10) {
                    ScreenHeader(title: "Daily Encore", onBack: { env.back() }) {
                        Button("Rules") { env.tap(); env.router.modal = .dailyRules }.buttonStyle(TextLinkStyle())
                            .accessibilityLabel("Reward Rules")
                    }
                    HStack {
                        Text(isCollected ? "Collected today" : "Your free daily spin")
                            .vcFont(.secondary).foregroundColor(isCollected ? Palette.success : Palette.mutedRose)
                        Spacer()
                        TicketBalance(count: store.profile.hintBalance)
                    }
                    .padding(.horizontal, Metrics.side)
                    Spacer(minLength: 4)
                    DailyMachine(size: size, rects: env.media.reelRects, symbols: shownSymbols, spinStart: spinStart,
                                 reduceMotion: env.reduceMotion)
                        .scaleEffect(spring ? 1.02 : 1)
                    paytable
                    Spacer(minLength: 4)
                    VStack(spacing: 8) {
                        if spinStart != nil && receipt != nil {
                            Button("Skip Animation") { finish() }.buttonStyle(TextLinkStyle())
                        }
                        Button {
                            spin()
                        } label: {
                            Text(buttonTitle)
                        }
                        .goldButton(busy: store.isCommitting)
                        .disabled((!store.dailyEligible && !hasPendingReceipt) || spinStart != nil || store.isCommitting)
                        Text(resetLine).vcFont(.caption).foregroundColor(Palette.mutedRose).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Metrics.side)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: Metrics.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            env.audio.play(.dailyOpen)
            // Crash после commit: показать ту же тройку, не начислять заново.
            if let pending = store.unacknowledgedReceipt, spinStart == nil {
                receipt = pending
            }
        }
        .onDisappear { env.audio.stopReelLoop() }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .vcDebugDailySpin)) { _ in spin() }
        #endif
    }

    private var isCollected: Bool { !store.dailyEligible }
    private var hasPendingReceipt: Bool { receipt.map { !$0.acknowledged } ?? false }

    private var shownSymbols: [GemColor] {
        if let r = receipt { return r.symbols }
        if let t = store.profile.todayReceipt, isCollected { return t.symbols }
        return [.heart, .diamond, .star]
    }

    private var buttonTitle: String {
        if spinStart != nil { return "Spinning…" }
        if receipt != nil && !(receipt?.acknowledged ?? true) { return "Continue" }
        return store.dailyEligible ? "Free Spin" : "Collected today"
    }

    private var resetLine: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        if store.dailyEligible { return "Resets at 00:00 UTC" }
        return "Resets at 00:00 UTC · next spin \(f.string(from: store.nextDailyDate))"
    }

    private var paytable: some View {
        HStack(spacing: 14) {
            ForEach(DailyOutcomeKind.allCases, id: \.self) { k in
                HStack(spacing: 4) {
                    Text(k.title).vcFont(.caption).foregroundColor(Palette.mutedRose)
                    Text("\(k.nominalReward)").vcFont(.headline).foregroundColor(Palette.spotlightGold)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Palette.panel.opacity(0.9)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mixed 1 ticket, Pair 2 tickets, Triple 5 tickets")
    }

    private func spin() {
        env.audio.userInteracted()
        if let r = receipt, !r.acknowledged, spinStart == nil {
            env.router.push(.dailyReward(receiptID: r.id))
            return
        }
        guard spinStart == nil, store.dailyEligible, !store.isCommitting else { return }
        guard let r = store.claimDaily() else {
            // Save Failed → Recovery; награда не выдана до durable commit.
            if var p = store.pending {
                let original = p.onSuccess
                p = PendingTransaction(id: p.id, label: p.label, profile: p.profile) { prof in
                    original(prof)
                    if let rec = prof.recentReceipts.last { self.startAnimation(rec) }
                }
                store.pending = p
            }
            return
        }
        startAnimation(r)
    }

    private func startAnimation(_ r: DailyReceipt) {
        receipt = r
        navigated = false
        if env.reduceMotion {
            spinStart = Date()
            env.audio.play(.dailyReward, gainDB: -1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { finish() }
            return
        }
        withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) { spring = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.1)) { spring = false }
            spinStart = Date()
            env.audio.startReelLoop()
            for (i, t) in DailyMachine.stopTimes.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                    guard !navigated else { return }
                    env.audio.play(.reelStop, semitones: Double(i * 2))
                    env.haptics.reelStop()
                    if i == 2 { env.audio.stopReelLoop() }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.15 + 0.2) { finish() }
        }
    }

    private func finish() {
        guard !navigated, let r = receipt else { return }
        navigated = true
        env.audio.stopReelLoop()
        spinStart = nil
        env.router.push(.dailyReward(receiptID: r.id))
    }
}

struct EncoreRewardView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore
    let receiptID: String

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width - 40, 320)
            ZStack {
                BackgroundArt(name: "vc_world_01", dim: 0.35)
                if let r = store.receipt(id: receiptID) {
                    VStack(spacing: 12) {
                        ScreenHeader(title: "Daily Encore", onBack: { done(r) })
                        Spacer(minLength: 4)
                        ZStack {
                            RadialGradient(colors: [Palette.spotlightGold.opacity(0.35), .clear], center: .center, startRadius: 10, endRadius: size * 0.7)
                                .frame(width: size * 1.3, height: size * 1.3)
                                .accessibilityHidden(true)
                            DailyMachine(size: size, rects: env.media.reelRects, symbols: r.symbols)
                            if !env.reduceMotion { SparkEmitter(count: 12, area: CGSize(width: size, height: size), seed: Int(r.dayIndex % 1000)) }
                        }
                        TheatrePanel {
                            VStack(spacing: 8) {
                                ArtImage(name: "vc_hint_ticket", maxPoints: 56).frame(width: 56, height: 56)
                                Text(DailyRewardPolicy.classify(r.symbols).title).vcFont(.caption).foregroundColor(Palette.mutedRose)
                                if r.creditedAmount > 0 {
                                    Text("+\(r.creditedAmount) Hint Ticket\(r.creditedAmount == 1 ? "" : "s")")
                                        .vcFont(.title).foregroundColor(Palette.spotlightGold)
                                    Text("Added to your collection").vcFont(.body).foregroundColor(Palette.warmIvory)
                                } else {
                                    Text("Ticket limit reached").vcFont(.title2).foregroundColor(Palette.warmIvory)
                                    Text("Reward \(r.nominalReward) · balance unchanged").vcFont(.secondary).foregroundColor(Palette.mutedRose)
                                }
                                Text("Balance: \(store.profile.hintBalance)").vcFont(.secondary).foregroundColor(Palette.mutedRose).monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .padding(.horizontal, Metrics.side)
                        Spacer(minLength: 4)
                        Button("Continue") { done(r) }.goldButton().padding(.horizontal, Metrics.side).padding(.bottom, 12)
                    }
                    .frame(maxWidth: Metrics.maxContentWidth)
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        env.audio.duck(for: 1.5)
                        env.audio.play(.dailyReward)
                        env.haptics.success()
                    }
                } else {
                    // Нет receipt — вернуться к Daily, не генерировать новый результат.
                    Color.clear.onAppear { env.router.replaceTop(.daily) }
                }
            }
        }
    }

    /// Continue/Back отмечают receipt acknowledged; кнопка не начисляет награду.
    private func done(_ r: DailyReceipt) {
        env.tap()
        if !r.acknowledged { store.acknowledge(receiptID: r.id) }
        env.router.goHome()
    }
}

struct EncoreRulesView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ModalScrim(dismissOnTapOutside: { env.router.modal = nil }) {
            TheatrePanel {
                VStack(spacing: 12) {
                    Text("Encore Rules").vcFont(.title2).foregroundColor(Palette.warmIvory).accessibilityAddTraits(.isHeader)
                    row(.mixed, [.heart, .diamond, .star])
                    row(.pair, [.heart, .clover, .heart])
                    row(.triple, [.star, .star, .star])
                    HStack(alignment: .top, spacing: 10) {
                        ArtImage(name: "vc_hint_ticket", maxPoints: 32).frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("One free spin per UTC day.").vcFont(.body).foregroundColor(Palette.warmIvory)
                            Text("Hint Tickets are only used for optional hints.").vcFont(.secondary).foregroundColor(Palette.mutedRose)
                            Text("Pair means any two positions. Each reel picks one of five symbols with equal chance.")
                                .vcFont(.caption).foregroundColor(Palette.mutedRose)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Done") { env.tap(); env.router.modal = nil }.goldButton()
                }
            }
        }
    }

    private func row(_ k: DailyOutcomeKind, _ sample: [GemColor]) -> some View {
        AdaptiveStack(vertical: typeSize.isAccessibilitySize, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    ArtImage(name: GemArt.name(sample[i]), maxPoints: 28).frame(width: 28, height: 28)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(k.title).vcFont(.headline).foregroundColor(Palette.warmIvory).fixedSize()
                    Text("\(k.nominalReward) ticket\(k.nominalReward == 1 ? "" : "s")").vcFont(.secondary).foregroundColor(Palette.mutedRose)
                        .fixedSize()
                }
                Spacer()
                Text("\(k.probabilityPercent)%").vcFont(.hudSmall).foregroundColor(Palette.spotlightGold).fixedSize()
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 64)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.plumStage))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(k.title): \(k.nominalReward) tickets, \(k.probabilityPercent) percent")
    }
}
