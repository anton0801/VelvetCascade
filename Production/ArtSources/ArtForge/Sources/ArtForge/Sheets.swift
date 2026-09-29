// Sheets.swift — style-reference / readability sheets used during iteration.
import Foundation
import CoreGraphics

enum Sheets {
    static func renderAsset(_ id: String) -> CGImage? {
        guard let spec = catalog.first(where: { $0.id == id }) else { return nil }
        let c = Canvas(width: CGFloat(spec.width), height: CGFloat(spec.height), scale: spec.renderScale, opaque: spec.opaque)
        if spec.opaque { c.fill(rectPath(c.bounds), Pal.deepVelvet) }
        spec.draw(c)
        return c.makeImage()
    }

    /// Lays out the given IDs at several display sizes on Deep Velvet and on a light cream reel colour.
    static func render(_ name: String, to dir: URL) {
        let ids: [String]
        switch name {
        case "gems": ids = ["VC07", "VC08", "VC09", "VC10", "VC11"]
        case "items": ids = ["VC12", "VC13", "VC14", "VC15", "VC16", "VC17", "VC18", "VC19", "VC20", "VC21", "VC22"]
        case "ui": ids = ["VC38", "VC40", "VC37"]
        default: ids = name.split(separator: ",").map { String($0) }
        }
        var imgs: [CGImage] = []
        let lock = NSLock()
        var tmp = [CGImage?](repeating: nil, count: ids.count)
        DispatchQueue.concurrentPerform(iterations: ids.count) { i in
            let im = renderAsset(ids[i]); lock.lock(); tmp[i] = im; lock.unlock()
        }
        imgs = tmp.compactMap { $0 }
        let big: CGFloat = 300, sizes: [CGFloat] = [160, 80, 48]
        let colW: CGFloat = big + 20
        let W = colW * CGFloat(imgs.count) + 20
        let H: CGFloat = 20 + big * 1.0 + 20 + sizes.reduce(0, +) + 60 + 20 + 80 + 20 + 80 + 20
        let c = Canvas(width: W, height: H, scale: 1, opaque: true)
        c.fill(rectPath(c.bounds), Pal.deepVelvet)
        // stripes: plum board and cream reel
        for (i, img) in imgs.enumerated() {
            let x0 = 20 + CGFloat(i) * colW
            let ar = CGFloat(img.width) / CGFloat(img.height)
            var y: CGFloat = 20
            c.drawImage(img, in: CGRect(x: x0, y: y, width: big * min(1, ar), height: big / max(1, ar)))
            y += big + 20
            for s in sizes {
                let small = resample(img, width: Int(s * min(1, ar)), height: Int(s / max(1, ar)), opaque: false)
                c.drawImage(small, in: CGRect(x: x0, y: y, width: s * min(1, ar), height: s / max(1, ar)))
                y += s + 20
            }
            // on panel colour cell
            c.fill(rrectPath(CGRect(x: x0 - 4, y: y - 4, width: 88, height: 88), 12), Pal.panel)
            let small = resample(img, width: Int(80 * min(1, ar)), height: Int(80 / max(1, ar)), opaque: false)
            c.drawImage(small, in: CGRect(x: x0, y: y, width: 80 * min(1, ar), height: 80 / max(1, ar)))
            // on cream reel
            c.fill(rrectPath(CGRect(x: x0 + 100 - 4, y: y - 4, width: 88, height: 88), 12), Pal.ivory)
            c.drawImage(small, in: CGRect(x: x0 + 100, y: y, width: 80 * min(1, ar), height: 80 / max(1, ar)))
        }
        writePNG(c.makeImage(), to: dir.appendingPathComponent("sheet_\(name.replacingOccurrences(of: ",", with: "_")).png"))
        print("sheet written")
    }
}
