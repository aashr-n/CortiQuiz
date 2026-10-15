import SwiftUI

// MARK: - Modes

enum AppMode: String, CaseIterable, Identifiable, Hashable {
    case learn, quiz, mriQuiz, explore, mri

    var id: Self { self }

    var icon: String {
        switch self {
        case .learn: return "rectangle.portrait.on.rectangle.portrait.angled.fill"
        case .quiz: return "brain.head.profile.fill"
        case .mriQuiz: return "square.3.layers.3d.middle.filled"
        case .explore: return "cube.transparent.fill"
        case .mri: return "slider.horizontal.below.square.filled.and.square"
        }
    }

    var title: String {
        switch self {
        case .learn: return "Learn"
        case .quiz: return "3D Quiz"
        case .mriQuiz: return "MRI Quiz"
        case .explore: return "3D Atlas"
        case .mri: return "MRI Slicer"
        }
    }

    /// The line under the title on the menu, short enough for a half-width tile.
    var subtitle: String {
        switch self {
        case .learn: return "Flashcards at your own pace"
        case .quiz: return "Name structures in 3D"
        case .mriQuiz: return "Name them on slices"
        case .explore: return "Every structure in 3D"
        case .mri: return "Scroll through slices"
        }
    }

    /// Built only when the mode is opened.
    @ViewBuilder var destination: some View {
        switch self {
        case .learn: LearnView()
        case .quiz: QuizView()
        case .mriQuiz: MRIQuizView()
        case .explore: ExploreView()
        case .mri: MRIView()
        }
    }
}

// MARK: - Main Menu

/// The menu: the turning brain, your progress under it, and a glass tile for each mode.
/// A mode pushes over the whole screen, on iPhone and iPad alike.
struct MainMenuView: View {
    @State private var path: [AppMode] = []
    @State private var showingAbout = false

    var body: some View {
        NavigationStack(path: $path) {
            MenuScreen(isActive: path.isEmpty, open: { path = [$0] }, onAbout: { showingAbout = true })
                .navigationDestination(for: AppMode.self) { ModeScreen(mode: $0) }
        }
        .environment(\.leaveMode, LeaveModeAction { path.removeAll() })
        .sheet(isPresented: $showingAbout) { AboutView() }
        .tint(Theme.accent)
    }
}

/// A mode with its title, as pushed from the menu.
private struct ModeScreen: View {
    let mode: AppMode

    var body: some View {
        mode.destination
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The menu's one screen, with no navigation bar. Portrait: the wordmark, the brain, then the
/// progress and tiles under it. Wide (iPad landscape): a spread, the brain the full height
/// of the left and the wordmark heading a column of progress and tiles on the right. The
/// brain takes whatever room the rest leaves; at large text sizes the whole screen scrolls.
private struct MenuScreen: View {
    /// False while a mode is open over the menu, so the brain stops drawing.
    let isActive: Bool
    let open: (AppMode) -> Void
    let onAbout: () -> Void

    @State private var appeared = false
    private let store = ProgressStore.shared

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height && geo.size.width >= 700
            // `AnyLayout` keeps the brain's identity when an iPad rotates, so its scene
            // isn't rebuilt.
            let layout = wide ? AnyLayout(HStackLayout(spacing: 40)) : AnyLayout(VStackLayout(spacing: 12))
            ScrollView {
                layout {
                    if !wide { wordmark }
                    HeroBrainView(mastery: store.masteryByName, isActive: isActive)
                        .frame(minHeight: 220, maxHeight: .infinity)
                    VStack(spacing: 32) {
                        if wide { wordmark }
                        panel
                    }
                    .frame(maxWidth: wide ? 440 : 560)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.stage)
        }
        .overlay(alignment: .topTrailing) {
            AboutButton(action: onAbout)
                .padding(.trailing, 16)
                .padding(.top, 10)
                .entrance(appeared, order: 0)
        }
        .navigationTitle("CortiQuiz")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear { appeared = true }
    }

    private var wordmark: some View {
        Wordmark()
            .padding(.top, 4)
            .entrance(appeared, order: 0)
    }

    private var panel: some View {
        VStack(spacing: 20) {
            Group {
                if store.totalAnswered > 0 {
                    ProgressStrip(store: store)
                } else {
                    WelcomeNote()
                }
            }
            .entrance(appeared, order: 1)

            ModeGrid(startHere: store.totalAnswered == 0, reviewCount: store.reviewQueue.count,
                     appeared: appeared, open: open)
        }
    }
}

// MARK: - Header

/// "Corti*Quiz*" in Times over a tracked tagline. A logo, so like a navigation bar it stops
/// growing at the largest standard text size.
private struct Wordmark: View {
    var body: some View {
        VStack(spacing: 3) {
            Text("\(Text("Corti"))\(Text("Quiz").italic())")
                .font(Theme.displayFont)
            Text("Brain Anatomy Trainer")
                .eyebrow(tracking: 2.2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        // Clear of the About button on both sides, so it stays centered.
        .padding(.horizontal, 52)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CortiQuiz, Brain Anatomy Trainer")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A glass circle in the top corner, floating over the menu.
private struct AboutButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("About", systemImage: "info")
                .labelStyle(.iconOnly)
                .font(Theme.font(.body).weight(.bold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(.primary)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityShowsLargeContentViewer()
    }
}

// MARK: - Progress

/// Lifetime numbers in a row, or two by two when they don't fit (large text). Learning and
/// Mastered carry the brain's two highlight colors, so the numbers double as its legend.
private struct ProgressStrip: View {
    let store: ProgressStore

    var body: some View {
        let mastered = store.masteredCount
        let accuracy = StatColumn(value: "\(Int((store.accuracy * 100).rounded()))%", label: "Accuracy")
        let learning = StatColumn(value: "\(store.masteryByName.count - mastered)", label: "Learning",
                                  dot: Color(SceneColors.heroLearning))
        let mastery = StatColumn(value: "\(mastered)", label: "Mastered", dot: Color(SceneColors.heroMastered))
        let streak = StatColumn(value: "\(store.bestStreak)", label: "Best Streak")
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                accuracy
                divider
                learning
                divider
                mastery
                divider
                streak
            }
            Grid(verticalSpacing: 14) {
                GridRow { accuracy; learning }
                GridRow { mastery; streak }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.12))
            .frame(width: 1, height: 22)
    }
}

private struct StatColumn: View {
    let value: String
    let label: String
    var dot: Color?

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.font(.title2).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            HStack(spacing: 5) {
                if let dot {
                    Circle()
                        .fill(dot)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .eyebrow(tracking: 0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// First launch: what the app is for, in place of the numbers.
private struct WelcomeNote: View {
    var body: some View {
        Text("Learn each structure with flashcards, then name it in 3D and on MRI slices. Everything you master lights up on the brain.")
            .font(Theme.font(.subheadline))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 340)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Mode Tiles

/// The modes as glass tiles: Learn across the top, then the quizzes, then the reference
/// tools, with 3D on the left and MRI on the right.
private struct ModeGrid: View {
    let startHere: Bool
    let reviewCount: Int
    let appeared: Bool
    let open: (AppMode) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    private let gap: CGFloat = 10

    var body: some View {
        // At accessibility text sizes the pairs stack, one tile per row.
        let pair = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: gap)) : AnyLayout(HStackLayout(spacing: gap))
        let review = reviewCount > 0 ? "\(reviewCount) to review" : nil

        GlassEffectContainer(spacing: gap) {
            VStack(spacing: gap) {
                ModeTile(mode: .learn, banner: true, note: startHere ? "Start here" : nil,
                         highlighted: startHere, open: open)
                    .fixedSize(horizontal: false, vertical: true)
                    .entrance(appeared, order: 2)
                pair {
                    ModeTile(mode: .quiz, note: review, open: open)
                    ModeTile(mode: .mriQuiz, note: review, open: open)
                }
                .fixedSize(horizontal: false, vertical: true)
                .entrance(appeared, order: 3)
                pair {
                    ModeTile(mode: .explore, open: open)
                    ModeTile(mode: .mri, open: open)
                }
                .fixedSize(horizontal: false, vertical: true)
                .entrance(appeared, order: 4)
            }
        }
    }
}

private struct ModeTile: View {
    let mode: AppMode
    /// Full width, with the words beside the icon instead of under it.
    var banner = false
    /// In the top corner: "Start here", or how many flagged structures the quiz asks first.
    var note: String?
    /// The tile to start with: drawn with a heavier outline.
    var highlighted = false
    let open: (AppMode) -> Void

    static let cornerRadius: CGFloat = 26

    var body: some View {
        Button { open(mode) } label: {
            Group {
                if banner {
                    HStack(spacing: 14) {
                        icon
                        words
                        Spacer(minLength: 8)
                        noteText
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            icon
                            Spacer(minLength: 8)
                            noteText
                        }
                        Spacer(minLength: 14)
                        words
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(GlassTileStyle(emphasized: highlighted, cornerRadius: Self.cornerRadius))
        .accessibilityLabel(mode.title)
        .accessibilityValue(note ?? "")
        .accessibilityHint(mode.subtitle)
    }

    private var icon: some View {
        Image(systemName: mode.icon)
            .font(Theme.font(.title2))
            .foregroundStyle(.primary)
            .frame(minWidth: 30, alignment: .leading)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(mode.title)
                .font(Theme.font(.title3).weight(.bold))
                .foregroundStyle(.primary)
            Text(mode.subtitle)
                .font(Theme.font(.footnote))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.leading)
    }

    @ViewBuilder private var noteText: some View {
        if let note {
            Text(note)
                .font(Theme.font(.caption).italic())
                .foregroundStyle(.primary)
        }
    }
}

/// A button drawn as a Liquid Glass slab that answers touch, with a hairline edge so it
/// holds its shape on the plain backdrop.
private struct GlassTileStyle: ButtonStyle {
    var emphasized = false
    var cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .glassEffect(.regular.interactive(), in: shape)
            .overlay(shape.strokeBorder(.primary.opacity(emphasized ? 0.45 : 0.1), lineWidth: emphasized ? 1 : 0.5))
    }
}

// MARK: - Details

private extension Text {
    /// Small tracked capitals, for labels above or under content.
    func eyebrow(tracking: CGFloat = 1) -> some View {
        font(Theme.font(.caption2).weight(.bold))
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

private extension View {
    /// Fades and rises into place when the menu first appears, `order` steps after the first.
    func entrance(_ shown: Bool, order: Int) -> some View {
        modifier(Entrance(shown: shown, order: order))
    }
}

private struct Entrance: ViewModifier {
    let shown: Bool
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .animation(.spring(duration: 0.7, bounce: 0.2).delay(0.07 * Double(order)), value: shown)
    }
}
