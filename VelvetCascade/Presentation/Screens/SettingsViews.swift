// SettingsViews.swift — 17 Settings, 18 Credits, 19 Import Review, 20 Recovery, 22 Reset Confirmation.

import SwiftUI
import UniformTypeIdentifiers
import VelvetDomain

// MARK: System share / document picker (не перекрашиваются непрозрачной накладкой)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let u = urls.first { onPick(u) }
        }
    }
}

// MARK: 17 Settings

/// Один sheet на экран: несколько `.sheet` на одном уровне в iOS 15 конфликтуют.
enum SettingsSheet: Identifiable {
    case share(URL)
    case picker

    var id: String {
        switch self {
        case .share(let u): return "share-" + u.lastPathComponent
        case .picker: return "picker"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var activeSheet: SettingsSheet?

    var body: some View {
        ZStack {
            Palette.deepVelvet.ignoresSafeArea()
            VStack(spacing: 0) {
                ScreenHeader(title: "Settings", onBack: { env.back() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        group("Sound") {
                            slider("Music", icon: "music.note", value: Binding(get: { store.settings.musicVolume }, set: { v in
                                var s = store.settings; s.musicVolume = v; if v > 0.01 { s.lastNonZeroMusic = v }; store.settings = s }))
                            slider("Sound Effects", icon: "speaker.wave.2", value: Binding(get: { store.settings.sfxVolume }, set: { v in
                                var s = store.settings; s.sfxVolume = v; if v > 0.01 { s.lastNonZeroSFX = v }; store.settings = s }))
                            slider("Stage Ambience", icon: "wind", value: Binding(get: { store.settings.ambienceVolume }, set: { v in
                                var s = store.settings; s.ambienceVolume = v; store.settings = s }))
                            Button("Preview SFX") { env.audio.userInteracted(); env.audio.play(.hintReveal, gainDB: -6) }
                                .buttonStyle(TextLinkStyle())
                        }
                        group("Play") {
                            toggle("Haptics", icon: "hand.tap", \.haptics)
                            if typeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Reduce Motion").vcFont(.body).foregroundColor(Palette.warmIvory)
                                    reduceMotionPicker
                                    Rectangle().fill(Palette.separator).frame(height: 0.5)
                                }
                                .padding(.vertical, 6)
                            } else {
                                SettingsRow(title: "Reduce Motion", icon: "figure.walk") {
                                    reduceMotionPicker.frame(maxWidth: 190)
                                }
                            }
                            toggle("High Contrast Symbols", icon: "circle.lefthalf.filled", \.highContrastSymbols)
                            toggle("Gravity Labels", icon: "arrow.down.to.line", \.gravityLabels)
                        }
                        group("Progress") {
                            actionRow("Export Progress", icon: "square.and.arrow.up") { export() }
                            actionRow("Import Progress", icon: "square.and.arrow.down") { activeSheet = .picker }
                                .disabled(store.isCommitting)
                            actionRow("Credits", icon: "info.circle") { env.tap(); env.router.push(.credits) }
                        }
                        Button {
                            env.tap()
                            env.router.modal = .resetConfirm
                        } label: {
                            Text("Reset Progress").frame(maxWidth: .infinity)
                        }
                        .velvetButton(destructive: true)
                        .disabled(store.isCommitting)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, Metrics.side)
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: Metrics.maxContentWidth)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .share(let url): ShareSheet(items: [url])
            case .picker: DocumentPicker { url in importFile(url) }
            }
        }
    }

    private var reduceMotionPicker: some View {
        Picker("Reduce Motion", selection: Binding(get: { store.settings.reduceMotion }, set: { v in
            var s = store.settings; s.reduceMotion = v; store.settings = s })) {
            ForEach(ReduceMotionSetting.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).vcFont(.caption).foregroundColor(Palette.mutedRose).padding(.bottom, 4)
            c()
        }
    }

    private func slider(_ title: String, icon: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon).foregroundColor(Palette.spotlightGold).frame(width: 24).accessibilityHidden(true)
                Text(title).vcFont(.body).foregroundColor(Palette.warmIvory)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%").vcFont(.secondary).foregroundColor(Palette.mutedRose).monospacedDigit()
            }
            Slider(value: value, in: 0...1)
                .tint(Palette.spotlightGold)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int((value.wrappedValue * 100).rounded())) percent")
            Rectangle().fill(Palette.separator).frame(height: 0.5)
        }
        .frame(minHeight: 64)
    }

    private func toggle(_ title: String, icon: String, _ kp: WritableKeyPath<AppSettings, Bool>) -> some View {
        SettingsRow(title: title, icon: icon) {
            Toggle(title, isOn: Binding(get: { store.settings[keyPath: kp] }, set: { v in
                var s = store.settings; s[keyPath: kp] = v; store.settings = s
                env.audio.play(.uiToggle)
            }))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: Palette.spotlightGold))
        }
    }

    private func actionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsRow(title: title, icon: icon) {
                VectorGlyph(kind: .back, color: Palette.mutedRose).frame(width: 12, height: 12).rotationEffect(.degrees(180))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Export: один JSON без ключей и медиа; пользователь сам выбирает сохранение через share sheet.
    private func export() {
        env.tap()
        guard let (data, name) = try? BackupCodec.export(store.profile, now: env.clock.now()) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            activeSheet = .share(url)
        } catch {
            env.recovery = .saveFailed(diagnosticID: AppEnvironment.diagnostic("EXP"))
        }
    }

    private func importFile(_ url: URL) {
        activeSheet = nil
        let data: Data
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? Int, size > BackupCodec.maxBytes {
                env.recovery = .importInvalid(diagnosticID: AppEnvironment.diagnostic("IMP"), reason: ImportError.tooLarge.reason)
                return
            }
            data = try Data(contentsOf: url)
        } catch {
            env.recovery = .importInvalid(diagnosticID: AppEnvironment.diagnostic("IMP"), reason: ImportError.unreadable.reason)
            return
        }
        do {
            let preview = try BackupCodec.validate(data: data, fileName: url.lastPathComponent, levels: env.levels, now: env.clock.now())
            env.importPreview = preview
            env.router.push(.importReview)
        } catch let e as ImportError {
            env.recovery = .importInvalid(diagnosticID: AppEnvironment.diagnostic("IMP"), reason: e.reason)
        } catch {
            env.recovery = .importInvalid(diagnosticID: AppEnvironment.diagnostic("IMP"), reason: ImportError.unreadable.reason)
        }
    }
}

// MARK: 18 Credits

struct CreditsView: View {
    @EnvironmentObject var env: AppEnvironment

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(v) (build \(b))"
    }

    var body: some View {
        ZStack {
            CalmBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Credits", onBack: { env.back() })
                ScrollView {
                    VStack(spacing: 16) {
                        ArtImage(name: "vc_vell_portrait", maxPoints: 88)
                            .frame(width: 88, height: 88)
                            .background(Circle().fill(Palette.panel))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Palette.antiqueGold, lineWidth: 1))
                        Text("Velvet Cascade").vcFont(.title).foregroundColor(Palette.warmIvory)
                        Text(version).vcFont(.secondary).foregroundColor(Palette.mutedRose)
                        section("Game", ["An original theatrical match-3 puzzle.",
                                         "Built with SwiftUI and a custom deterministic puzzle engine.",
                                         "180 levels generated from the level briefs and verified by an automated solver."])
                        section("Artwork", artLines)
                        section("Audio", audioLines)
                        section("Characters", ["Vell is an original character created for this game."])
                        Button("Done") { env.back() }.goldButton().padding(.top, 8)
                    }
                    .padding(.horizontal, Metrics.side)
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: Metrics.maxContentWidth)
        }
    }

    private var artLines: [String] {
        let m = env.media
        guard !m.art.isEmpty else { return ["Artwork manifest unavailable."] }
        var lines = ["\(m.art.count) illustrations."]
        if m.art.allSatisfy({ $0.provenance.contains("Procedural") }) {
            lines.append("All artwork was drawn procedurally in code (vector/CoreGraphics) for this game; no image-generation model was used.")
        } else {
            lines.append(contentsOf: m.artProvenanceSummary)
        }
        return lines
    }

    private var audioLines: [String] {
        let m = env.media
        guard !m.audio.isEmpty else { return ["Audio manifest unavailable."] }
        var lines: [String] = []
        let eleven = m.elevenLabsCount
        let subs = m.substituteCount
        if eleven > 0 { lines.append("\(eleven) of \(m.audio.count) audio files were created with ElevenLabs.") }
        if subs > 0 { lines.append("\(subs) audio file\(subs == 1 ? " was" : "s were") synthesized procedurally in code for this game.") }
        return lines
    }

    private func section(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).vcFont(.headline).foregroundColor(Palette.spotlightGold)
            ForEach(lines, id: \.self) { l in
                Text(l).vcFont(.body).foregroundColor(Palette.warmIvory).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.panel))
    }
}

// MARK: 19 Import Review

struct ImportReviewView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore
    @State private var showPicker = false

    var body: some View {
        ZStack {
            CalmBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Import Review", onBack: { cancel() })
                if let p = env.importPreview {
                    ScrollView {
                        TheatrePanel {
                            VStack(alignment: .leading, spacing: 0) {
                                row("File Name", p.fileName)
                                row("Export Date", DateFormatter.localizedString(from: p.exportDate, dateStyle: .medium, timeStyle: .short))
                                row("Completed Levels", "\(p.completedLevels)/180")
                                row("Stars", "\(p.stars)/540")
                                row("Hint Tickets", "\(p.hintTickets)")
                                if let a = p.activeLevel { row("Active Level", "Level \(a)") }
                                if let d = p.droppedIncompatibleRun {
                                    Text("The saved attempt on Level \(d) was made for an older version of that level. Your results will be imported; start that level again.")
                                        .vcFont(.secondary).foregroundColor(Palette.mutedRose).padding(.top, 10)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text("Your current progress will be replaced.")
                                    .vcFont(.body).foregroundColor(Palette.error).padding(.top, 12)
                                Text("Today's Daily Encore stays collected if it was already used on this device.")
                                    .vcFont(.caption).foregroundColor(Palette.mutedRose).padding(.top, 4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(20)
                    }
                    VStack(spacing: 10) {
                        Button("Replace Progress") { replace(p) }.goldButton(busy: store.isCommitting).disabled(store.isCommitting)
                        Button("Cancel") { cancel() }.velvetButton()
                        Button("Choose Another File") { showPicker = true }.buttonStyle(TextLinkStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                } else {
                    Spacer()
                    Text("No file selected.").vcFont(.body).foregroundColor(Palette.mutedRose)
                    Spacer()
                }
            }
            .frame(maxWidth: Metrics.maxContentWidth)
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { url in
                showPicker = false
                guard let data = try? Data(contentsOf: url) else { return }
                do {
                    env.importPreview = try BackupCodec.validate(data: data, fileName: url.lastPathComponent, levels: env.levels, now: env.clock.now())
                } catch let e as ImportError {
                    env.recovery = .importInvalid(diagnosticID: AppEnvironment.diagnostic("IMP"), reason: e.reason)
                } catch {}
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(k).vcFont(.secondary).foregroundColor(Palette.mutedRose)
                Spacer(minLength: 12)
                Text(v).vcFont(.body).foregroundColor(Palette.warmIvory).multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            Rectangle().fill(Palette.separator).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private func cancel() {
        env.importPreview = nil
        env.back()
    }

    /// Backup + одна атомарная замена → Home.
    private func replace(_ p: ImportPreview) {
        env.tap()
        if store.applyImport(p) {
            env.importPreview = nil
            env.session = nil
            env.router.reset([.home])
        }
    }
}

// MARK: 20 Recovery

struct RecoveryView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore
    let kind: RecoveryKind
    @State private var showPicker = false

    var body: some View {
        ModalScrim(dismissOnTapOutside: nil) {
            switch kind {
            case .saveFailed(let diag):
                MessageState(kind: .warning, title: "Save Failed", message: "Progress could not be saved.",
                             detail: "Your previous save is safe.", diagnosticID: diag) {
                    Button("Retry") { _ = store.retryPending() }.goldButton()
                    Button("Back") {
                        store.discardPending()
                        env.recovery = nil
                        env.session?.toast = "Your last action wasn't saved."
                    }
                    .velvetButton()
                }
            case .importInvalid(let diag, let reason):
                MessageState(kind: .warning, title: "Import Invalid", message: "This save file cannot be imported.",
                             detail: reason + " Your current progress has not changed.", diagnosticID: diag) {
                    Button("Choose Another File") { showPicker = true }.goldButton()
                    Button("Cancel") { env.recovery = nil }.velvetButton()
                }
            case .levelInvalid(let id, let diag):
                MessageState(kind: .warning, title: "Level Invalid", message: "This stage is unavailable.",
                             detail: "Level \(id) could not be loaded. It isn't counted as a loss and your progress is safe.",
                             diagnosticID: diag) {
                    Button("Back to Map") {
                        env.recovery = nil
                        env.session = nil
                        env.router.goWorldMap(WorldCatalog.world(ofLevel: max(1, id)))
                    }
                    .goldButton()
                }
            case .restoreBackup(let diag):
                MessageState(kind: .info, title: "Restore previous backup?",
                             message: "Your latest save could not be read, but an earlier verified backup is available.",
                             detail: "Nothing has been erased.", diagnosticID: diag) {
                    Button("Restore") {
                        if store.restoreBackup() { env.router.reset([store.profile.onboardingCompleted ? .home : .welcome]) }
                    }
                    .goldButton()
                    Button("Cancel") { store.declineRestore() }.velvetButton()
                }
            case .unrecoverable(let diag):
                MessageState(kind: .warning, title: "Save Unreadable",
                             message: "Your saved progress could not be read and no backup was found.",
                             detail: "The damaged file will be kept aside, not deleted.", diagnosticID: diag) {
                    Button("Start New Profile") {
                        store.startNewProfileAfterCorruption()
                        env.router.reset([.welcome])
                    }
                    .velvetButton(destructive: true)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { url in
                showPicker = false
                env.recovery = nil
                guard let data = try? Data(contentsOf: url) else { return }
                do {
                    env.importPreview = try BackupCodec.validate(data: data, fileName: url.lastPathComponent, levels: env.levels, now: env.clock.now())
                    env.router.push(.importReview)
                } catch let e as ImportError {
                    env.recovery = .importInvalid(diagnosticID: AppEnvironment.diagnostic("IMP"), reason: e.reason)
                } catch {}
            }
        }
    }
}

// MARK: 22 Reset Confirmation

struct ResetConfirmationView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var store: ProgressStore

    var body: some View {
        ModalScrim(dismissOnTapOutside: nil) {
            TheatrePanel {
                VStack(spacing: 14) {
                    WarningGlyph(color: Palette.spotlightGold)
                    Text("Reset your progress?").vcFont(.title2).foregroundColor(Palette.warmIvory).accessibilityAddTraits(.isHeader)
                    Text("Levels, stars and your current attempt will be erased.")
                        .vcFont(.body).foregroundColor(Palette.warmIvory).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Today's bonus will stay collected.")
                        .vcFont(.secondary).foregroundColor(Palette.mutedRose).multilineTextAlignment(.center)
                    Button("Cancel") { env.tap(); env.router.modal = nil }.goldButton()
                    Button("Reset Progress") {
                        env.router.modal = nil
                        if store.resetProgress() {
                            env.session = nil
                            env.router.reset([.home])
                        }
                    }
                    .velvetButton(destructive: true)
                    .disabled(store.isCommitting)
                    .padding(.top, 12)
                }
            }
        }
    }
}
