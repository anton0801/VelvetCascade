// CoreServices.swift — Clock abstraction, системный криптографический RNG для Daily, haptics, загрузчик изображений.

import Foundation
import ImageIO
import Security
import SwiftUI
import UIKit
import VelvetDomain

protocol Clock {
    func now() -> Date
}

struct SystemClock: Clock {
    func now() -> Date { Date() }
}

/// DEBUG: фиксированное время для детерминированных fixtures.
final class FixedClock: Clock {
    var date: Date
    init(_ date: Date) { self.date = date }
    func now() -> Date { date }
}

/// Равномерные bounded integers из SecRandomCopyBytes, отбрасывание без modulo bias.
/// Игровой PRNG уровня для бонуса не используется.
enum SecureRandom {
    static func uniform(below bound: UInt32) -> UInt32 {
        precondition(bound > 0)
        let limit = UInt32.max - (UInt32.max % bound)
        while true {
            var v: UInt32 = 0
            let status = withUnsafeMutableBytes(of: &v) { SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!) }
            if status != errSecSuccess {
                var g = SystemRandomNumberGenerator()
                return UInt32.random(in: 0..<bound, using: &g)
            }
            if v < limit { return v % bound }
        }
    }

    static func dailySymbols() -> [GemColor] {
        (0..<3).map { _ in GemColor(rawValue: Int(uniform(below: 5)))! }
    }
}

// MARK: - Haptics (отдельно от SFX)

final class HapticsService {
    var enabled = true
    private let selection = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notify = UINotificationFeedbackGenerator()

    func swap() { guard enabled else { return }; selection.selectionChanged() }
    func reelStop() { guard enabled else { return }; light.impactOccurred() }
    func turn() { guard enabled else { return }; medium.impactOccurred() }
    func success() { guard enabled else { return }; notify.notificationOccurred(.success) }
    func invalid() { guard enabled else { return }; notify.notificationOccurred(.warning) }
}

// MARK: - Images (декодировать по необходимости, thumbnails — средствами загрузчика)

final class ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSString, UIImage>()
    /// Полноэкранные фоны: текущий + максимум один переходный (LRU на 2 записи).
    private var large: [(key: String, image: UIImage)] = []
    private let largeThreshold = 1400

    init() {
        cache.totalCostLimit = 64 * 1024 * 1024
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.purge()
        }
    }

    /// Загружает PNG из бандла с даунсэмплингом до maxPixel по длинной стороне.
    func image(_ name: String, maxPixel: CGFloat) -> UIImage? {
        let bucket = Int((maxPixel / 64).rounded(.up)) * 64
        let key = "\(name)@\(bucket)" as NSString
        if bucket >= largeThreshold, let i = large.firstIndex(where: { $0.key == key as String }) {
            let hit = large.remove(at: i)
            large.append(hit)
            return hit.image
        }
        if let img = cache.object(forKey: key) { return img }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: bucket,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = UIImage(cgImage: cg)
        if bucket >= largeThreshold {
            large.append((key as String, img))
            if large.count > 2 { large.removeFirst(large.count - 2) }
        } else {
            cache.setObject(img, forKey: key, cost: cg.bytesPerRow * cg.height)
        }
        return img
    }

    func purge() {
        cache.removeAllObjects()
        if large.count > 1 { large.removeFirst(large.count - 1) }
    }
}

/// Растровый ассет из каталога VC01–VC40 в размере отображения.
struct ArtImage: View {
    let name: String
    var contentMode: ContentMode = .fit
    /// Максимальная сторона в pt (для выбора display-size текстуры).
    var maxPoints: CGFloat
    @Environment(\.displayScale) private var scale

    var body: some View {
        if let img = ImageLoader.shared.image(name, maxPixel: maxPoints * scale) {
            Image(uiImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: contentMode)
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }
}

/// Полноэкранный фон (aspectFill), декодируется только текущий.
struct BackgroundArt: View {
    let name: String
    var dim: Double = 0

    var body: some View {
        GeometryReader { geo in
            ArtImage(name: name, contentMode: .fill, maxPoints: max(geo.size.width, geo.size.height))
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(Color.black.opacity(dim))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

enum GemArt {
    static func name(_ c: GemColor) -> String {
        switch c {
        case .heart: return "vc_gem_heart"
        case .diamond: return "vc_gem_diamond"
        case .clover: return "vc_gem_clover"
        case .bell: return "vc_gem_bell"
        case .star: return "vc_gem_star"
        }
    }
}
