import SwiftUI

/// The "dark cockpit" design system: exact token palette + typography from the
/// design source (design/TrainOrRest.dc.html). Colors are dynamic so they
/// adapt to light/dark automatically; the app defaults to the dark cockpit.
enum Theme {
    // MARK: - Palette (dark / light token pairs from the design)

    static let bg = dynamic(dark: 0x08080D, light: 0xEEEFF3)
    static let card = dynamic(dark: 0x14141D, light: 0xFFFFFF)
    static let card2 = dynamic(dark: 0x1B1B26, light: 0xF6F6FA)
    static let text = dynamic(dark: 0xF5F5FA, light: 0x0C0C14)

    static let line = dynamicA(dark: (0xFFFFFF, 0.07), light: (0x0A0A14, 0.07))
    static let border = dynamicA(dark: (0xFFFFFF, 0.08), light: (0x0A0A14, 0.09))
    static let dim = dynamicA(dark: (0xF5F5FA, 0.62), light: (0x0C0C14, 0.62))
    // Raised from the design's 0.32 so captions clear WCAG contrast on the dark canvas.
    static let faint = dynamicA(dark: (0xF5F5FA, 0.46), light: (0x0C0C14, 0.46))
    static let chip = dynamicA(dark: (0xFFFFFF, 0.06), light: (0x0A0A14, 0.05))

    static let accent = dynamic(dark: 0x9B7BF0, light: 0x7C3AED)
    static let accent2 = dynamic(dark: 0x7C5CE0, light: 0x6D28D9)
    static let accentSoft = dynamicA(dark: (0x9B7BF0, 0.16), light: (0x7C3AED, 0.10))

    static let good = dynamic(dark: 0x35D9A0, light: 0x0F9D6E)
    static let warn = dynamic(dark: 0xFBBF24, light: 0xD97706)
    static let bad = dynamic(dark: 0xFB7185, light: 0xE11D48)

    /// Soft tint of a semantic color for badge backgrounds.
    static func soft(_ color: Color, _ opacity: Double = 0.14) -> Color {
        color.opacity(opacity)
    }

    // MARK: - Dynamic color plumbing

    private static func dynamic(dark: Int, light: Int) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    private static func dynamicA(dark: (Int, Double), light: (Int, Double)) -> Color {
        Color(uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(hex: dark.0, alpha: dark.1)
                : UIColor(hex: light.0, alpha: light.1)
        })
    }
}

// MARK: - Typography
//
// The design uses Barlow / Barlow Semi Condensed / JetBrains Mono. Rather than
// bundle font binaries, we map to the system font with matching width/weight:
// condensed for display numbers and headers, monospaced for the label chips.
// Swap in the real families later by adding TTFs + UIAppFonts.

extension Font {
    /// Big condensed display numerals (readiness score, metric values).
    static func torNumber(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Condensed headings and titles.
    static func torHeading(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Uppercase tracked labels / eyebrows.
    static func torLabel(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Monospaced technical captions.
    static func torMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Card container

/// The standard card surface: neutral fill, hairline border, rounded.
struct TorCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

/// An uppercase tracked section eyebrow ("TODAY'S READINESS").
struct TorEyebrow: View {
    let text: String
    var color: Color = Theme.faint
    init(_ text: String, color: Color = Theme.faint) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text.uppercased())
            .font(.torLabel(11))
            .tracking(1.8)
            .foregroundStyle(color)
    }
}

private extension UIColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
