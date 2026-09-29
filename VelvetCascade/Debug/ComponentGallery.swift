// ComponentGallery.swift — DEBUG-превью 20 кодовых компонентов UI01–UI20 в состояниях normal/pressed/disabled/focused.
#if DEBUG
import SwiftUI
import VelvetDomain

struct ComponentGallery: View {
    @EnvironmentObject var env: AppEnvironment
    let page: Int

    var body: some View {
        ZStack {
            Palette.deepVelvet.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Components · page \(page) of 4").vcFont(.title2).foregroundColor(Palette.warmIvory)
                    switch page {
                    case 1: p1
                    case 2: p2
                    case 3: p3
                    default: p4
                    }
                }
                .padding(16)
            }
        }
    }

    private func label(_ t: String) -> some View {
        Text(t).vcFont(.caption).foregroundColor(Palette.spotlightGold)
    }

    @ViewBuilder private var p1: some View {
        label("UI01 GoldButton — normal / pressed / disabled / committing")
        HStack(spacing: 8) {
            Button("Play") {}.buttonStyle(GoldButtonStyle())
            Button("Play") {}.buttonStyle(GoldButtonStyle(forcePressed: true))
        }
        HStack(spacing: 8) {
            Button("Play") {}.buttonStyle(GoldButtonStyle()).disabled(true)
            Button("Saving") {}.buttonStyle(GoldButtonStyle(busy: true))
        }
        label("UI02 VelvetButton — normal / pressed / disabled / destructive")
        HStack(spacing: 8) {
            Button("Retry") {}.buttonStyle(VelvetButtonStyle())
            Button("Retry") {}.buttonStyle(VelvetButtonStyle(forcePressed: true))
        }
        HStack(spacing: 8) {
            Button("Retry") {}.buttonStyle(VelvetButtonStyle()).disabled(true)
            Button("Reset") {}.buttonStyle(VelvetButtonStyle(destructive: true))
        }
        label("UI03 IconButton — gear / back / pause / close / focused ring")
        HStack(spacing: 12) {
            IconButton(glyph: .gear, label: "Settings") {}
            IconButton(glyph: .back, label: "Back") {}
            IconButton(glyph: .pause, label: "Pause") {}
            IconButton(glyph: .close, label: "Close") {}
            IconButton(glyph: .help, label: "Help") {}.overlay(Circle().stroke(Palette.spotlightGold, lineWidth: 2).padding(-3))
        }
    }

    @ViewBuilder private var p2: some View {
        label("UI04 TheatrePanel")
        TheatrePanel { Text("Intermission").vcFont(.title2).foregroundColor(Palette.warmIvory) }
        label("UI05 BoardFrame · UI06 BoardCell (normal / selected / hint)")
        HStack(spacing: 12) {
            BoardFrameView(viewport: 110)
            VStack(spacing: 6) {
                cell().overlay(EmptyView())
                cell().overlay(SelectionFrame(size: 44))
                cell().overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.spotlightGold, lineWidth: 2))
            }
        }
        label("UI07 StageChargeGauge — 0 / 7 / 12")
        StageChargeGauge(charge: 0)
        StageChargeGauge(charge: 7)
        StageChargeGauge(charge: 12)
        label("UI08 GravityCompass — q0..q3, preview dashed")
        HStack { ForEach(0..<4, id: \.self) { GravityCompass(q: $0, showLabel: true) } }
        GravityCompass(q: 1, previewQ: 2, showLabel: true)
    }

    @ViewBuilder private var p3: some View {
        label("UI09 MovesBadge — normal / few moves")
        HStack { MovesBadge(moves: 18); MovesBadge(moves: 3) }
        label("UI10 ObjectiveBadge — remaining / done")
        HStack(spacing: 14) {
            ObjectiveBadge(objective: .collect(color: .heart, target: 12), remaining: 7)
            ObjectiveBadge(objective: .plates, remaining: 4)
            ObjectiveBadge(objective: .keys, remaining: 0)
        }
        label("UI11 LevelNode — locked / current / available / completed / selected")
        HStack(spacing: 10) {
            LevelNode(number: 5, state: .locked)
            LevelNode(number: 4, state: .current)
            LevelNode(number: 3, state: .available)
            LevelNode(number: 2, state: .completed(2))
            LevelNode(number: 1, state: .completed(3), selected: true)
        }
        .padding(.bottom, 12)
        label("UI12 ResultStars — 1 / 2 / 3")
        VStack(alignment: .leading, spacing: 4) {
            ResultStars(stars: 1, animate: false)
            ResultStars(stars: 2, animate: false)
            ResultStars(stars: 3, animate: false)
        }
    }

    @ViewBuilder private var p4: some View {
        label("UI13 LineSparkOverlay · UI14 DamageMarkers · UI15 Port/Switch marks")
        HStack(spacing: 10) {
            ZStack { cell(); PieceView(model: PieceModel(id: 1, kind: .lineSpark(.heart, .horizontal), cell: Coord(0, 0), pinned: false), size: 44, angle: 0, highContrast: false) }.frame(width: 44, height: 44)
            ZStack { cell(); PieceView(model: PieceModel(id: 2, kind: .lineSpark(.star, .vertical), cell: Coord(0, 0), pinned: false), size: 44, angle: 0, highContrast: false) }.frame(width: 44, height: 44)
            CellLayerView(cell: Cell(playable: true, blocker: .crate(hp: 2)), size: 44, angle: 0, highContrast: false, links: []).frame(width: 44, height: 44)
            CellLayerView(cell: Cell(playable: true, floor: .plate(hp: 2)), size: 44, angle: 0, highContrast: false, links: []).frame(width: 44, height: 44)
            CellLayerView(cell: Cell(playable: true, floor: .switchPlate(group: 0, active: false)), size: 44, angle: 0, highContrast: false, links: []).frame(width: 44, height: 44)
            CellLayerView(cell: Cell(playable: true, floor: .switchPlate(group: 1, active: true)), size: 44, angle: 0, highContrast: false, links: []).frame(width: 44, height: 44)
        }
        HStack(spacing: 30) {
            ZStack { cell(); PortView(port: ExitPort(x: 0, y: 0, direction: .right, keyID: 1), active: true, size: 44, angle: 0, done: false, inner: true, step: 46) }.frame(width: 44, height: 44)
            ZStack { cell(); PortView(port: ExitPort(x: 0, y: 0, direction: .right, keyID: 2), active: false, size: 44, angle: 0, done: false, inner: true, step: 46) }.frame(width: 44, height: 44)
        }
        .padding(.trailing, 60)
        label("UI16 ModalScrim + UI20 MessageState")
        ZStack {
            Palette.scrim.opacity(0.62)
            MessageState(kind: .warning, title: "Save Failed", message: "Progress could not be saved.", detail: "Your previous save is safe.", diagnosticID: "VC-SAVE-DEMO") {
                Button("Retry") {}.goldButton()
            }
            .padding(12)
        }
        .frame(height: 260)
        label("UI17 ReelWindow · UI18 SparkEmitter")
        HStack {
            ReelWindow(symbol: .bell, start: .bell, stopAfter: 1, loops: 1, spinStart: nil, reduceMotion: false).frame(width: 60, height: 100)
            ReelWindow(symbol: .star, start: .star, stopAfter: 1, loops: 1, spinStart: nil, reduceMotion: false).frame(width: 60, height: 100)
            SparkEmitter(count: 12, area: CGSize(width: 140, height: 100), seed: 3)
        }
        label("UI19 SettingsRow")
        SettingsRow(title: "Haptics", icon: "hand.tap") { Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(SwitchToggleStyle(tint: Palette.spotlightGold)) }
        SettingsRow(title: "Export Progress", value: "JSON", icon: "square.and.arrow.up")
        SavingIndicator()
    }

    private func cell() -> some View {
        RoundedRectangle(cornerRadius: 5).fill(Palette.cellFill).frame(width: 44, height: 44)
    }
}
#endif
