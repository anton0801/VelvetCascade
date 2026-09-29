// GameplayView.swift — 08 Gameplay, 09 Turn Preview, 10 Intermission (состояния одного экрана).

import SwiftUI
import VelvetDomain

struct GameplayView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var session: GameSession
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showCellPicker = false

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, Metrics.maxContentWidth + 40)
            let bigType = typeSize.isAccessibilitySize
            let compact = geo.size.height < 700 || bigType
            let headerH: CGFloat = bigType ? 52 : 44
            let hudH: CGFloat = bigType ? 96 : (compact ? 74 : 84)
            let controlsH: CGFloat = bigType ? 200 : (compact ? 104 : 118)
            let gaps: CGFloat = compact ? 8 + 8 : 12 + 16
            let availH = geo.size.height - headerH - hudH - controlsH - gaps - 8
            let viewport = max(220, min(width - 32, 430, availH))
            ZStack {
                BackgroundArt(name: WorldCatalog.background(session.level.worldID), dim: 0.35)
                VStack(spacing: 0) {
                    header.frame(height: headerH)
                    hud.frame(height: hudH).padding(.top, 4)
                    Spacer(minLength: compact ? 8 : 12)
                    ZStack {
                        BoardView(session: session, viewport: viewport,
                                  highContrast: env.store.settings.highContrastSymbols,
                                  gravityLabels: env.store.settings.gravityLabels,
                                  dimmed: session.preview != nil || session.paused)
                        if !env.reduceMotion { CurtainLayer(session: session, viewport: viewport) }
                    }
                    .frame(width: viewport, height: viewport)
                    Spacer(minLength: compact ? 8 : 16)
                    controls(compact: compact)
                        .frame(minHeight: controlsH)
                        .padding(.bottom, 6)
                }
                .frame(width: width)
                .frame(maxWidth: .infinity)

                if let b = session.banner, !session.paused { bannerView(b) }
                if let t = session.toast { toastView(t) }
                if let c = session.infoCell { infoCard(c) }
                if let p = session.preview { previewSheet(p) }
                if session.paused { pauseSheet }
                if session.restartConfirm { restartSheet }
            }
        }
        .sheet(isPresented: $showCellPicker) {
            CellPickerSheet(session: session)
        }
        .onAppear { env.musicForCurrentRoute() }
    }

    // MARK: Header / HUD

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Level \(session.level.id)").vcFont(.headline).foregroundColor(Palette.warmIvory)
                if !typeSize.isAccessibilitySize {
                    Text(session.level.title).vcFont(.caption).foregroundColor(Palette.mutedRose).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if UIAccessibility.isVoiceOverRunning || typeSize >= .accessibility1 {
                Button("Cells") { showCellPicker = true }
                    .buttonStyle(TextLinkStyle())
                    .accessibilityHint("Choose a cell from a list and swap it with a neighbour.")
            }
            IconButton(glyph: .pause, label: "Pause") { session.pause() }
        }
        .padding(.horizontal, Metrics.side)
    }

    private var hud: some View {
        HStack(alignment: .center, spacing: 10) {
            MovesBadge(moves: session.hudMoves)
            Spacer(minLength: 4)
            HStack(spacing: 10) {
                ForEach(Array(session.level.objectives.enumerated()), id: \.offset) { _, o in
                    ObjectiveBadge(objective: o, remaining: session.objectiveRemaining(o), compact: typeSize.isAccessibilitySize)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.panel.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.antiqueGold.opacity(0.6), lineWidth: 0.8))
        }
        .padding(.horizontal, Metrics.side)
    }

    // MARK: Controls

    private func controls(compact: Bool) -> some View {
        let full = session.hudCharge >= 12 && session.hudMoves > 0
        return VStack(spacing: compact ? 8 : 10) {
            HStack(spacing: 10) {
                ArtImage(name: "vc_vell_portrait", maxPoints: 40)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Palette.panel))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Palette.antiqueGold, lineWidth: 1))
                StageChargeGauge(charge: session.hudCharge)
                    .onTapGesture {
                        if !full { session.toast = "Match gems to charge the stage." }
                    }
                Spacer(minLength: 0)
                if env.store.settings.gravityLabels {
                    GravityCompass(q: session.hudQ, previewQ: session.preview?.nextQ, showLabel: !compact)
                } else {
                    GravityCompass(q: session.hudQ, previewQ: session.preview?.nextQ, showLabel: false)
                }
            }
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { turnButton(full: full); hintButton }
            } else {
                HStack(spacing: 12) { turnButton(full: full); hintButton.frame(maxWidth: 170) }
            }
        }
        .padding(.horizontal, Metrics.side)
    }

    private func turnButton(full: Bool) -> some View {
        Button {
            session.openTurnPreview()
        } label: {
            HStack(spacing: 8) {
                ArtImage(name: "vc_turn_crown", maxPoints: 40).frame(width: 32, height: 32)
                    .background(Circle().fill(Palette.spotlightGold.opacity(full ? 0.35 : 0)).blur(radius: 6))
                Text("Turn Stage")
            }
        }
        .goldButton()
        .disabled(!full)
        .overlay(RoundedRectangle(cornerRadius: Metrics.ctaRadius).stroke(Palette.spotlightGold, lineWidth: session.hintTurn ? 3 : 0))
        .modifier(ChargePulse(active: full && !env.reduceMotion))
        .accessibilityHint(full ? "Opens a free preview of the quarter turn." : "Needs a full Stage Charge.")
    }

    private var hintButton: some View {
        Button { session.requestHint() } label: {
            HStack(spacing: 6) {
                ArtImage(name: "vc_hint_ticket", maxPoints: 24).frame(width: 24, height: 24)
                Text(session.hintButtonTitle)
            }
        }
        .velvetButton()
        .accessibilityLabel(session.hintButtonTitle)
    }

    // MARK: Overlays

    private func bannerView(_ step: TutorialStep) -> some View {
        VStack {
            TheatrePanel(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title).vcFont(.headline).foregroundColor(Palette.spotlightGold)
                    Text(step.text).vcFont(.secondary).foregroundColor(Palette.warmIvory).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Got it") { session.banner = nil }.buttonStyle(TextLinkStyle())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 50)   // ниже строки заголовка: Pause остаётся доступной
            Spacer()
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
    }

    private func toastView(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .vcFont(.secondary)
                .foregroundColor(Palette.warmIvory)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Palette.panel))
                .overlay(Capsule().stroke(Palette.antiqueGold.opacity(0.7), lineWidth: 0.8))
                .padding(.bottom, 150)
                .padding(.horizontal, 24)
                .onTapGesture { session.toast = nil }
        }
        .transition(.opacity)
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: text)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { if session.toast == text { session.toast = nil } }
        }
    }

    private func infoCard(_ c: Coord) -> some View {
        let cell = session.board[c]
        return ModalScrim(dismissOnTapOutside: { session.infoCell = nil }) {
            TheatrePanel {
                VStack(spacing: 10) {
                    Text("On this cell").vcFont(.title2).foregroundColor(Palette.warmIvory)
                    Text(CellDescriber.describe(cell, at: c, state: session.state, ports: session.level.exitPorts, extracted: session.hudExtracted))
                        .vcFont(.body).foregroundColor(Palette.warmIvory).multilineTextAlignment(.center)
                    Text(ruleHint(cell)).vcFont(.secondary).foregroundColor(Palette.mutedRose).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Close") { session.infoCell = nil }.velvetButton(compact: true)
                }
            }
        }
    }

    private func ruleHint(_ cell: Cell) -> String {
        if case .key? = cell.occupant?.kind { return "Keys can't be swapped. Turn the stage so an exit points down, then clear the gems in the way." }
        if cell.overlay != nil { return "Pinned. Match this gem or blast it to break the overlay." }
        switch cell.blocker {
        case .crate?: return "A match next to the crate, or a blast, removes one layer."
        case .wall?: return "Baffles never break and split the falls."
        case .shutter?: return "Clear the gem on the switch with the same letter to open it."
        default: break
        }
        if case .plate? = cell.floor { return "Clear a gem standing here to lift a layer." }
        if case .switchPlate? = cell.floor { return "Clear a gem standing here to open its shutters." }
        if case .lineSpark? = cell.occupant?.kind { return "Clears its whole row or column. Swap it to fire." }
        if case .stageBurst? = cell.occupant?.kind { return "Blasts a 3×3 area. Swap it to fire." }
        if case .prism? = cell.occupant?.kind { return "Swap with a gem to clear that colour." }
        return "Swap with a neighbour to make a line of three."
    }

    private func previewSheet(_ p: TurnPreview) -> some View {
        VStack {
            Spacer()
            TheatrePanel(padding: 16) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ArtImage(name: "vc_vell_portrait", maxPoints: 40).frame(width: 40, height: 40).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Turn Stage").vcFont(.headline).foregroundColor(Palette.warmIvory)
                            Text("1 move • 12 charge").vcFont(.secondary).foregroundColor(Palette.mutedRose)
                        }
                        Spacer()
                        GravityCompass(q: session.hudQ, previewQ: p.nextQ, showLabel: false)
                    }
                    Text(previewDescription(p)).vcFont(.caption).foregroundColor(Palette.mutedRose)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("Cancel") { session.cancelPreview() }.velvetButton()
                        Button("Turn") { session.confirmTurn() }.goldButton()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func previewDescription(_ p: TurnPreview) -> String {
        var s = "Pieces will fall toward the stage's \(p.nextGravity.label.lowercased()) side. The Curtain Sweep clears \(p.frontier.count - p.frontierKeys.count) highlighted edge cell\(p.frontier.count - p.frontierKeys.count == 1 ? "" : "s")."
        if !p.frontierKeys.isEmpty { s += " Keys on the edge are not harmed." }
        if !p.immediateKeyExtractions.isEmpty { s += " A key already at its exit will leave the stage." }
        if !p.activePorts.isEmpty { s += " \(p.activePorts.count) exit\(p.activePorts.count == 1 ? "" : "s") will be active." }
        return s
    }

    private var pauseSheet: some View {
        ModalScrim {
            IntermissionPanel(session: session)
        }
    }

    private var restartSheet: some View {
        ModalScrim {
            TheatrePanel {
                VStack(spacing: 14) {
                    Text("Restart this level?").vcFont(.title2).foregroundColor(Palette.warmIvory)
                    Text("Your current attempt will be replaced.").vcFont(.body).foregroundColor(Palette.mutedRose)
                        .multilineTextAlignment(.center)
                    Button("Keep Playing") { session.restartConfirm = false }.goldButton()
                    Button("Restart") { session.restart() }.velvetButton(destructive: true)
                }
            }
        }
    }
}

/// Спокойная пульсация полного заряда: не чаще одного цикла за 2 s, без стробоскопа.
struct ChargePulse: ViewModifier {
    let active: Bool
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .shadow(color: Palette.spotlightGold.opacity(active && on ? 0.55 : 0), radius: active && on ? 12 : 0)
            .onAppear { restart() }
            .onChange(of: active) { _ in restart() }
    }
    private func restart() {
        on = false
        guard active else { return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { on = true }
    }
}

/// VC24/VC25 по бокам и луч VC26 во время поворота; шторы закрывают только узкие полосы.
struct CurtainLayer: View {
    @ObservedObject var session: GameSession
    let viewport: CGFloat

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ArtImage(name: "vc_curtain_left", contentMode: .fill, maxPoints: viewport)
                    .frame(width: viewport * 0.16, height: viewport * 1.1)
                    .offset(x: session.curtainsClosed ? 0 : -viewport * 0.3)
                Spacer()
                ArtImage(name: "vc_curtain_right", contentMode: .fill, maxPoints: viewport)
                    .frame(width: viewport * 0.16, height: viewport * 1.1)
                    .offset(x: session.curtainsClosed ? 0 : viewport * 0.3)
            }
            .frame(width: viewport * 1.3)
            .opacity(session.curtainsClosed ? 1 : 0)
            ArtImage(name: "vc_spotlight_beam", maxPoints: 220)
                .frame(width: min(220, viewport * 0.6), height: viewport * 1.05)
                .blendMode(.plusLighter)
                .opacity(session.beamVisible ? 0.25 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct IntermissionPanel: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var session: GameSession
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        TheatrePanel {
            VStack(spacing: 12) {
                Text("Intermission").vcFont(.title).foregroundColor(Palette.warmIvory).accessibilityAddTraits(.isHeader)
                Text("Level \(session.level.id) • \(session.hudMoves) moves left").vcFont(.secondary).foregroundColor(Palette.mutedRose)
                Button("Resume") { session.resume() }.goldButton()
                Button("Restart Level") { session.restartConfirm = true; session.paused = false }.velvetButton()
                Button("World Map") {
                    session.paused = true
                    env.router.goWorldMap(session.level.worldID)
                }
                .velvetButton()
                AdaptiveStack(vertical: typeSize.isAccessibilitySize, spacing: 12) {
                    AudioToggle(title: "Music", value: Binding(
                        get: { env.store.settings.musicVolume > 0.001 },
                        set: { on in
                            var s = env.store.settings
                            if on { s.musicVolume = max(0.05, s.lastNonZeroMusic) } else { s.lastNonZeroMusic = max(0.05, s.musicVolume); s.musicVolume = 0 }
                            env.store.settings = s
                        }))
                    AudioToggle(title: "Sound Effects", value: Binding(
                        get: { env.store.settings.sfxVolume > 0.001 },
                        set: { on in
                            var s = env.store.settings
                            if on { s.sfxVolume = max(0.05, s.lastNonZeroSFX) } else { s.lastNonZeroSFX = max(0.05, s.sfxVolume); s.sfxVolume = 0 }
                            env.store.settings = s
                        }))
                }
                Button("Help") {
                    env.handbookFromPause = true
                    env.router.push(.handbook(topic: session.level.newMechanicTopic.flatMap { HandbookTopic(rawValue: $0) }))
                }
                .buttonStyle(TextLinkStyle())
            }
        }
        .padding(.horizontal, 4)
    }
}

struct AudioToggle: View {
    let title: String
    @Binding var value: Bool
    var body: some View {
        Toggle(isOn: $value) {
            Text(title).vcFont(.secondary).foregroundColor(Palette.warmIvory)
        }
        .toggleStyle(SwitchToggleStyle(tint: Palette.spotlightGold))
        .frame(minHeight: 44)
    }
}

/// Доступный список клеток с кнопками ≥44 pt; выбранная клетка показывает доступных соседей.
struct CellPickerSheet: View {
    @ObservedObject var session: GameSession
    @Environment(\.presentationMode) private var presentation
    @State private var picked: Coord?

    var body: some View {
        ZStack {
            Palette.deepVelvet.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Choose a cell").vcFont(.title2).foregroundColor(Palette.warmIvory).padding(.top, 20)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if let p = picked {
                            Text("Swap \(label(p)) with…").vcFont(.headline).foregroundColor(Palette.spotlightGold)
                            ForEach([Direction.up, .down, .left, .right], id: \.self) { d in
                                let screen = BoardTransform.toScreen(p, q: session.state.q, n: session.n).offset(d)
                                if screen.x >= 0, screen.y >= 0, screen.x < session.n, screen.y < session.n {
                                    let other = BoardTransform.toLocal(screen, q: session.state.q, n: session.n)
                                    if session.board.isPlayable(other), session.board[other].isSwappable {
                                        Button("\(d.label): \(label(other))") {
                                            session.swipe(fromLocal: p, screenDirection: d)
                                            presentation.wrappedValue.dismiss()
                                        }
                                        .velvetButton(compact: true)
                                    }
                                }
                            }
                            Button("Choose another cell") { picked = nil }.buttonStyle(TextLinkStyle())
                        } else {
                            ForEach(swappableCells, id: \.self) { c in
                                Button(label(c)) { picked = c }.velvetButton(compact: true)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                Button("Close") { presentation.wrappedValue.dismiss() }.goldButton().padding(.horizontal, 20).padding(.bottom, 12)
            }
        }
    }

    private var swappableCells: [Coord] {
        var r: [Coord] = []
        for y in 0..<session.n {
            for x in 0..<session.n {
                let local = BoardTransform.toLocal(Coord(x, y), q: session.state.q, n: session.n)
                if session.board.isPlayable(local) && session.board[local].isSwappable { r.append(local) }
            }
        }
        return r
    }

    private func label(_ local: Coord) -> String {
        let s = BoardTransform.toScreen(local, q: session.state.q, n: session.n)
        let kind = session.board[local].occupant.map { CellDescriber.describe($0.kind) } ?? "Empty"
        return "Row \(s.y + 1), column \(s.x + 1): \(kind)"
    }
}
