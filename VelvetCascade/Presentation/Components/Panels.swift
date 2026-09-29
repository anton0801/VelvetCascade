// Panels.swift — UI04 TheatrePanel, UI16 ModalScrim, UI19 SettingsRow, UI20 MessageState, общие заголовки.

import SwiftUI

/// Завиток 18 pt у верхних углов панели (векторный).
struct Flourish: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + r.height * 0.3),
                   control2: CGPoint(x: r.minX + r.width * 0.4, y: r.minY))
        p.move(to: CGPoint(x: r.minX + r.width * 0.25, y: r.maxY * 0.9))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.midY), control: CGPoint(x: r.minX + r.width * 0.3, y: r.midY))
        return p
    }
}

/// UI04: radius 20, padding 20, #351B36 с верхним градиентом #462443, gold-line 0.8 pt opacity 0.65,
/// два завитка по 18 pt у верхних углов, тень y6 blur18 opacity 0.2.
struct TheatrePanel<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.panelTop, Palette.panel], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .stroke(Palette.antiqueGold.opacity(0.65), lineWidth: 0.8)
            )
            .overlay(alignment: .topLeading) {
                Flourish().stroke(Palette.antiqueGold.opacity(0.8), lineWidth: 1)
                    .frame(width: 18, height: 18).offset(x: 9, y: 9).accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                Flourish().stroke(Palette.antiqueGold.opacity(0.8), lineWidth: 1)
                    .frame(width: 18, height: 18).scaleEffect(x: -1, y: 1).offset(x: -9, y: 9).accessibilityHidden(true)
            }
            .shadow(color: Color.black.opacity(0.2), radius: 9, x: 0, y: 6)
    }
}

/// UI16: чёрно-сливовый scrim 0.62, sheet с отступом 20, max-width 430, длинное содержимое скроллится.
/// Tap снаружи закрывает только информационные sheets.
struct ModalScrim<Content: View>: View {
    var dismissOnTapOutside: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Palette.scrim.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { dismissOnTapOutside?() }
                .accessibilityHidden(dismissOnTapOutside == nil)
                .accessibilityLabel("Close")
                .accessibilityAddTraits(.isButton)
            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    content
                        .frame(maxWidth: 430)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height)
                }
            }
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }
}

/// Верхняя строка экрана: Back/заголовок/трейлинг.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                IconButton(glyph: .back, label: "Back", action: onBack)
            } else {
                Color.clear.frame(width: Metrics.touch, height: Metrics.touch)
            }
            Spacer(minLength: 0)
            Text(title)
                .vcFont(.title2)
                .foregroundColor(Palette.warmIvory)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing.frame(minWidth: Metrics.touch, minHeight: Metrics.touch)
        }
        .padding(.horizontal, Metrics.side - 4)
        .frame(minHeight: 56)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, onBack: (() -> Void)?) {
        self.title = title
        self.onBack = onBack
        self.trailing = EmptyView()
    }
}

/// UI19: min-height 56, icon 20, title 17, value 15, separator 0.5 #5A3B58.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var value: String?
    var icon: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(Palette.spotlightGold)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
                Text(title).vcFont(.body).foregroundColor(Palette.warmIvory)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let value {
                    Text(value).vcFont(.secondary).foregroundColor(Palette.mutedRose)
                }
                accessory
            }
            .frame(minHeight: 56)
            Rectangle().fill(Palette.separator).frame(height: 0.5)
        }
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(title: String, value: String? = nil, icon: String? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
        self.accessory = EmptyView()
    }
}

/// Предупреждающий векторный значок 32 pt.
struct WarningGlyph: View {
    var color: Color = Palette.error
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            var tri = Path()
            tri.move(to: CGPoint(x: s * 0.5, y: s * 0.08))
            tri.addLine(to: CGPoint(x: s * 0.95, y: s * 0.88))
            tri.addLine(to: CGPoint(x: s * 0.05, y: s * 0.88))
            tri.closeSubpath()
            ctx.stroke(tri, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
            var bar = Path()
            bar.move(to: CGPoint(x: s * 0.5, y: s * 0.36))
            bar.addLine(to: CGPoint(x: s * 0.5, y: s * 0.6))
            ctx.stroke(bar, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: s * 0.47, y: s * 0.68, width: s * 0.06, height: s * 0.06)), with: .color(color))
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}

/// UI20: Warning/Info icon 32, title 22 serif, body 17 и 1–2 реальных CTA.
struct MessageState<Actions: View>: View {
    enum Kind { case warning, info }
    let kind: Kind
    let title: String
    let message: String
    var detail: String?
    var diagnosticID: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        TheatrePanel {
            VStack(spacing: 14) {
                if kind == .warning { WarningGlyph() } else { VectorGlyph(kind: .info, color: Palette.spotlightGold).frame(width: 32, height: 32) }
                Text(title).vcFont(.title2).foregroundColor(Palette.warmIvory).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message).vcFont(.body).foregroundColor(Palette.warmIvory).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).vcFont(.secondary).foregroundColor(Palette.mutedRose).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let diagnosticID {
                    Text("Reference \(diagnosticID)").vcFont(.caption).foregroundColor(Palette.mutedRose.opacity(0.8))
                }
                VStack(spacing: 12) { actions }.padding(.top, 4)
            }
        }
    }
}

/// Inline «Saving…» без фальшивого процента, с объявлением VoiceOver.
struct SavingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().tint(Palette.spotlightGold)
            Text("Saving…").vcFont(.secondary).foregroundColor(Palette.mutedRose)
        }
        .accessibilityElement(children: .combine)
        .onAppear { UIAccessibility.post(notification: .announcement, argument: "Saving") }
    }
}

/// Спокойный фон экранов без театра (Settings, Handbook).
struct CalmBackground: View {
    var body: some View {
        LinearGradient(colors: [Palette.deepVelvet, Palette.plumStage.opacity(0.6), Palette.deepVelvet],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
