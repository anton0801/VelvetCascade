// PerfMonitor.swift — DEBUG-замер кадрового времени и памяти (`-VCPerf <seconds>`): пишет Documents/perf.json.
// Результат — замер на симуляторе, а не на физическом устройстве.
#if DEBUG
import Foundation
import QuartzCore
import UIKit

final class PerfMonitor: NSObject {
    static let shared = PerfMonitor()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var intervals: [Double] = []
    private var peakFootprint: UInt64 = 0
    private var label = ""

    static func startIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-VCPerf"), i + 1 < args.count, let secs = Double(args[i + 1]) else { return }
        let fx = args.firstIndex(of: "-VCFixture").map { args[$0 + 1] } ?? "none"
        shared.start(seconds: secs, label: fx)
    }

    private func start(seconds: Double, label: String) {
        self.label = label
        link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.finish() }
    }

    @objc private func tick(_ l: CADisplayLink) {
        if last > 0 { intervals.append((l.timestamp - last) * 1000) }
        last = l.timestamp
        if intervals.count % 30 == 0 { peakFootprint = max(peakFootprint, PerfMonitor.footprint()) }
    }

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private func finish() {
        link?.invalidate()
        let sorted = intervals.sorted()
        func pct(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        let avg = intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count)
        let result: [String: Any] = [
            "fixture": label,
            "environment": "iOS Simulator \(UIDevice.current.systemVersion) (\(UIDevice.current.model)), not a physical device",
            "frames": intervals.count,
            "avgFrameMs": (avg * 100).rounded() / 100,
            "p95FrameMs": (pct(0.95) * 100).rounded() / 100,
            "maxFrameMs": ((sorted.last ?? 0) * 100).rounded() / 100,
            "hitchesOver25ms": intervals.filter { $0 > 25 }.count,
            "maxFrameRateHz": UIScreen.main.maximumFramesPerSecond,
            "peakPhysFootprintMB": Double(max(peakFootprint, PerfMonitor.footprint())) / 1_048_576,
        ]
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("perf-\(label).json")
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url) }
    }
}
#endif
