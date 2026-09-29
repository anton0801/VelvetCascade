// HomeViews.swift — 04 Home, 05 Worlds, 06 World Map, 07 Level Brief.

import SwiftUI
import VelvetDomain

// MARK: 04 Home

struct HomeView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < 350
            let heroH = min(hSize == .regular ? 440 : 260, max(150, geo.size.height * (hSize == .regular ? 0.4 : 0.3)))
            ZStack {
                BackgroundArt(name: WorldCatalog.background(store.profile.currentWorld), dim: 0.25)
                VStack(spacing: 0) {
                    HStack {
                        Text("Velvet Cascade").vcFont(.title2).foregroundColor(Palette.warmIvory).accessibilityAddTraits(.isHeader)
                        Spacer()
                        TicketBalance(count: store.profile.hintBalance)
                        IconButton(glyph: .gear, label: "Settings") { env.tap(); env.router.push(.settings) }
                    }
                    .padding(.horizontal, Metrics.side)
                    .frame(minHeight: 48)
                    progressLine.padding(.top, 6)
                    Spacer(minLength: 6)
                    ArtImage(name: "vc_vell_idle", maxPoints: heroH)
                        .frame(width: heroH * 190 / 260, height: heroH)
                        .accessibilityLabel("Vell, the jester conductor")
                        .accessibilityHidden(false)
                    Spacer(minLength: 6)
                    VStack(spacing: 12) {
                        Button(primaryTitle) { primary() }.goldButton()
                        HStack(spacing: 12) {
                            tile(title: "Worlds", subtitle: "\(store.profile.completedLevels)/180 levels",
                                 image: WorldCatalog.background(store.profile.currentWorld), showImage: !narrow) {
                                env.tap(); env.router.push(.worlds)
                            }
                            tile(title: "Daily Encore", subtitle: store.dailyEligible ? "Ready" : "Collected today",
                                 image: "vc_daily_machine", showImage: !narrow, highlight: store.dailyEligible) {
                                env.tap(); env.router.push(.daily)
                            }
                        }
                        Button("How to Play") { env.tap(); env.router.push(.handbook(topic: nil)) }
                            .buttonStyle(TextLinkStyle())
                    }
                    .padding(.horizontal, Metrics.side)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: Metrics.maxContentWidth)
            }
        }
    }

    private var progressLine: some View {
        HStack(spacing: 8) {
            Text("World \(store.profile.currentWorld): \(WorldCatalog.name(store.profile.currentWorld))")
                .vcFont(.secondary).foregroundColor(Palette.warmIvory)
            Text("•").foregroundColor(Palette.mutedRose)
            Text("\(store.profile.completedLevels)/180").vcFont(.secondary).foregroundColor(Palette.mutedRose).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryTitle: String {
        if let run = store.profile.activeRun { return "Resume Level \(run.levelID)" }
        if let c = store.profile.currentLevel { return "Play Level \(c)" }
        return "Replay Levels"
    }

    private func primary() {
        env.tap()
        if store.profile.activeRun != nil {
            env.resumeActiveRun()
        } else if let c = store.profile.currentLevel {
            env.router.push(.levelBrief(level: c))
        } else {
            env.router.push(.worlds)
        }
    }

    private func tile(title: String, subtitle: String, image: String, showImage: Bool, highlight: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if showImage {
                    ArtImage(name: image, contentMode: image.hasPrefix("vc_world") ? .fill : .fit, maxPoints: 56)
                        .frame(width: image.hasPrefix("vc_world") ? 72 : 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text(title).vcFont(.headline).foregroundColor(Palette.warmIvory).multilineTextAlignment(.center)
                Text(subtitle).vcFont(.caption).foregroundColor(highlight ? Palette.spotlightGold : Palette.mutedRose)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius).fill(Palette.panel.opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius).stroke(highlight ? Palette.spotlightGold : Palette.antiqueGold.opacity(0.7), lineWidth: highlight ? 1.5 : 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: 05 Worlds

struct WorldsView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore

    var body: some View {
        ZStack {
            BackgroundArt(name: WorldCatalog.background(store.profile.currentWorld), dim: 0.55)
            VStack(spacing: 0) {
                ScreenHeader(title: "Worlds", onBack: { env.back() })
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(1...9, id: \.self) { w in
                                if w == store.profile.currentWorld && !store.profile.campaignComplete {
                                    currentCard(w).id(w)
                                } else {
                                    card(w).id(w)
                                }
                            }
                        }
                        .padding(.horizontal, Metrics.side)
                        .padding(.bottom, 24)
                    }
                    .onAppear { proxy.scrollTo(store.profile.currentWorld, anchor: .center) }
                }
            }
            .frame(maxWidth: Metrics.maxContentWidth)
        }
    }

    private func status(_ w: Int) -> (String, Color) {
        if !store.profile.isWorldUnlocked(w) { return ("Locked", Palette.mutedRose) }
        if store.profile.worldCompleted(w) == 20 { return ("Complete", Palette.success) }
        if w == store.profile.currentWorld { return ("Current", Palette.spotlightGold) }
        return ("Open", Palette.warmIvory)
    }

    private func currentCard(_ w: Int) -> some View {
        Button { open(w) } label: {
            VStack(alignment: .leading, spacing: 10) {
                ArtImage(name: WorldCatalog.background(w), contentMode: .fill, maxPoints: 420)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .bottomLeading) {
                        Text("Current").vcFont(.caption).foregroundColor(Palette.ink)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Palette.spotlightGold)).padding(10)
                    }
                texts(w, big: true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius).fill(Palette.panel.opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius).stroke(Palette.spotlightGold, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func card(_ w: Int) -> some View {
        let unlocked = store.profile.isWorldUnlocked(w)
        return Button { open(w) } label: {
            ViewThatFitsCompat {
                HStack(spacing: 12) {
                    thumb(w, unlocked: unlocked)
                    texts(w, big: false)
                    Spacer(minLength: 0)
                }
            } fallback: {
                VStack(alignment: .leading, spacing: 8) {
                    thumb(w, unlocked: unlocked)
                    texts(w, big: false)
                }
            }
            .padding(12)
            .frame(minHeight: 116)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius).fill(Palette.panel.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius).stroke(Palette.antiqueGold.opacity(0.6), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func thumb(_ w: Int, unlocked: Bool) -> some View {
        ArtImage(name: WorldCatalog.background(w), contentMode: .fill, maxPoints: 156)
            .frame(width: 156, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(unlocked ? 0 : 0.55)))
            .overlay { if !unlocked { LockGlyph().frame(width: 22, height: 26) } }
    }

    private func texts(_ w: Int, big: Bool) -> some View {
        let st = status(w)
        let range = WorldCatalog.range(w)
        return VStack(alignment: .leading, spacing: 4) {
            Text("World \(w) · \(WorldCatalog.name(w))").vcFont(big ? .title2 : .headline).foregroundColor(Palette.warmIvory)
                .fixedSize(horizontal: false, vertical: true)
            Text("Levels \(range.lowerBound)–\(range.upperBound)").vcFont(.secondary).foregroundColor(Palette.mutedRose)
            if store.profile.isWorldUnlocked(w) {
                HStack(spacing: 10) {
                    Text("\(store.profile.worldCompleted(w))/20").vcFont(.secondary).foregroundColor(Palette.warmIvory).monospacedDigit()
                        .fixedSize()
                    HStack(spacing: 3) {
                        StarShape().fill(Palette.spotlightGold).frame(width: 12, height: 12)
                        Text("\(store.profile.worldStars(w))/60").vcFont(.secondary).foregroundColor(Palette.warmIvory).monospacedDigit()
                            .fixedSize()
                    }
                    if big { Text(st.0).vcFont(.caption).foregroundColor(st.1) }
                }
                if !big { Text(st.0).vcFont(.caption).foregroundColor(st.1) }
            } else {
                Text("Complete Level \(20 * (w - 1))").vcFont(.secondary).foregroundColor(Palette.mutedRose)
            }
        }
    }

    private func open(_ w: Int) {
        env.tap()
        guard store.profile.isWorldUnlocked(w) else {
            env.audio.play(.uiError)
            return
        }
        env.router.push(.worldMap(world: w))
    }
}

/// iOS 15: заменитель ViewThatFits — выбирает горизонтальную раскладку, если ширина ≥ 340.
struct ViewThatFitsCompat<A: View, B: View>: View {
    @ViewBuilder var primary: A
    @ViewBuilder var fallback: B
    @Environment(\.dynamicTypeSize) private var type

    var body: some View {
        GeometryReader { g in
            Group {
                if g.size.width >= 300 && type < .accessibility1 { primary } else { fallback }
            }
            .frame(width: g.size.width, alignment: .leading)
            .background(GeometryReader { inner in Color.clear.preference(key: HeightKey.self, value: inner.size.height) })
        }
        .modifier(AdaptiveHeight())
    }
}

struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct AdaptiveHeight: ViewModifier {
    @State private var h: CGFloat = 100
    func body(content: Content) -> some View {
        content.frame(height: h).onPreferenceChange(HeightKey.self) { if $0 > 0 { h = $0 } }
    }
}

// MARK: 06 World Map

struct WorldMapView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore
    let world: Int
    @State private var selected: Int?

    private var range: ClosedRange<Int> { WorldCatalog.range(world) }

    var body: some View {
        GeometryReader { geo in
            let W = min(geo.size.width, Metrics.maxContentWidth)
            let stepY: CGFloat = 76
            let pathHeight = max(1400, stepY * 20 + 160)
            ZStack {
                BackgroundArt(name: WorldCatalog.background(world), dim: 0.3)
                VStack(spacing: 0) {
                    ScreenHeader(title: WorldCatalog.name(world), onBack: { env.back() }) {
                        Button("Current") { scrollTarget = currentOrSelected }
                            .buttonStyle(TextLinkStyle())
                            .accessibilityLabel("Current Level")
                    }
                    .background(Palette.deepVelvet.opacity(0.85))
                    ScrollViewReader { proxy in
                        ScrollView {
                            ZStack(alignment: .topLeading) {
                                pathShape(W: W, stepY: stepY, height: pathHeight)
                                ForEach(Array(range), id: \.self) { id in
                                    let p = nodePoint(id, W: W, stepY: stepY, height: pathHeight)
                                    Button { select(id) } label: {
                                        LevelNode(number: id, state: nodeState(id), selected: selected == id)
                                            .frame(width: 56, height: 64)
                                    }
                                    .buttonStyle(.plain)
                                    .position(p)
                                    .id(id)
                                    .accessibilityLabel("Level \(id)")
                                    .accessibilityValue(nodeAccessibility(id))
                                    .accessibilityAddTraits(selected == id ? .isSelected : [])
                                }
                            }
                            .frame(width: W, height: pathHeight)
                            .frame(maxWidth: .infinity)
                        }
                        .onAppear {
                            selected = currentOrSelected
                            let target = currentOrSelected
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { proxy.scrollTo(target, anchor: .center) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { proxy.scrollTo(target, anchor: .center) }
                        }
                        .onChange(of: scrollTarget) { t in
                            if let t { withAnimation { proxy.scrollTo(t, anchor: .center) }; selected = t; scrollTarget = nil }
                        }
                    }
                    selectionPanel.frame(minHeight: 132)
                }
                .frame(maxWidth: Metrics.maxContentWidth)
            }
        }
    }

    @State private var scrollTarget: Int?

    private var currentOrSelected: Int {
        if let c = store.profile.currentLevel, range.contains(c) { return c }
        if let run = store.profile.activeRun, range.contains(run.levelID) { return run.levelID }
        return range.filter { store.profile.isUnlocked($0) }.last ?? range.lowerBound
    }

    /// Узлы по центрам x=0.28W/0.50W/0.72W с шагом 76 pt, порядок снизу вверх.
    private func nodePoint(_ id: Int, W: CGFloat, stepY: CGFloat, height: CGFloat) -> CGPoint {
        let i = id - range.lowerBound
        let xs: [CGFloat] = [0.50, 0.72, 0.50, 0.28]
        return CGPoint(x: W * xs[i % 4], y: height - 80 - CGFloat(i) * stepY)
    }

    private func pathShape(W: CGFloat, stepY: CGFloat, height: CGFloat) -> some View {
        let pts = range.map { nodePoint($0, W: W, stepY: stepY, height: height) }
        let path = Path { p in
            guard let f = pts.first else { return }
            p.move(to: f)
            for i in 1..<pts.count {
                let a = pts[i - 1], b = pts[i]
                p.addCurve(to: b, control1: CGPoint(x: a.x, y: (a.y + b.y) / 2), control2: CGPoint(x: b.x, y: (a.y + b.y) / 2))
            }
        }
        return ZStack {
            path.stroke(Palette.nodeLine, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            path.stroke(Palette.spotlightGold.opacity(0.7), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        .accessibilityHidden(true)
    }

    private func nodeState(_ id: Int) -> LevelNode.State {
        if let b = store.profile.best(id) { return .completed(b.stars) }
        if !store.profile.isUnlocked(id) { return .locked }
        if id == store.profile.currentLevel { return .current }
        return .available
    }

    private func nodeAccessibility(_ id: Int) -> String {
        switch nodeState(id) {
        case .locked: return "Locked"
        case .current: return "Current level"
        case .available: return "Open"
        case .completed(let s): return "Complete, \(s) of 3 stars"
        }
    }

    private func select(_ id: Int) {
        env.tap()
        guard store.profile.isUnlocked(id) else {
            env.audio.play(.uiError)
            selected = id
            return
        }
        selected = id
    }

    private var selectionPanel: some View {
        let id = selected ?? currentOrSelected
        let def = env.levels.summary(id)
        let unlocked = store.profile.isUnlocked(id)
        return TheatrePanel(padding: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Level \(id)").vcFont(.headline).foregroundColor(Palette.warmIvory)
                    Text(def?.title ?? "").vcFont(.secondary).foregroundColor(Palette.mutedRose).lineLimit(1)
                    HStack(spacing: 6) {
                        ForEach(Array((def?.objectives ?? []).enumerated()), id: \.offset) { _, o in
                            ObjectiveIcon(objective: o, size: 24)
                        }
                        if let b = store.profile.best(id) { MiniStars(stars: b.stars, size: 13) }
                    }
                }
                Spacer(minLength: 4)
                if unlocked {
                    Button(store.profile.activeRun?.levelID == id ? "Resume" : "Play") {
                        env.tap()
                        if store.profile.activeRun?.levelID == id { env.resumeActiveRun() } else { env.router.push(.levelBrief(level: id)) }
                    }
                    .goldButton()
                    .frame(maxWidth: 150)
                } else {
                    Text("Complete Level \(id - 1)").vcFont(.secondary).foregroundColor(Palette.mutedRose)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: 07 Level Brief

struct LevelBriefView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let levelID: Int

    var body: some View {
        let loaded = Result { try env.levels.load(levelID) }
        ZStack {
            BackgroundArt(name: WorldCatalog.background(WorldCatalog.world(ofLevel: levelID)), dim: 0.25)
            VStack(spacing: 0) {
                ScreenHeader(title: "Level \(levelID)", onBack: { env.back() })
                ScrollView {
                    switch loaded {
                    case .success(let def): card(def)
                    case .failure: invalidCard
                    }
                }
            }
            .frame(maxWidth: Metrics.maxContentWidth)
        }
    }

    private func card(_ def: LevelDefinition) -> some View {
        TheatrePanel {
            VStack(spacing: 14) {
                Text(def.title).vcFont(.title).foregroundColor(Palette.warmIvory).multilineTextAlignment(.center)
                Text("World \(def.worldID) · \(WorldCatalog.name(def.worldID))").vcFont(.secondary).foregroundColor(Palette.mutedRose)
                VStack(spacing: 8) {
                    ForEach(Array(def.objectives.enumerated()), id: \.offset) { _, o in
                        HStack(spacing: 12) {
                            ObjectiveIcon(objective: o, size: 40)
                            Text(objectiveText(o, def: def)).vcFont(.body).foregroundColor(Palette.warmIvory)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .frame(minHeight: 48)
                        .accessibilityElement(children: .combine)
                    }
                }
                AdaptiveStack(vertical: typeSize.isAccessibilitySize, spacing: 12) {
                    statBox("Moves", "\(def.initialMoves)")
                    statBox("Stage Charge", "\(def.initialCharge)/12")
                    statBox("Best", store.profile.best(def.id).map { "\($0.stars)★" } ?? "—")
                }
                if let m = def.newMechanic {
                    HStack(spacing: 12) {
                        mechanicIcon(def).frame(width: 72, height: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("New: \(m)").vcFont(.headline).foregroundColor(Palette.spotlightGold)
                            Text(def.tutorialSteps.first?.text ?? "").vcFont(.secondary).foregroundColor(Palette.warmIvory)
                                .fixedSize(horizontal: false, vertical: true)
                            if let t = def.newMechanicTopic.flatMap({ HandbookTopic(rawValue: $0) }) {
                                Button("Learn Mechanic") { env.tap(); env.router.push(.handbook(topic: t)) }
                                    .buttonStyle(TextLinkStyle())
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.plumStage))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.spotlightGold.opacity(0.6), lineWidth: 0.8))
                }
                if let b = store.profile.best(def.id) {
                    Text("Personal best: \(b.stars) star\(b.stars == 1 ? "" : "s"), \(b.minMovesUsed) moves. Replaying never lowers it.")
                        .vcFont(.caption).foregroundColor(Palette.mutedRose).multilineTextAlignment(.center)
                }
                Button("Start Level") {
                    env.tap()
                    env.startLevel(def.id)
                }
                .goldButton()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func objectiveText(_ o: ObjectiveDef, def: LevelDefinition) -> String {
        switch o {
        case .collect(let c, let t): return "Collect \(t) \(c.name) gems"
        case .plates:
            let n = def.floors.filter { $0.type == "plate" }.count
            return "Clear all \(n) Velvet Plates"
        case .keys:
            let dirs = Set(def.exitPorts.map { $0.direction.label }).sorted().joined(separator: ", ")
            return "Guide \(def.initialKeyIDs.count) key\(def.initialKeyIDs.count == 1 ? "" : "s") out (exits: \(dirs))"
        }
    }

    @ViewBuilder
    private func mechanicIcon(_ def: LevelDefinition) -> some View {
        let name: String = {
            switch def.newMechanicTopic {
            case "crates": return "vc_crate"
            case "ice": return "vc_ice_overlay"
            case "chains": return "vc_chain_overlay"
            case "shutters": return "vc_shutter_closed"
            case "velvetPlates": return "vc_velvet_plate"
            case "keysExits": return "vc_exit_port"
            case "curtainSweep": return "vc_baffle"
            case "stageTurn": return "vc_turn_crown"
            case "specials": return def.newMechanic == "Prism" ? "vc_special_prism" : "vc_special_burst"
            default: return "vc_gem_heart"
            }
        }()
        ArtImage(name: name, maxPoints: 72)
    }

    private func statBox(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).vcFont(.hudSmall).foregroundColor(Palette.warmIvory).fixedSize()
            Text(title).vcFont(.caption).foregroundColor(Palette.mutedRose).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.plumStage))
        .accessibilityElement(children: .combine)
    }

    private var invalidCard: some View {
        MessageState(kind: .warning, title: "Level Invalid", message: "This stage is unavailable.",
                     detail: "Your progress is safe. This is not counted as a loss.",
                     diagnosticID: "VC-LVL-\(levelID)") {
            Button("Back to Map") { env.router.goWorldMap(WorldCatalog.world(ofLevel: levelID)) }.goldButton()
        }
        .padding(20)
    }
}
