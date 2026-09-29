// Theme.swift — палитра, типографика и метрики Velvet Cascade (из спецификации «Color palette»).

import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Palette {
    static let deepVelvet = Color(hex: 0x160C1D)      // корневой фон
    static let plumStage = Color(hex: 0x27142E)       // спокойный фон сцены
    static let panel = Color(hex: 0x351B36)           // панели, sheets
    static let panelTop = Color(hex: 0x462443)        // верхний градиент TheatrePanel
    static let rubyCurtain = Color(hex: 0xB52643)     // шторы, вторичная кнопка
    static let brightCrimson = Color(hex: 0xE04459)   // локальный акцент
    static let antiqueGold = Color(hex: 0xAF783B)     // кромки, тонкие рамки
    static let spotlightGold = Color(hex: 0xFFD26E)   // Primary CTA, полный Stage Turn
    static let warmIvory = Color(hex: 0xFFF3DC)       // основной текст
    static let mutedRose = Color(hex: 0xCDB5CB)       // вторичный текст
    static let ink = Color(hex: 0x2D1930)             // текст золотой кнопки
    static let sapphire = Color(hex: 0x369FEE)
    static let emerald = Color(hex: 0x38BA8A)
    static let amethyst = Color(hex: 0xA36BE8)
    static let success = Color(hex: 0x70D2A6)
    static let error = Color(hex: 0xF07D8C)

    // Производные цвета компонентов (UI01–UI20).
    static let goldTop = Color(hex: 0xFFE4A0)
    static let goldBottom = Color(hex: 0xC88D43)
    static let goldDisabled = Color(hex: 0x736149)
    static let shadow = Color(hex: 0x0D0614)
    static let velvetTop = Color(hex: 0x6E233B)
    static let destructive = Color(hex: 0x622334)
    static let cellFill = Color(hex: 0x302039)
    static let cellEdge = Color(hex: 0x58405C)
    static let boardFloor = Color(hex: 0x211426)
    static let gaugeEmpty = Color(hex: 0x4A344A)
    static let nodeLine = Color(hex: 0x78405A)
    static let starEmpty = Color(hex: 0x8A647C)
    static let separator = Color(hex: 0x5A3B58)
    static let scrim = Color(hex: 0x0A0410)
}

/// Типографика: заголовки system serif semibold 28–32, body 17, secondary 15, минимум 13, HUD 24 monospaced.
/// Все размеры масштабируются Dynamic Type через @ScaledMetric, крупный текст не заменяется мелким кеглем.
struct VCFont: ViewModifier {
    enum Style {
        case display, title, title2, headline, body, secondary, caption, hud, hudSmall, button
    }

    let style: Style
    @ScaledMetric private var size: CGFloat

    init(_ style: Style) {
        self.style = style
        let base: CGFloat
        let rel: Font.TextStyle
        switch style {
        case .display: base = 32; rel = .largeTitle
        case .title: base = 28; rel = .title
        case .title2: base = 22; rel = .title2
        case .headline: base = 17; rel = .headline
        case .body: base = 17; rel = .body
        case .secondary: base = 15; rel = .subheadline
        case .caption: base = 13; rel = .footnote
        case .hud: base = 24; rel = .title2
        case .hudSmall: base = 17; rel = .body
        case .button: base = 17; rel = .headline
        }
        _size = ScaledMetric(wrappedValue: base, relativeTo: rel)
    }

    func body(content: Content) -> some View {
        switch style {
        case .display, .title, .title2:
            content.font(.system(size: size, weight: .semibold, design: .serif))
        case .headline, .button:
            content.font(.system(size: size, weight: .semibold))
        case .body:
            content.font(.system(size: size))
        case .secondary:
            content.font(.system(size: size))
        case .caption:
            content.font(.system(size: size, weight: .medium))
        case .hud, .hudSmall:
            content.font(.system(size: size, weight: .semibold, design: .monospaced))
        }
    }
}

extension View {
    func vcFont(_ style: VCFont.Style) -> some View { modifier(VCFont(style)) }
}

enum Metrics {
    static let side: CGFloat = 20
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let cardRadius: CGFloat = 20
    static let ctaRadius: CGFloat = 16
    static let ctaHeight: CGFloat = 56
    static let touch: CGFloat = 44
    static let maxContentWidth: CGFloat = 520
}
