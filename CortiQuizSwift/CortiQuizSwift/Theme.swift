import SwiftUI

// MARK: - Design Tokens

enum Theme {
    // MARK: Backgrounds — system grouped colors, so cards match native lists and sheets.
    static let bgCard = Color(uiColor: .secondarySystemGroupedBackground)
    static let bgCardStroke = Color.white.opacity(0.09)

    // MARK: Accent — dusty brain-pink (also the asset catalog's AccentColor)
    static let accent = Color(red: 0.83, green: 0.51, blue: 0.60)       // #D4829A

    // MARK: Text — system label colors
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(uiColor: .tertiaryLabel)

    // MARK: Feedback
    static let correct = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let incorrect = Color(red: 0.90, green: 0.30, blue: 0.30)
    static let scoreGold = Color(red: 0.95, green: 0.77, blue: 0.20)

    // MARK: Typography — New York serif for brand moments (titles, the answer on a
    // flashcard), SF Pro everywhere else. Built on text styles so they scale with
    // Dynamic Type / accessibility text sizes.
    static let titleFont: Font = .system(.title2, design: .serif).weight(.semibold)
    static let headingFont: Font = .headline
    static let bodyFont: Font = .subheadline
    static let captionFont: Font = .caption

    /// Navigation bar titles in New York, matching `titleFont`. Applied once at launch.
    static func applyNavigationBarFonts() {
        func serif(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            let system = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
            guard let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
            return UIFont(descriptor: descriptor, size: 0)
        }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: serif(.largeTitle, .bold)]
        bar.titleTextAttributes = [.font: serif(.headline, .semibold)]
    }

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
    static let miniBrain = UIColor(white: 0.7, alpha: 0.12)
    /// Mini-brain slice plane: where it's in front of the brain, and (fainter) through it.
    static let slicePlane = UIColor(red: 0.83, green: 0.51, blue: 0.60, alpha: 0.70)
    static let slicePlaneXRay = UIColor(red: 0.83, green: 0.51, blue: 0.60, alpha: 0.30)
    /// Behind and around the slice image. Opaque: the slice scene paints it over whatever
    /// lies outside every structure.
    static let sliceBackground = UIColor(white: 0.05, alpha: 1.0)
    /// MRI quiz target pulses between these two.
    static let mriTarget = UIColor.white
    static let mriTargetDim = UIColor(red: 0.0, green: 0.82, blue: 0.78, alpha: 1.0)

    /// Regions other than the quiz target or the tapped structure: same hue, faded toward
    /// the slice background (`brightness` 0 is background, 1 the original color).
    static func mriDimmed(_ color: UIColor, brightness: CGFloat = 0.2) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        var bg: CGFloat = 0
        sliceBackground.getWhite(&bg, alpha: nil)
        func fade(_ c: CGFloat) -> CGFloat { bg + (c - bg) * brightness }
        return UIColor(red: fade(r), green: fade(g), blue: fade(b), alpha: 1)
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
