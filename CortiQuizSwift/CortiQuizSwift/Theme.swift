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
    // flashcard), SF Pro everywhere else, SF Rounded for numbers. Built on text styles so
    // they scale with Dynamic Type / accessibility text sizes.
    static let displayFont: Font = .system(.largeTitle, design: .serif).weight(.bold)
    static let titleFont: Font = .system(.title2, design: .serif).weight(.semibold)
    static let headingFont: Font = .headline
    static let bodyFont: Font = .subheadline
    static let captionFont: Font = .caption
    static func numberFont(_ style: Font.TextStyle) -> Font {
        .system(style, design: .rounded).weight(.bold)
    }

    // MARK: Layout
    enum Metrics {
        /// Widest a bottom panel (answers, study card) grows on iPad, so rows stay readable.
        static let panelMaxWidth: CGFloat = 560
        /// Width of the side panel when a mode lays out side by side (iPad landscape).
        static let sidePanelWidth: CGFloat = 400
        /// Corner radius of floating cards that aren't concentric with the screen.
        static let cardRadius: CGFloat = 22
    }

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
    /// X-ray "context" brain behind a highlighted structure (`NodeStyle.ghost`): a cool
    /// blue-white rim glow, so warm highlights stand out against it.
    static let ghost = UIColor(red: 0.62, green: 0.68, blue: 0.80, alpha: 1.0)
    /// How brightly ghost silhouettes glow. Every structure's rim adds up, so keep it low.
    static let ghostRimGain: CGFloat = 0.10
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

    // Home screen hero brain (`SCNNode.applyGlow`)
    static let heroGlow = UIColor(red: 0.83, green: 0.51, blue: 0.60, alpha: 1.0)      // Theme.accent
    static let heroLearning = UIColor(red: 0.95, green: 0.66, blue: 0.74, alpha: 1.0)
    static let heroMastered = UIColor(red: 1.00, green: 0.84, blue: 0.62, alpha: 1.0)
    static let heroFill: CGFloat = 0.06
    static let heroLearningFill: CGFloat = 0.22
    static let heroMasteredFill: CGFloat = 0.42
    /// Behind the 3D stage: near-black, a touch lighter in the middle for depth.
    static let stageCenter = UIColor(red: 0.075, green: 0.075, blue: 0.09, alpha: 1.0)
    static let stageEdge = UIColor(white: 0.0, alpha: 1.0)

    // MRI modes
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

// MARK: - Display Names

extension String {
    /// Atlas names are lowercase ("left putamen"); the UI shows them in sentence case.
    /// Names that already start with a capital (cerebellar lobules like "VIIA crusI-l1")
    /// are left alone.
    nonisolated var sentenceCased: String {
        guard let first, first.isLowercase else { return self }
        return first.uppercased() + dropFirst()
    }
}

extension BrainStructure {
    nonisolated var displayName: String { name.sentenceCased }

    /// Where the structure sits, as one line: "Prosencephalon › Telencephalon › Left
    /// frontal lobe". See `breadcrumb(_:bothSides:)`.
    nonisolated var breadcrumb: String { Self.breadcrumb(hierarchyPath) }

    /// A hierarchy path without the "Brain" root every structure shares, in sentence case,
    /// most specific last. `bothSides` drops "left"/"right" for a card standing for a pair.
    nonisolated static func breadcrumb(_ path: [String], bothSides: Bool = false) -> String {
        path.drop(while: { $0 == "Brain" })
            .map { (bothSides ? computeBaseName($0) : $0).sentenceCased }
            .joined(separator: " › ")
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
