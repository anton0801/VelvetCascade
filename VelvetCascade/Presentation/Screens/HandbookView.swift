// HandbookView.swift — 16 Stage Handbook: 11 тем, короткий текст и программная демонстрация на движке.
// Демонстрации изолированы от профиля; VoiceOver описывает before/action/after.

import SwiftUI
import VelvetDomain

struct HandbookDemo {
    let initial: GameState
    let action: GameActionKind?
    let before: String
    let actionText: String
    let after: String
}

enum HandbookContent {
    static let base5 = ["HDCBS", "CBSHD", "SHDCB", "DCBSH", "BSHDC"]
    static let run5 = ["HHCBS", "CBHSD", "SHDCB", "DCBSH", "BSHDC"]
    static let runSwap = GameActionKind.swap(from: Coord(2, 1), to: Coord(2, 0))

    static func text(_ t: HandbookTopic) -> [String] {
        switch t {
        case .matches:
            return ["Swap two neighbouring gems to line up three or more of the same shape. Diagonal swaps and swaps without a match don't count and cost nothing.",
                    "Each match charges the stage: three gems add 1, four add 3, five or more add 5. A single move and its cascades can add at most 6.",
                    "Five shapes — Heart, Diamond, Clover, Bell and Star — can be told apart without colour."]
        case .stageTurn:
            return ["With a full Stage Charge (12 of 12) you can turn the whole stage a quarter turn clockwise. A turn costs one move and the full charge.",
                    "The stage turns, but pieces still fall toward the floor. The small gravity diagram shows which side of the original board is now the floor.",
                    "The preview is free: it shows the edge that will be swept and which exits become active. It never predicts new gems.",
                    "Cascades after a turn can give back up to 4 charge."]
        case .curtainSweep:
            return ["A full board has no gaps, so every turn begins with a Curtain Sweep: the last cell of every falling line on the new floor edge is hit once.",
                    "Brass baffles, crates, closed shutters and pinned gems split lines into shorter falls, so a split stage has several short edges.",
                    "Each part of the stage refills from its own inlet — new gems never pass through walls."]
        case .keysExits:
            return ["Keys can't be swapped and never break. They fall with the gems.",
                    "Each exit has an arrow and a number for its key. An exit is active only when its arrow points to the floor — turn the stage until it does.",
                    "Clear the gems between the key and its exit, and the key drops out. Some levels need two or three turns; plan your charge."]
        case .velvetPlates:
            return ["Velvet Plates lie under gems. A plate loses a layer when a gem standing on it is cleared by a match, a Sweep or a blast.",
                    "A falling gem or a key leaving does not count. Plates with two studs need two clears — at most one per wave."]
        case .crates:
            return ["Crates don't move. A match next to a crate, or a blast that reaches it, knocks off one layer per wave.",
                    "A broken crate leaves an empty cell that fills from above."]
        case .ice:
            return ["Ice pins a gem: it can't be swapped and it doesn't fall. Matching that gem, or blasting it, cracks the ice.",
                    "When the last layer breaks the gem stays for that wave. If it still forms a line, it clears in the next wave — so thick ice doesn't always need two of your moves."]
        case .chains:
            return ["Chains pin a gem like ice but break with a single hit.",
                    "A chained gem can still be part of a match; the match breaks the chain first. Crates, by contrast, have no gem inside."]
        case .shutters:
            return ["Closed shutters block cells. Clear the gem on the switch with the same letter and its shutters open for good.",
                    "Opened cells fill with gems from the next fall. Switches stay on; pressing them again does nothing."]
        case .specials:
            return ["Four in a row makes a LineSpark: it clears its whole row or column, even across gaps and baffles.",
                    "Five in a T or L makes a Stage Burst that clears a 3×3 area. Five in a straight line makes a Prism: swap it with a gem to clear that colour.",
                    "Swap two specials together for bigger combos. Specials fire when swapped, matched, swept or hit."]
        case .dailyEncore:
            return ["Once per UTC day you get one free spin of the Daily Encore. Three reels each stop on one of the five shapes with equal chance.",
                    "Mixed pays 1 Hint Ticket (48%), any Pair pays 2 (48%), a Triple pays 5 (4%). There are no paid spins and no streaks.",
                    "Hint Tickets only buy optional hints. They never change moves, charge or the stage."]
        }
    }

    static func demo(_ t: HandbookTopic) -> HandbookDemo? {
        switch t {
        case .matches:
            return HandbookDemo(initial: DemoBoards.match3, action: .swap(from: Coord(1, 1), to: Coord(1, 0)),
                                before: "A three by three stage with two Hearts on the top row.",
                                actionText: "The centre Heart swaps upward.",
                                after: "Three Hearts clear and the charge rises by one.")
        case .stageTurn:
            return HandbookDemo(initial: DemoBoards.state(base5, charge: 12), action: .rotate,
                                before: "A full stage with a full charge.",
                                actionText: "The stage turns a quarter clockwise.",
                                after: "The right-hand column reached the floor and was swept; gems fell toward the floor.")
        case .curtainSweep:
            var rows = base5
            rows[2] = "SH#CB"
            return HandbookDemo(initial: DemoBoards.state(rows, charge: 12), action: .rotate,
                                before: "A stage with a brass baffle in the middle row.",
                                actionText: "The stage turns.",
                                after: "The baffle split one line, so two short edges were swept in that row.")
        case .keysExits:
            return HandbookDemo(initial: DemoBoards.rotate, action: .rotate,
                                before: "A key sits one cell from an exit facing right. The exit is inactive.",
                                actionText: "The stage turns so the exit faces the floor.",
                                after: "The Sweep clears the gem in front of the key, and the key drops out.")
        case .velvetPlates:
            return HandbookDemo(initial: DemoBoards.state(run5, plates: [Coord(0, 0): 1, Coord(1, 0): 1, Coord(2, 0): 2]),
                                action: runSwap,
                                before: "Three plates on the top row, the right one with two layers.",
                                actionText: "A Heart swaps up to complete the row.",
                                after: "Two plates lift; the double plate loses one layer.")
        case .crates:
            var rows = run5
            rows[0] = "HHCXS"
            return HandbookDemo(initial: DemoBoards.state(rows), action: runSwap,
                                before: "A crate stands next to two Hearts.",
                                actionText: "A Heart swaps up beside the crate.",
                                after: "The match next to the crate breaks it.")
        case .ice:
            var rows = run5
            rows[0] = "hHCBS"
            return HandbookDemo(initial: DemoBoards.state(rows), action: runSwap,
                                before: "The left Heart is frozen in ice.",
                                actionText: "A Heart swaps up to complete the row.",
                                after: "The ice cracks and its Heart stays for this wave.")
        case .chains:
            return HandbookDemo(initial: DemoBoards.state(run5, chains: [Coord(1, 0)]), action: runSwap,
                                before: "The middle Heart is chained.",
                                actionText: "A Heart swaps up to complete the row.",
                                after: "The chain breaks with one hit; the gem stays for this wave.")
        case .shutters:
            var rows = run5
            rows[4] = "BSHDZ"
            return HandbookDemo(initial: DemoBoards.state(rows, links: [ShutterSwitchLink(group: 0, switches: [Coord(0, 0)], shutters: [Coord(4, 4)])],
                                                          switches: [Coord(0, 0): 0]),
                                action: runSwap,
                                before: "Switch A is under the left Heart; shutter A closes the bottom-right cell.",
                                actionText: "A Heart swaps up and the row clears.",
                                after: "Switch A turns on and shutter A opens for good.")
        case .specials:
            var rows = base5
            rows[2] = "SH-CB"
            return HandbookDemo(initial: DemoBoards.state(rows), action: .swap(from: Coord(2, 2), to: Coord(2, 1)),
                                before: "A LineSpark lies in the middle of the stage.",
                                actionText: "It swaps upward.",
                                after: "It fires along its row and clears it.")
        case .dailyEncore:
            return nil
        }
    }
}

struct StageHandbookView: View {
    @EnvironmentObject var env: AppEnvironment
    let initialTopic: HandbookTopic?
    @State private var open: HandbookTopic?
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        ZStack {
            CalmBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Stage Handbook", onBack: { gotIt() })
                if hSize == .regular {
                    HStack(alignment: .top, spacing: 16) {
                        ScrollView { VStack(spacing: 8) { ForEach(HandbookTopic.allCases) { topicButton($0) } } }
                            .frame(width: 260)
                        ScrollView { if let t = open { TopicContent(topic: t, onGotIt: gotIt) } }
                    }
                    .padding(.horizontal, 20)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(HandbookTopic.allCases) { t in
                                    VStack(spacing: 0) {
                                        topicButton(t)
                                        if open == t { TopicContent(topic: t, onGotIt: gotIt).padding(.top, 8) }
                                    }
                                    .id(t)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        }
                        .onAppear { if let t = open { DispatchQueue.main.async { proxy.scrollTo(t, anchor: .top) } } }
                    }
                }
            }
            .frame(maxWidth: hSize == .regular ? 900 : Metrics.maxContentWidth)
        }
        .onAppear { if open == nil { open = initialTopic ?? .matches } }
    }

    private func topicButton(_ t: HandbookTopic) -> some View {
        Button {
            env.tap()
            withAnimation(.easeInOut(duration: 0.2)) { open = open == t ? nil : t }
        } label: {
            HStack {
                Text(t.title).vcFont(.headline).foregroundColor(open == t ? Palette.spotlightGold : Palette.warmIvory)
                Spacer()
                VectorGlyph(kind: .back, color: Palette.mutedRose).frame(width: 14, height: 14)
                    .rotationEffect(.degrees(open == t ? 90 : -90))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(open == t ? Palette.spotlightGold : Palette.antiqueGold.opacity(0.5), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(open == t ? .isSelected : [])
        .accessibilityHint(open == t ? "Collapse" : "Expand")
    }

    /// Got It → источник; если вход был из Pause — вернуться в Pause.
    private func gotIt() {
        env.audio.play(.uiBack)
        if env.handbookFromPause { env.session?.paused = true; env.handbookFromPause = false }
        env.router.pop()
    }
}

struct TopicContent: View {
    @EnvironmentObject var env: AppEnvironment
    let topic: HandbookTopic
    let onGotIt: () -> Void
    @StateObject private var holder = DemoHolder()
    @State private var phaseText = ""

    var body: some View {
        TheatrePanel(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                if topic == .stageTurn {
                    ArtImage(name: "vc_turn_crown", maxPoints: 56).frame(width: 56, height: 56).frame(maxWidth: .infinity)
                }
                ForEach(HandbookContent.text(topic), id: \.self) { p in
                    Text(p).vcFont(.body).foregroundColor(Palette.warmIvory).fixedSize(horizontal: false, vertical: true)
                }
                if let demo = HandbookContent.demo(topic), let s = holder.session {
                    VStack(spacing: 8) {
                        BoardView(session: s, viewport: min(240, UIScreen.main.bounds.width - 100),
                                  highContrast: env.store.settings.highContrastSymbols, gravityLabels: true)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Demonstration")
                            .accessibilityValue("Before: \(demo.before) Action: \(demo.actionText) After: \(demo.after)")
                        Text(phaseText).vcFont(.caption).foregroundColor(Palette.mutedRose).multilineTextAlignment(.center)
                        Button("Replay Demo") { replay(demo) }.buttonStyle(TextLinkStyle())
                    }
                    .frame(maxWidth: .infinity)
                } else if topic == .dailyEncore {
                    HStack(spacing: 6) {
                        ForEach(GemColor.allCases, id: \.self) { c in ArtImage(name: GemArt.name(c), maxPoints: 36).frame(width: 36, height: 36) }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                }
                Button("Got It") { onGotIt() }.goldButton()
            }
        }
        .onAppear {
            guard let demo = HandbookContent.demo(topic), holder.session == nil else { return }
            let s = GameSession.demo(env: env, state: demo.initial, id: -100 - HandbookTopic.allCases.firstIndex(of: topic)!)
            s.onDemoFinished = { _ in phaseText = "After: " + demo.after }
            holder.session = s
            phaseText = "Before: " + demo.before
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { replay(demo) }
        }
    }

    private func replay(_ demo: HandbookDemo) {
        guard let s = holder.session, let a = demo.action else { return }
        s.resetDemo(demo.initial)
        phaseText = "Action: " + demo.actionText
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { s.demoPerform(a) }
    }
}
