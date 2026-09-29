// Main.swift — ArtForge CLI. Renders the Velvet Cascade art catalog (VC01–VC40).
//
//   swift run -c release ArtForge                 # render everything
//   swift run -c release ArtForge VC07 VC23       # render selected IDs
//   swift run -c release ArtForge --sheet gems    # style-reference sheet only
//   swift run -c release ArtForge --parallel      # faster, but not bit-reproducible (drafts only)
//
// Output:
//   Production/ArtSources/renders/<file>   native-resolution source render (2× for most items)
//   VelvetCascade/Resources/Art/<file>     exact catalog size (uniform downscale only)
//   Production/ArtSources/renders/meta.json  measured/derived geometry (faceRect, design window rects…)
import Foundation
import CoreGraphics

struct AssetSpec {
    let id: String
    let file: String
    let width: Int
    let height: Int
    let opaque: Bool
    let renderScale: CGFloat
    let draw: (Canvas) -> Void
}

let catalog: [AssetSpec] = [
    AssetSpec(id: "VC01", file: "vc_onboarding_welcome.png", width: 1290, height: 2796, opaque: true, renderScale: 1) { Backgrounds.onboardingWelcome($0) },
    AssetSpec(id: "VC02", file: "vc_onboarding_match.png", width: 1290, height: 2796, opaque: true, renderScale: 1) { Backgrounds.onboardingMatch($0) },
    AssetSpec(id: "VC03", file: "vc_onboarding_rotate.png", width: 1290, height: 2796, opaque: true, renderScale: 1) { Backgrounds.onboardingRotate($0) },
    AssetSpec(id: "VC04", file: "vc_vell_idle.png", width: 1024, height: 1536, opaque: false, renderScale: 2) { VellArt.idle($0) },
    AssetSpec(id: "VC05", file: "vc_vell_celebrate.png", width: 1024, height: 1536, opaque: false, renderScale: 2) { VellArt.celebrate($0) },
    AssetSpec(id: "VC06", file: "vc_vell_encourage.png", width: 1024, height: 1536, opaque: false, renderScale: 2) { VellArt.encourage($0) },
    AssetSpec(id: "VC07", file: "vc_gem_heart.png", width: 512, height: 512, opaque: false, renderScale: 2) { Gems.heart($0) },
    AssetSpec(id: "VC08", file: "vc_gem_diamond.png", width: 512, height: 512, opaque: false, renderScale: 2) { Gems.diamond($0) },
    AssetSpec(id: "VC09", file: "vc_gem_clover.png", width: 512, height: 512, opaque: false, renderScale: 2) { Gems.clover($0) },
    AssetSpec(id: "VC10", file: "vc_gem_bell.png", width: 512, height: 512, opaque: false, renderScale: 2) { Gems.bell($0) },
    AssetSpec(id: "VC11", file: "vc_gem_star.png", width: 512, height: 512, opaque: false, renderScale: 2) { Gems.star($0) },
    AssetSpec(id: "VC12", file: "vc_special_burst.png", width: 512, height: 512, opaque: false, renderScale: 2) { c in scaled(c, 0.9) { Items.burst(c) } },
    AssetSpec(id: "VC13", file: "vc_special_prism.png", width: 512, height: 512, opaque: false, renderScale: 2) { Items.prism($0) },
    AssetSpec(id: "VC14", file: "vc_stage_key.png", width: 512, height: 512, opaque: false, renderScale: 2) { Items.key($0) },
    AssetSpec(id: "VC15", file: "vc_exit_port.png", width: 512, height: 512, opaque: false, renderScale: 2) { c in scaled(c, 0.88) { Items.exitPort(c) } },
    AssetSpec(id: "VC16", file: "vc_crate.png", width: 512, height: 512, opaque: false, renderScale: 2) { Items.crate($0) },
    AssetSpec(id: "VC17", file: "vc_ice_overlay.png", width: 512, height: 512, opaque: false, renderScale: 2) { Items.ice($0) },
    AssetSpec(id: "VC18", file: "vc_chain_overlay.png", width: 512, height: 512, opaque: false, renderScale: 2) { Items.chains($0) },
    AssetSpec(id: "VC19", file: "vc_shutter_closed.png", width: 512, height: 512, opaque: false, renderScale: 2) { Items.shutter($0) },
    AssetSpec(id: "VC20", file: "vc_switch.png", width: 512, height: 512, opaque: false, renderScale: 2) { Items.switchPedal($0) },
    AssetSpec(id: "VC21", file: "vc_baffle.png", width: 512, height: 512, opaque: false, renderScale: 2) { Items.baffle($0) },
    AssetSpec(id: "VC22", file: "vc_velvet_plate.png", width: 512, height: 512, opaque: false, renderScale: 2) { Items.velvetPlate($0) },
    AssetSpec(id: "VC23", file: "vc_daily_machine.png", width: 1536, height: 1536, opaque: false, renderScale: 1) { Machine.draw($0) },
    AssetSpec(id: "VC24", file: "vc_curtain_left.png", width: 768, height: 2048, opaque: false, renderScale: 1) { Items.curtain($0, right: false) },
    AssetSpec(id: "VC25", file: "vc_curtain_right.png", width: 768, height: 2048, opaque: false, renderScale: 1) { Items.curtain($0, right: true) },
    AssetSpec(id: "VC26", file: "vc_spotlight_beam.png", width: 1024, height: 1024, opaque: false, renderScale: 1) { Items.spotlightBeam($0) },
    AssetSpec(id: "VC27", file: "vc_world_01.png", width: 1290, height: 2796, opaque: true, renderScale: 1) { Backgrounds.world(1, $0) },
    AssetSpec(id: "VC28", file: "vc_world_02.png", width: 1290, height: 2796, opaque: true, renderScale: 1) { Backgrounds.world(2, $0) },
    AssetSpec(id: "VC29", file: "vc_world_03.png", width: 1290, height: 2796, opaque: true, renderScale: 1) { Backgrounds.world(3, $0) },
    AssetSpec(id: "VC30", file: "vc_world_04.png", width: 1290, height: 2796, opaque: true, renderScale: 1) { Backgrounds.world(4, $0) },
    AssetSpec(id: "VC31", file: "vc_world_05.png", width: 1290, height: 2796, opaque: true, renderScale: 1) { Backgrounds.world(5, $0) },
    AssetSpec(id: "VC32", file: "vc_world_06.png", width: 1290, height: 2796, opaque: true, renderScale: 1) { Backgrounds.world(6, $0) },
    AssetSpec(id: "VC33", file: "vc_world_07.png", width: 1290, height: 2796, opaque: true, renderScale: 1) { Backgrounds.world(7, $0) },
    AssetSpec(id: "VC34", file: "vc_world_08.png", width: 1290, height: 2796, opaque: true, renderScale: 1) { Backgrounds.world(8, $0) },
    AssetSpec(id: "VC35", file: "vc_world_09.png", width: 1290, height: 2796, opaque: true, renderScale: 1) { Backgrounds.world(9, $0) },
    AssetSpec(id: "VC36", file: "vc_app_icon.png", width: 1024, height: 1024, opaque: true, renderScale: 1) { Items.appIcon($0) },
    AssetSpec(id: "VC37", file: "vc_vell_portrait.png", width: 768, height: 768, opaque: false, renderScale: 2) { VellArt.portrait($0) },
    AssetSpec(id: "VC38", file: "vc_hint_ticket.png", width: 512, height: 512, opaque: false, renderScale: 2) { Items.ticket($0) },
    AssetSpec(id: "VC39", file: "vc_result_crest.png", width: 1024, height: 512, opaque: false, renderScale: 2) { c in scaled(c, 0.9) { Items.crest(c) } },
    AssetSpec(id: "VC40", file: "vc_turn_crown.png", width: 512, height: 512, opaque: false, renderScale: 2) { Items.turnCrown($0) },
]

/// Uniformly scales a drawing about the canvas centre (used to tune transparent padding).
func scaled(_ c: Canvas, _ k: CGFloat, _ body: () -> Void) {
    let cx = c.width / 2, cy = c.height / 2
    c.transform(CGAffineTransform(translationX: cx, y: cy).scaledBy(x: k, y: k).translatedBy(x: -cx, y: -cy)) { body() }
}

// MARK: - Metadata sidecar

final class MetaStore: @unchecked Sendable {
    static let shared = MetaStore()
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    func set(_ id: String, _ key: String, _ value: Any) {
        lock.lock(); defer { lock.unlock() }
        var d = values[id] as? [String: Any] ?? [:]
        d[key] = value; values[id] = d
    }
    func merged(into url: URL) {
        var existing: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { existing = obj }
        lock.lock(); for (k, v) in values { existing[k] = v }; lock.unlock()
        let data = try! JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: url)
    }
}
func normRect(_ r: CGRect, _ w: CGFloat, _ h: CGFloat) -> [String: Double] {
    ["x": Double(r.minX / w), "y": Double(r.minY / h), "w": Double(r.width / w), "h": Double(r.height / h)]
}

// MARK: - CLI

@main
struct ArtForgeCLI {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() } // Sources/ArtForge/Main.swift → project root
        if let i = args.firstIndex(of: "--root"), i + 1 < args.count {
            root = URL(fileURLWithPath: args[i + 1]); args.removeSubrange(i...(i + 1))
        }
        // Jobs run one after another by default: concurrent CoreGraphics shadow/transparency-layer rendering
        // was measured to be non-deterministic between runs. `--parallel` trades that for speed (drafts only).
        var parallel = false
        if let i = args.firstIndex(of: "--parallel") { parallel = true; args.remove(at: i) }
        var sheet: String? = nil
        if let i = args.firstIndex(of: "--sheet"), i + 1 < args.count {
            sheet = args[i + 1]; args.removeSubrange(i...(i + 1))
        }
        let rendersDir = root.appendingPathComponent("Production/ArtSources/renders")
        let artDir = root.appendingPathComponent("VelvetCascade/Resources/Art")
        try? FileManager.default.createDirectory(at: rendersDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: artDir, withIntermediateDirectories: true)

        if let sheet {
            Sheets.render(sheet, to: rendersDir)
            return
        }

        let wanted = Set(args.map { $0.uppercased() })
        let jobs = catalog.filter { wanted.isEmpty || wanted.contains($0.id) }
        if jobs.isEmpty { print("No matching IDs. Known: \(catalog.map { $0.id }.joined(separator: " "))"); exit(1) }
        let t0 = Date()
        let printLock = NSLock()
        let renderJob: (Int) -> Void = { idx in
            let spec = jobs[idx]
            let t = Date()
            autoreleasepool {
                let canvas = Canvas(width: CGFloat(spec.width), height: CGFloat(spec.height), scale: spec.renderScale, opaque: spec.opaque)
                if spec.opaque {
                    canvas.fill(rectPath(canvas.bounds), Pal.deepVelvet)
                }
                spec.draw(canvas)
                let native = canvas.makeImage()
                writePNG(native, to: rendersDir.appendingPathComponent(spec.file))
                let final = (native.width == spec.width && native.height == spec.height)
                    ? native : resample(native, width: spec.width, height: spec.height, opaque: spec.opaque)
                writePNG(final, to: artDir.appendingPathComponent(spec.file))
            }
            printLock.lock()
            print(String(format: "%@  %@  %dx%d  %.2fs", spec.id, spec.file, spec.width, spec.height, Date().timeIntervalSince(t)))
            printLock.unlock()
        }
        if parallel {
            DispatchQueue.concurrentPerform(iterations: jobs.count, execute: renderJob)
        } else {
            for idx in jobs.indices { renderJob(idx) }
        }
        MetaStore.shared.merged(into: rendersDir.appendingPathComponent("meta.json"))
        print(String(format: "Rendered %d assets in %.1fs", jobs.count, Date().timeIntervalSince(t0)))
    }
}
