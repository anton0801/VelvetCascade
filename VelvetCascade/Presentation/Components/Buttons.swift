// Buttons.swift — UI01 GoldButton, UI02 VelvetButton, UI03 IconButton (векторные glyphs).

import SwiftUI

/// UI01: 56 pt, padding 20, radius 16, заливка #FFE4A0→#FFD26E→#C88D43, кромка 1 pt #AF783B,
/// верхний блик 1 pt 0.45, тень #0D0614 0.32 y4 blur8. Pressed: scale 0.98, y1. Disabled: #736149.
struct GoldButtonStyle: ButtonStyle {
    var busy = false
    /// Галерея компонентов: принудительное состояние pressed.
    var forcePressed = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = (configuration.isPressed || forcePressed) && isEnabled
        return HStack(spacing: 8) {
            if busy {
                ProgressView().progressViewStyle(.circular).tint(Palette.ink)
            }
            configuration.label
                .vcFont(.button)
                .multilineTextAlignment(.center)
                .foregroundColor(isEnabled ? Palette.ink : Palette.warmIvory.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: Metrics.ctaHeight)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.ctaRadius, style: .continuous)
                    .fill(isEnabled
                          ? AnyShapeStyle(LinearGradient(colors: [Palette.goldTop, Palette.spotlightGold, Palette.goldBottom],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Palette.goldDisabled))
                RoundedRectangle(cornerRadius: Metrics.ctaRadius, style: .continuous)
                    .inset(by: 1)
                    .stroke(Color.white.opacity(isEnabled ? 0.45 : 0), lineWidth: 1)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                RoundedRectangle(cornerRadius: Metrics.ctaRadius, style: .continuous)
                    .stroke(Palette.antiqueGold, lineWidth: 1)
            }
        )
        .shadow(color: Palette.shadow.opacity(isEnabled ? 0.32 : 0), radius: 4, x: 0, y: 4)
        .scaleEffect(pressed ? 0.98 : 1)
        .offset(y: pressed ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .contentShape(Rectangle())
    }
}

/// UI02: 56 pt/radius 16; #6E233B→#B52643 с золотым контуром 1 pt, ivory label.
/// Pressed −12% яркости; disabled — приглушённая слива. Destructive — #622334 с текстом #FFF3DC.
struct VelvetButtonStyle: ButtonStyle {
    var destructive = false
    var compact = false
    var forcePressed = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = (configuration.isPressed || forcePressed) && isEnabled
        let fill: AnyShapeStyle
        if !isEnabled {
            fill = AnyShapeStyle(Palette.panel)
        } else if destructive {
            fill = AnyShapeStyle(Palette.destructive)
        } else {
            fill = AnyShapeStyle(LinearGradient(colors: [Palette.velvetTop, Palette.rubyCurtain], startPoint: .top, endPoint: .bottom))
        }
        return configuration.label
            .vcFont(.button)
            .multilineTextAlignment(.center)
            .foregroundColor(Palette.warmIvory.opacity(isEnabled ? 1 : 0.5))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: compact ? Metrics.touch : Metrics.ctaHeight)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Metrics.ctaRadius, style: .continuous).fill(fill)
                    RoundedRectangle(cornerRadius: Metrics.ctaRadius, style: .continuous)
                        .stroke(Palette.antiqueGold.opacity(isEnabled ? 1 : 0.4), lineWidth: 1)
                }
            )
            .brightness(pressed ? -0.12 : 0)
            .scaleEffect(pressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .contentShape(Rectangle())
    }
}

/// Текстовая кнопка ≥44 pt (Skip, Show a bigger match, How to Play).
struct TextLinkStyle: ButtonStyle {
    var color: Color = Palette.spotlightGold
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .vcFont(.headline)
            .foregroundColor(color.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(minHeight: Metrics.touch)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
    }
}

enum GlyphKind {
    case gear, back, pause, close, help, info
}

/// Ровные векторные strokes 2 pt — не растровые картинки.
struct VectorGlyph: View {
    let kind: GlyphKind
    var color: Color = Palette.warmIvory

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let o = CGPoint(x: (size.width - s) / 2, y: (size.height - s) / 2)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
            var path = Path()
            let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            switch kind {
            case .back:
                path.move(to: p(0.62, 0.18)); path.addLine(to: p(0.32, 0.5)); path.addLine(to: p(0.62, 0.82))
                ctx.stroke(path, with: .color(color), style: style)
            case .close:
                path.move(to: p(0.25, 0.25)); path.addLine(to: p(0.75, 0.75))
                path.move(to: p(0.75, 0.25)); path.addLine(to: p(0.25, 0.75))
                ctx.stroke(path, with: .color(color), style: style)
            case .pause:
                path.move(to: p(0.36, 0.22)); path.addLine(to: p(0.36, 0.78))
                path.move(to: p(0.64, 0.22)); path.addLine(to: p(0.64, 0.78))
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            case .gear:
                let c = p(0.5, 0.5)
                let teeth = 8
                var g = Path()
                for i in 0..<(teeth * 2) {
                    let a = Double(i) / Double(teeth * 2) * .pi * 2
                    let r = (i % 2 == 0 ? 0.40 : 0.31) * s
                    let a2 = a + .pi / Double(teeth * 2)
                    let r2 = (i % 2 == 0 ? 0.40 : 0.31) * s
                    let pt1 = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
                    let pt2 = CGPoint(x: c.x + CGFloat(cos(a2)) * r2, y: c.y + CGFloat(sin(a2)) * r2)
                    if i == 0 { g.move(to: pt1) } else { g.addLine(to: pt1) }
                    g.addLine(to: pt2)
                }
                g.closeSubpath()
                ctx.stroke(g, with: .color(color), style: style)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 0.12 * s, y: c.y - 0.12 * s, width: 0.24 * s, height: 0.24 * s)),
                           with: .color(color), style: style)
            case .help:
                ctx.stroke(Path(ellipseIn: CGRect(x: o.x + 0.12 * s, y: o.y + 0.12 * s, width: 0.76 * s, height: 0.76 * s)),
                           with: .color(color), style: style)
                path.move(to: p(0.38, 0.4))
                path.addQuadCurve(to: p(0.5, 0.28), control: p(0.38, 0.28))
                path.addQuadCurve(to: p(0.6, 0.42), control: p(0.62, 0.3))
                path.addQuadCurve(to: p(0.5, 0.58), control: p(0.5, 0.48))
                ctx.stroke(path, with: .color(color), style: style)
                ctx.fill(Path(ellipseIn: CGRect(x: o.x + 0.47 * s, y: o.y + 0.67 * s, width: 0.06 * s, height: 0.06 * s)), with: .color(color))
            case .info:
                ctx.stroke(Path(ellipseIn: CGRect(x: o.x + 0.12 * s, y: o.y + 0.12 * s, width: 0.76 * s, height: 0.76 * s)),
                           with: .color(color), style: style)
                path.move(to: p(0.5, 0.45)); path.addLine(to: p(0.5, 0.7))
                ctx.stroke(path, with: .color(color), style: style)
                ctx.fill(Path(ellipseIn: CGRect(x: o.x + 0.47 * s, y: o.y + 0.3 * s, width: 0.06 * s, height: 0.06 * s)), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// UI03: 44×44 pt минимум; круг #351B36, контур Antique Gold 0.8 pt, символ 20 pt ivory.
struct IconButton: View {
    let glyph: GlyphKind
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VectorGlyph(kind: glyph).frame(width: 20, height: 20)
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(label)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: Metrics.touch, height: Metrics.touch)
            .background(Circle().fill(configuration.isPressed ? Palette.panelTop : Palette.panel))
            .overlay(Circle().stroke(Palette.antiqueGold, lineWidth: 0.8))
            .contentShape(Circle())
    }
}

extension View {
    func goldButton(busy: Bool = false) -> some View { buttonStyle(GoldButtonStyle(busy: busy)) }
    func velvetButton(destructive: Bool = false, compact: Bool = false) -> some View {
        buttonStyle(VelvetButtonStyle(destructive: destructive, compact: compact))
    }
}
