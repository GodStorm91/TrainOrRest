import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Use System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var subtitle: String {
        switch self {
        case .system: "Follows your device appearance."
        case .light: "Always uses the bright TrainOrRest interface."
        case .dark: "Always uses the low-glare TrainOrRest interface."
        }
    }

    var symbolName: String {
        switch self {
        case .system: "iphone"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Adaptive TrainOrRest design tokens. Dark keeps the original cockpit mood;
/// light mode uses pearl glass surfaces with strong typography and restrained
/// purple/green accents.
enum Theme {
    // MARK: - Palette (dark / light token pairs from the design)

    static let bg = dynamic(dark: 0x08080D, light: 0xF7F6F2)
    static let card = dynamicA(dark: (0x14141D, 1.0), light: (0xFFFFFF, 0.98))
    static let card2 = dynamicA(dark: (0x1B1B26, 1.0), light: (0xFFFFFF, 0.92))
    static let text = dynamic(dark: 0xF5F5FA, light: 0x11131A)

    static let line = dynamicA(dark: (0xFFFFFF, 0.07), light: (0x182033, 0.08))
    static let border = dynamicA(dark: (0xFFFFFF, 0.08), light: (0x182033, 0.16))
    static let dim = dynamicA(dark: (0xF5F5FA, 0.62), light: (0x11131A, 0.74))
    // Raised so captions clear WCAG contrast on both canvases.
    static let faint = dynamicA(dark: (0xF5F5FA, 0.50), light: (0x11131A, 0.62))
    static let chip = dynamicA(dark: (0xFFFFFF, 0.06), light: (0xFFFFFF, 0.82))

    /// Interactive primary: buttons, links, selected state, and focus.
    static let accent = dynamic(dark: 0x9B7BF0, light: 0x7C3AED)
    /// Interactive secondary: pressed, gradient, and paired action states.
    static let accent2 = dynamic(dark: 0x7C5CE0, light: 0x6D28D9)
    /// Interactive tint: soft selected, pressed, or focus backgrounds.
    static let accentSoft = dynamicA(dark: (0x9B7BF0, 0.16), light: (0x7C3AED, 0.10))

    static let good = dynamic(dark: 0x35D9A0, light: 0x0F9D6E)
    /// Uncertainty only: stale, disputed, or unconfirmed signals.
    static let warn = dynamic(dark: 0xFBBF24, light: 0xD97706)
    /// Error only: failed sync, denied permission, or rejected validation.
    static let bad = dynamic(dark: 0xFB7185, light: 0xE11D48)
    /// Data series only: charts and sparklines, with no good/bad judgment.
    static let data = dynamic(dark: 0x6BB8D6, light: 0x08758F)
    /// Verdict only: Train recommendation.
    static let verdictTrain = dynamic(dark: 0x4EDCC4, light: 0x087A6E)
    /// Verdict only: Go easy recommendation.
    static let verdictEasy = dynamic(dark: 0xE4C58A, light: 0x806021)
    /// Verdict only: Rest recommendation.
    static let verdictRest = dynamic(dark: 0x97AEDC, light: 0x496BA3)

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

extension UIColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Adaptive Liquid Glass surfaces

enum TorGlassTint {
    case graphite
    case subtle
}

private struct TorGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let tint: TorGlassTint

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape.fill(baseTint)
                    }
                    .overlay(alignment: .topLeading) {
                        shape
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.20), Color.white.opacity(0.055), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(tint == .graphite ? 0.11 : 0.075))
                            .frame(height: 1.2)
                            .padding(.horizontal, cornerRadius * 0.95)
                            .padding(.top, 1)
                    }
                    .shadow(color: glassShadow, radius: tint == .graphite ? 22 : 16, x: 0, y: tint == .graphite ? 12 : 8)
                    .shadow(color: Theme.accent.opacity(0.045), radius: 16, x: 0, y: 4)
            }
    }

    private var glassShadow: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(tint == .graphite ? 0.34 : 0.22)
                : UIColor(hex: 0x30405A, alpha: tint == .graphite ? 0.14 : 0.09)
        })
    }

    private var baseTint: Color {
        switch tint {
        case .graphite:
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: 0x151722, alpha: 0.58)
                    : UIColor(hex: 0xFFFFFF, alpha: 0.58)
            })
        case .subtle:
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: 0x191B25, alpha: 0.48)
                    : UIColor(hex: 0xFFFFFF, alpha: 0.46)
            })
        }
    }
}

extension View {
    func torGlass(cornerRadius: CGFloat = 22, tint: TorGlassTint = .graphite) -> some View {
        modifier(TorGlassSurface(cornerRadius: cornerRadius, tint: tint))
    }
}

struct LiquidGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 2) {
            content()
        }
        .padding(2)
        .torGlass(cornerRadius: 24, tint: .graphite)
    }
}

extension Image {
    func torTopControlIcon() -> some View {
        self
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

extension Color {
    init(hex: Int, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Appearance controls

struct AppAppearanceSelector: View {
    var compact = false
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    private var selection: AppAppearance {
        get { AppAppearance(rawValue: appearanceRaw) ?? .system }
        nonmutating set { appearanceRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            if !compact {
                HStack(spacing: 9) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        TorEyebrow("Appearance")
                        Text("Adaptive theme")
                            .font(.torHeading(18, .bold))
                            .foregroundStyle(Theme.text)
                    }
                }
            }

            HStack(spacing: 7) {
                ForEach(AppAppearance.allCases) { option in
                    appearanceButton(option)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Use System follows your device appearance.")
                Text("Choose Light or Dark anytime.")
            }
            .font(.caption)
            .foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func appearanceButton(_ option: AppAppearance) -> some View {
        let selected = selection == option
        return Button {
            withAnimation(.smooth(duration: 0.18)) {
                selection = option
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: option.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                Text(option.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(selected ? Color.white : Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 50 : 56)
            .background(
                selected ? Theme.accent : Theme.chip,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(selected ? Theme.accent.opacity(0.35) : Theme.border, lineWidth: 1)
            )
            .shadow(color: selected ? Theme.accent.opacity(0.20) : .clear, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityValue(selected ? "Selected" : option.subtitle)
    }
}
