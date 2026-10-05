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

// MARK: - 3D Scene Colors

/// Material colors for the SceneKit views. `nonisolated` (and plain RGB rather than
/// `UIColor(Theme.…)`) because nodes are styled on background threads while scenes load.
/// Values mirror the `Theme` palette above.
nonisolated enum SceneColors {
    /// Faded "context" brain behind a highlighted structure.
    static let ghost = UIColor(white: 0.58, alpha: 1.0)
    static let ghostOpacity: CGFloat = 0.16
    /// Structure the user is asked to identify.
    static let target = UIColor(red: 0.96, green: 0.24, blue: 0.36, alpha: 1.0)
    /// Learn mode: highlight once the answer is revealed (Theme.accent).
    static let revealed = UIColor(red: 0.83, green: 0.51, blue: 0.60, alpha: 1.0)
    /// Explore mode: the tapped / searched structure.
    static let selection = UIColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1.0)
    static let correct = UIColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1.0)   // Theme.correct
    static let incorrect = UIColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1.0) // Theme.incorrect
    /// The other hemisphere of a correctly answered left/right pair.
    static let pairedCorrect = UIColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1.0)
    static let pairedCorrectOpacity: CGFloat = 0.75

    // MRI modes
    static let miniBrain = UIColor(white: 0.7, alpha: 0.35)
    static let slicePlane = UIColor(red: 0.83, green: 0.51, blue: 0.60, alpha: 0.40)
    /// MRI quiz target pulses between these two.
    static let mriTarget = UIColor.white
    static let mriTargetDim = UIColor(red: 0.0, green: 0.82, blue: 0.78, alpha: 1.0)

    /// Non-target regions in the MRI quiz slice: same hue, much darker.
    static func mriDimmed(_ color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * 0.2, green: g * 0.2, blue: b * 0.2, alpha: 0.4)
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

// MARK: - Atlas Color Parsing

extension Color {
    /// Parses atlasStructure.json's `rgb(r,g,b)` colors.
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
