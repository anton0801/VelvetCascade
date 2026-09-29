// AudioService.swift — шины Music / SFX / Ambience, лимит 10 SFX-голосов с приоритетами, duck и crossfade.
//
// Категория .ambient уважает Silent Mode и чужое аудио. Музыка и ambience — AVAudioPlayer с бесшовной петлёй
// (PCM WAV), SFX — AVAudioEngine: 10 голосов, каждый через Varispeed (для S38 с высотой 0/+2/+4 полутона).
// Master headroom −6 dB. Музыка стартует только после первого взаимодействия пользователя.

import AVFoundation
import Foundation

enum SFX: String, CaseIterable {
    case uiTap = "vc_ui_tap", uiBack = "vc_ui_back", uiToggle = "vc_ui_toggle", uiError = "vc_ui_error"
    case curtainOpen = "vc_curtain_open", curtainClose = "vc_curtain_close"
    case swapValid = "vc_swap_valid", swapInvalid = "vc_swap_invalid", matchThree = "vc_match_three"
    case cascadeTwo = "vc_cascade_two", cascadeThree = "vc_cascade_three", cascadeFour = "vc_cascade_four"
    case gemLand = "vc_gem_land", specialCreate = "vc_special_create", lineSpark = "vc_line_spark"
    case stageBurst = "vc_stage_burst", prismClear = "vc_prism_clear", chargeTick = "vc_charge_tick"
    case turnReady = "vc_turn_ready", turnStart = "vc_turn_start", stageRotate = "vc_stage_rotate"
    case turnLock = "vc_turn_lock", curtainSweep = "vc_curtain_sweep", keyExtract = "vc_key_extract"
    case plateClear = "vc_plate_clear", crateHit = "vc_crate_hit", crateBreak = "vc_crate_break"
    case iceCrack = "vc_ice_crack", chainBreak = "vc_chain_break", switchPress = "vc_switch_press"
    case shutterOpen = "vc_shutter_open", hintReveal = "vc_hint_reveal", levelWin = "vc_level_win"
    case levelFail = "vc_level_fail", worldUnlock = "vc_world_unlock", dailyOpen = "vc_daily_open"
    case reelStop = "vc_reel_stop", dailyReward = "vc_daily_reward"

    enum Priority: Int, Comparable {
        case low = 0, medium, high, highest
        static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }

    var priority: Priority {
        switch self {
        case .uiTap, .uiBack, .uiToggle, .gemLand, .chargeTick: return .low
        case .levelWin, .levelFail, .worldUnlock, .dailyReward: return .highest
        case .lineSpark, .stageBurst, .prismClear, .turnReady, .turnStart, .stageRotate, .turnLock,
             .curtainSweep, .keyExtract, .reelStop: return .high
        default: return .medium
        }
    }

    /// Не обрывать при переполнении (извлечение ключа, результат).
    var protected: Bool { self == .keyExtract || priority == .highest }
}

enum MusicTrack: String {
    case menu = "vc_menu_waltz_loop"
    case gameplay = "vc_gameplay_loop"
    case finale = "vc_finale_loop"
}

enum AmbienceTrack: String {
    case theatre = "vc_theatre_room_loop"
    case footlights = "vc_footlight_air_loop"
}

final class AudioService {
    private let engine = AVAudioEngine()
    private let sfxMixer = AVAudioMixerNode()
    private struct Voice {
        let player: AVAudioPlayerNode
        let varispeed: AVAudioUnitVarispeed
        var sfx: SFX?
        var startedAt: TimeInterval = 0
        var busyUntil: TimeInterval = 0
    }
    private var voices: [Voice] = []
    private var buffers: [SFX: AVAudioPCMBuffer] = [:]
    private var engineReady = false

    private var musicPlayer: AVAudioPlayer?
    private var fadingOutMusic: AVAudioPlayer?
    private var currentTrack: MusicTrack?
    private var desiredTrack: MusicTrack?
    private var ambiencePlayer: AVAudioPlayer?
    private var currentAmbience: AmbienceTrack?
    private var desiredAmbience: AmbienceTrack?

    private(set) var musicVolume: Double = 0.45
    private(set) var sfxVolume: Double = 0.70
    private(set) var ambienceVolume: Double = 0.20
    private var duckFactor: Double = 1.0
    private var interacted = false
    private var suspended = false
    private let headroom: Double = 0.5   // −6 dB

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption(_:)),
                                               name: AVAudioSession.interruptionNotification, object: session)
    }

    // MARK: Setup

    private func prepareEngine() {
        guard !engineReady else { return }
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.attach(sfxMixer)
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: format)
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            let v = AVAudioUnitVarispeed()
            engine.attach(p)
            engine.attach(v)
            voices.append(Voice(player: p, varispeed: v))
        }
        for sfx in SFX.allCases {
            guard let url = Bundle.main.url(forResource: sfx.rawValue, withExtension: "wav"),
                  let file = try? AVAudioFile(forReading: url),
                  let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { continue }
            try? file.read(into: buf)
            buffers[sfx] = buf
        }
        let voiceFormat = buffers.values.first?.format ?? format
        for v in voices {
            engine.connect(v.player, to: v.varispeed, format: voiceFormat)
            engine.connect(v.varispeed, to: sfxMixer, format: voiceFormat)
        }
        engine.mainMixerNode.outputVolume = Float(headroom)
        sfxMixer.outputVolume = Float(sfxVolume)
        engine.prepare()
        engineReady = true
    }

    private func startEngineIfNeeded() -> Bool {
        prepareEngine()
        if engine.isRunning { return true }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    // MARK: Volumes

    func apply(music: Double, sfx: Double, ambience: Double) {
        musicVolume = music
        sfxVolume = sfx
        ambienceVolume = ambience
        if engineReady { sfxMixer.outputVolume = Float(sfx) }
        musicPlayer?.volume = Float(music * headroom * duckFactor)
        ambiencePlayer?.volume = Float(ambience * headroom)
        if music <= 0.001 { musicPlayer?.pause() } else if !suspended, interacted, musicPlayer?.isPlaying == false { musicPlayer?.play() }
    }

    /// Автовоспроизведение только после первого взаимодействия.
    func userInteracted() {
        guard !interacted else { return }
        interacted = true
        if let t = desiredTrack { setMusic(t) }
        if let a = desiredAmbience { setAmbience(a) }
    }

    // MARK: SFX

    func play(_ sfx: SFX, semitones: Double = 0, gainDB: Double = 0) {
        guard interacted, !suspended, sfxVolume > 0.001 else { return }
        guard startEngineIfNeeded(), let buf = buffers[sfx] else { return }
        let now = CACurrentMediaTime()
        var index = voices.firstIndex { $0.busyUntil <= now }
        if index == nil {
            // Переполнение: оборвать самый старый голос с наименьшим приоритетом ≤ нового, кроме защищённых.
            let candidates = voices.enumerated().filter { v in
                guard let s = v.element.sfx else { return true }
                return !s.protected && s.priority <= sfx.priority
            }
            index = candidates.min { a, b in
                let pa = a.element.sfx?.priority.rawValue ?? -1, pb = b.element.sfx?.priority.rawValue ?? -1
                return pa != pb ? pa < pb : a.element.startedAt < b.element.startedAt
            }?.offset
        }
        guard let i = index else { return }
        let voice = voices[i]
        voice.player.stop()
        voice.varispeed.rate = Float(pow(2.0, semitones / 12.0))
        voice.player.volume = Float(pow(10.0, gainDB / 20.0))
        voice.player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        voice.player.play()
        let duration = Double(buf.frameLength) / buf.format.sampleRate / Double(voice.varispeed.rate)
        voices[i].sfx = sfx
        voices[i].startedAt = now
        voices[i].busyUntil = now + duration
    }

    func stopAllSFX() {
        for i in voices.indices {
            voices[i].player.stop()
            voices[i].busyUntil = 0
            voices[i].sfx = nil
        }
    }

    // MARK: Music / ambience

    private func loopPlayer(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") ??
                Bundle.main.url(forResource: name, withExtension: "m4a"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.numberOfLoops = -1
        p.prepareToPlay()
        return p
    }

    private var otherAudioPlaying: Bool {
        AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
    }

    /// Crossfade 600 ms между menu и gameplay; одна музыкальная петля одновременно.
    func setMusic(_ track: MusicTrack?) {
        desiredTrack = track
        guard interacted, !suspended else { return }
        guard track != currentTrack || musicPlayer?.isPlaying != true else { return }
        let old = musicPlayer
        old?.setVolume(0, fadeDuration: 0.6)
        if let old {
            fadingOutMusic = old
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self, weak old] in
                old?.stop()
                if self?.fadingOutMusic === old { self?.fadingOutMusic = nil }
            }
        }
        currentTrack = track
        guard let track, !otherAudioPlaying, musicVolume > 0.001, let p = loopPlayer(track.rawValue) else {
            musicPlayer = nil
            return
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        p.volume = 0
        p.play()
        p.setVolume(Float(musicVolume * headroom * duckFactor), fadeDuration: 0.6)
        musicPlayer = p
    }

    /// Не включать оба ambience одновременно.
    func setAmbience(_ a: AmbienceTrack?) {
        desiredAmbience = a
        guard interacted, !suspended else { return }
        guard a != currentAmbience || ambiencePlayer?.isPlaying != true else { return }
        ambiencePlayer?.setVolume(0, fadeDuration: 0.4)
        let old = ambiencePlayer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { old?.stop() }
        currentAmbience = a
        guard let a, ambienceVolume > 0.001, let p = loopPlayer(a.rawValue) else { ambiencePlayer = nil; return }
        p.volume = 0
        p.play()
        p.setVolume(Float(ambienceVolume * headroom), fadeDuration: 0.8)
        ambiencePlayer = p
    }

    private var reelLoop: AVAudioPlayer?

    /// S37: петля барабанов управляется отдельно, музыку Daily не перезапускает.
    func startReelLoop() {
        guard interacted, !suspended, sfxVolume > 0.001 else { return }
        if reelLoop == nil { reelLoop = loopPlayer("vc_reel_spin_loop") }
        reelLoop?.volume = Float(sfxVolume * headroom * 0.8)
        reelLoop?.currentTime = 0
        reelLoop?.play()
    }

    func stopReelLoop() {
        reelLoop?.setVolume(0, fadeDuration: 0.08)
        let p = reelLoop
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { p?.stop() }
    }

    /// Duck −6 dB: attack 80 ms, release 450 ms.
    func duck(for seconds: Double) {
        duckFactor = 0.5
        musicPlayer?.setVolume(Float(musicVolume * headroom * duckFactor), fadeDuration: 0.08)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            self.duckFactor = 1.0
            self.musicPlayer?.setVolume(Float(self.musicVolume * self.headroom), fadeDuration: 0.45)
        }
    }

    // MARK: Lifecycle

    /// Background/interruption: остановить петли и отложенные события; Resume не воспроизводит накопленное.
    func suspend() {
        suspended = true
        stopAllSFX()
        reelLoop?.stop()
        musicPlayer?.pause()
        ambiencePlayer?.pause()
        engine.pause()
    }

    func resume() {
        suspended = false
        guard interacted else { return }
        if let t = desiredTrack {
            if musicPlayer != nil && currentTrack == t && !otherAudioPlaying && musicVolume > 0.001 { musicPlayer?.play() } else { setMusic(t) }
        }
        if let a = desiredAmbience {
            if ambiencePlayer != nil && currentAmbience == a { ambiencePlayer?.play() } else { setAmbience(a) }
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began { suspend() }
    }
}
