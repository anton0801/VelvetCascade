// ResultViews.swift — 11 Curtain Call, 12 One More Act, 13 New Theatre / Final Bow.
// Результат и награда уже сохранены одной транзакцией до показа; повторное открытие не начисляет билет.

import SwiftUI
import VelvetDomain

struct CurtainCallView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore

    var body: some View {
        if let r = store.profile.lastResult, r.won {
            content(r)
        } else {
            HomeView()
        }
    }

    private func content(_ r: LastResult) -> some View {
        let world = WorldCatalog.world(ofLevel: r.levelID)
        return ZStack {
            BackgroundArt(name: WorldCatalog.background(world), dim: 0.3)
            if !env.reduceMotion { ConfettiBurst(count: 20).allowsHitTesting(false) }
            ScrollView {
                VStack(spacing: 14) {
                    ArtImage(name: "vc_vell_celebrate", maxPoints: 220)
                        .frame(width: 180, height: 220)
                        .padding(.top, 12)
                        .accessibilityHidden(true)
                    Text("Curtain Call!").vcFont(.display).foregroundColor(Palette.spotlightGold).accessibilityAddTraits(.isHeader)
                    Text("Level \(r.levelID) Complete").vcFont(.title2).foregroundColor(Palette.warmIvory)
                    ZStack {
                        ArtImage(name: "vc_result_crest", maxPoints: 200).frame(width: 200, height: 100)
                        ResultStars(stars: r.stars, animate: !env.reduceMotion).offset(y: -4)
                    }
                    .frame(height: 110)
                    HStack(spacing: 12) {
                        stat("Moves Left", "\(r.movesLeft)")
                        stat("Turns Used", "\(r.turnsUsed)")
                    }
                    if let prev = r.previousBest {
                        let improved = r.stars > prev.stars || r.movesUsed < prev.minMovesUsed
                        Text(improved ? "New personal best!" : "Best Result: \(prev.stars)★ in \(prev.minMovesUsed) moves")
                            .vcFont(.secondary).foregroundColor(improved ? Palette.success : Palette.mutedRose)
                    }
                    if r.firstClear {
                        HStack(spacing: 8) {
                            ArtImage(name: "vc_hint_ticket", maxPoints: 24).frame(width: 24, height: 24)
                            Text(r.creditedTickets > 0 ? "First clear: +\(r.creditedTickets) Hint Ticket" : "Ticket limit reached")
                                .vcFont(.body).foregroundColor(Palette.warmIvory)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    VStack(spacing: 12) {
                        Button(nextTitle(r)) { next(r) }.goldButton()
                        HStack(spacing: 12) {
                            Button("Replay") { env.tap(); env.router.replaceTop(.levelBrief(level: r.levelID)) }.velvetButton()
                            Button("World Map") { env.tap(); env.router.goWorldMap(world) }.velvetButton()
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: Metrics.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            env.session = nil
            if r.firstClear && r.creditedTickets > 0 { UIAccessibility.post(notification: .announcement, argument: "First clear, plus one Hint Ticket") }
        }
    }

    private func nextTitle(_ r: LastResult) -> String {
        if r.levelID == 180 { return "The Final Bow" }
        if r.levelID % 20 == 0 { return "A New Theatre" }
        return "Next Level"
    }

    private func next(_ r: LastResult) {
        env.tap()
        if r.levelID == 180 {
            env.router.push(.newTheatre(world: 9, final: true))
        } else if r.levelID % 20 == 0 {
            env.audio.play(.worldUnlock)
            env.router.push(.newTheatre(world: r.levelID / 20 + 1, final: false))
        } else {
            env.router.replaceTop(.levelBrief(level: r.levelID + 1))
        }
    }

    private func stat(_ t: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(v).vcFont(.hud).foregroundColor(Palette.warmIvory)
            Text(t).vcFont(.caption).foregroundColor(Palette.mutedRose)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.panel.opacity(0.92)))
        .accessibilityElement(children: .combine)
    }
}

struct OneMoreActView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore

    var body: some View {
        if let r = store.profile.lastResult, !r.won {
            content(r)
        } else {
            HomeView()
        }
    }

    private func content(_ r: LastResult) -> some View {
        let world = WorldCatalog.world(ofLevel: r.levelID)
        return ZStack {
            BackgroundArt(name: WorldCatalog.background(world), dim: 0.4)
            ScrollView {
                VStack(spacing: 14) {
                    ArtImage(name: "vc_vell_encourage", maxPoints: 220)
                        .frame(width: 180, height: 220)
                        .padding(.top, 12)
                        .accessibilityHidden(true)
                    Text("One More Act").vcFont(.display).foregroundColor(Palette.warmIvory).accessibilityAddTraits(.isHeader)
                    Text("A new plan can change the ending.").vcFont(.body).foregroundColor(Palette.mutedRose)
                    TheatrePanel(padding: 14) {
                        VStack(spacing: 10) {
                            Text("Level \(r.levelID)").vcFont(.headline).foregroundColor(Palette.warmIvory)
                            HStack(spacing: 16) {
                                ForEach(Array(r.remaining.prefix(3).enumerated()), id: \.offset) { _, item in
                                    VStack(spacing: 4) {
                                        ObjectiveIcon(objective: item.objective, size: 32)
                                        Text(item.remaining == 0 ? "Done" : "\(item.remaining) left")
                                            .vcFont(.caption).foregroundColor(item.remaining == 0 ? Palette.success : Palette.warmIvory)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                            HStack(spacing: 20) {
                                Text("Moves Used \(r.movesUsed)").vcFont(.secondary).foregroundColor(Palette.mutedRose)
                                Text("Turns Used \(r.turnsUsed)").vcFont(.secondary).foregroundColor(Palette.mutedRose)
                            }
                            if let b = store.profile.best(r.levelID) {
                                Text("Your best stays at \(b.stars)★.").vcFont(.caption).foregroundColor(Palette.mutedRose)
                            }
                        }
                    }
                    Button("Try Again") { env.tap(); env.startLevel(r.levelID, replaceConfirmed: true) }.goldButton()
                    Button("World Map") { env.tap(); env.router.goWorldMap(world) }.velvetButton()
                    Button("Review Rules") { env.tap(); env.router.push(.handbook(topic: nil)) }.buttonStyle(TextLinkStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: Metrics.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { env.session = nil }
    }
}

struct NewTheatreView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore
    let world: Int
    let isFinal: Bool

    var body: some View {
        ZStack {
            BackgroundArt(name: WorldCatalog.background(isFinal ? 9 : world), dim: 0.3)
            if !env.reduceMotion { SparkEmitter(count: 20, area: CGSize(width: 320, height: 300), seed: world) }
            ScrollView {
                VStack(spacing: 14) {
                    ArtImage(name: "vc_vell_celebrate", maxPoints: 160).frame(width: 130, height: 160).padding(.top, 12)
                        .accessibilityHidden(true)
                    ZStack {
                        ArtImage(name: "vc_result_crest", maxPoints: 200).frame(width: 200, height: 100)
                        Text(isFinal ? "The Final Bow" : "A New Theatre")
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundColor(Palette.spotlightGold)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(width: 96)
                            .offset(y: -2)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if isFinal {
                        Text("180 stages complete").vcFont(.title2).foregroundColor(Palette.warmIvory)
                        Text("\(store.profile.completedLevels)/180 levels · \(store.profile.totalStars)/540 stars")
                            .vcFont(.body).foregroundColor(Palette.mutedRose).monospacedDigit()
                        Text("Every level stays open for replays and better stars.")
                            .vcFont(.secondary).foregroundColor(Palette.mutedRose).multilineTextAlignment(.center)
                    } else {
                        Text("\(WorldCatalog.name(world - 1)) complete").vcFont(.body).foregroundColor(Palette.mutedRose)
                        ArtImage(name: WorldCatalog.background(world), contentMode: .fill, maxPoints: 360)
                            .frame(height: 140).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.spotlightGold, lineWidth: 1))
                        Text("World \(world) · \(WorldCatalog.name(world))").vcFont(.title2).foregroundColor(Palette.warmIvory)
                        Text(WorldCatalog.tagline(world)).vcFont(.secondary).foregroundColor(Palette.mutedRose)
                        let r = WorldCatalog.range(world)
                        Text("Levels \(r.lowerBound)–\(r.upperBound) · \(store.profile.worldStars(world))/60 stars")
                            .vcFont(.secondary).foregroundColor(Palette.warmIvory)
                    }
                    if isFinal {
                        Button("Replay Levels") { env.tap(); env.router.reset([.home, .worlds]) }.goldButton()
                    } else {
                        Button("Enter World") { env.tap(); env.router.reset([.home, .worlds, .worldMap(world: world)]) }.goldButton()
                        Button("World Map") { env.tap(); env.router.reset([.home, .worlds]) }.velvetButton()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: Metrics.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { env.audio.play(.worldUnlock); env.session = nil }
    }
}
