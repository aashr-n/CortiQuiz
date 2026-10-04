import SwiftUI

// MARK: - Design Tokens

enum Theme {
    // MARK: Backgrounds
    static let bgPrimary = Color(red: 0.035, green: 0.035, blue: 0.035)
    static let bgSecondary = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let bgCard = Color.white.opacity(0.06)
    static let bgCardStroke = Color.white.opacity(0.09)
    static let bgInput = Color.white.opacity(0.10)

    // MARK: Accent — dusty brain-pink
    static let accent = Color(red: 0.83, green: 0.51, blue: 0.60)       // #D4829A
    static let accentBright = Color(red: 0.90, green: 0.55, blue: 0.65) // brighter for highlights
    static let accentDim = Color(red: 0.55, green: 0.33, blue: 0.40)    // muted for subtle use

    // MARK: Monochrome
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.50)
    static let textTertiary = Color(white: 0.35)
    static let divider = Color.white.opacity(0.08)

    // MARK: Feedback
    static let correct = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let incorrect = Color(red: 0.90, green: 0.30, blue: 0.30)
    static let scoreGold = Color(red: 0.95, green: 0.77, blue: 0.20)

    // MARK: Typography — New York serif for headings, SF Pro for body.
    // Built on text styles so they scale with Dynamic Type / accessibility text sizes.
    static let displayFont: Font = .system(.largeTitle, design: .serif).weight(.bold)
    static let titleFont: Font = .system(.title2, design: .serif).weight(.semibold)
    static let headingFont: Font = .system(.headline, design: .serif)
    static let bodyFont: Font = .system(.subheadline)
    static let captionFont: Font = .system(.caption)
    static let monoFont: Font = .system(.footnote, design: .monospaced).weight(.medium)

    // MARK: Haptics
    static func tapHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func successHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func errorHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - Pressable Button Style

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.80 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Hex Color (kept for JSON color parsing in atlasStructure.json)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        r = Double((int >> 16) & 0xFF) / 255
        g = Double((int >> 8) & 0xFF) / 255
        b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    nonisolated static func fromRGB(_ str: String?) -> Color {
        guard let str = str,
              str.hasPrefix("rgb("),
              str.hasSuffix(")")
        else { return .gray }
        let inner = String(str.dropFirst(4).dropLast()).split(separator: ",")
        guard inner.count == 3,
              let r = Double(inner[0].trimmingCharacters(in: .whitespaces)),
              let g = Double(inner[1].trimmingCharacters(in: .whitespaces)),
              let b = Double(inner[2].trimmingCharacters(in: .whitespaces))
        else { return .gray }
        return Color(red: r / 255, green: g / 255, blue: b / 255)
    }
}
