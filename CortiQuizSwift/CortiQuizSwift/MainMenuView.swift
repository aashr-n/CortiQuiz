import SwiftUI

// MARK: - Modes

enum AppMode: String, CaseIterable, Identifiable, Hashable {
    case learn, quiz, mriQuiz, explore, mri

    var id: Self { self }

    /// Menu sections: test yourself, or look around.
    static let practice: [AppMode] = [.learn, .quiz, .mriQuiz]
    static let reference: [AppMode] = [.explore, .mri]

    var icon: String {
        switch self {
        case .learn: return "rectangle.portrait.on.rectangle.portrait.angled.fill"
        case .quiz: return "brain.head.profile.fill"
        case .mriQuiz: return "square.3.layers.3d.middle.filled"
        case .explore: return "cube.transparent.fill"
        case .mri: return "slider.horizontal.below.square.filled.and.square"
        }
    }

    /// Icon tile color on the menu.
    var color: Color {
        switch self {
        case .learn: return .orange
        case .quiz: return Theme.accent
        case .mriQuiz: return .purple
        case .explore: return .teal
        case .mri: return .indigo
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

    var subtitle: String {
        switch self {
        case .learn: return "Flashcards at your own pace"
        case .quiz: return "Name the highlighted structure"
        case .mriQuiz: return "Name structures on brain slices"
        case .explore: return "Browse every structure in 3D"
        case .mri: return "Scroll through cross-sections"
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

/// The menu: a sidebar beside the open mode on iPad, a navigation stack on iPhone.
///
/// iPhone doesn't use a collapsed split view: its push made the main thread wait on a
/// lower-priority thread at the start of every transition (a priority inversion the UI tests
/// flagged on each mode open), which a plain stack doesn't. iPad keeps the split view, which
/// also keeps the open mode when a window crosses between compact and regular widths.
struct MainMenuView: View {
    /// iPad: the mode in the detail column.
    @State private var selection: AppMode?
    /// iPhone: the pushed mode.
    @State private var path: [AppMode] = []
    @State private var showingAbout = false
    /// Starts with the menu showing, even in iPad portrait where a split view would hide it
    /// behind the detail's "Choose a mode".
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let usesSplitView = UIDevice.current.userInterfaceIdiom == .pad

    var body: some View {
        Group {
            if usesSplitView {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    // A narrow window collapses to the list alone; the brain moves into it.
                    MenuList(selection: $selection, showsHero: sizeClass == .compact,
                             heroIsActive: selection == nil, open: open, onAbout: { showingAbout = true })
                } detail: {
                    if let mode = selection {
                        NavigationStack { ModeScreen(mode: mode) }
                            .id(mode)
                    } else {
                        MenuPlaceholder(mastery: ProgressStore.shared.masteryByName)
                    }
                }
                // Once a mode is open, let the system decide (iPad portrait gives the mode
                // the whole screen); back on the menu, show it again.
                .onChange(of: selection) { columnVisibility = selection == nil ? .all : .automatic }
                .environment(\.leaveMode, LeaveModeAction { selection = nil })
            } else {
                NavigationStack(path: $path) {
                    MenuList(selection: nil, showsHero: true, heroIsActive: path.isEmpty, open: open, onAbout: { showingAbout = true })
                        .navigationDestination(for: AppMode.self) { ModeScreen(mode: $0) }
                }
                .environment(\.leaveMode, LeaveModeAction { path.removeAll() })
            }
        }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .tint(Theme.accent)
    }

    private func open(_ mode: AppMode) {
        if usesSplitView { selection = mode } else { path = [mode] }
    }
}

/// A mode with its title, as pushed or shown in the detail column.
private struct ModeScreen: View {
    let mode: AppMode

    var body: some View {
        mode.destination
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The menu's list: the hero brain (iPhone), progress or Start Here, and the modes.
private struct MenuList: View {
    /// The split view's selection on iPad; nil on iPhone, where rows push onto the stack.
    let selection: Binding<AppMode?>?
    let showsHero: Bool
    var heroIsActive = true
    let open: (AppMode) -> Void
    let onAbout: () -> Void

    private let store = ProgressStore.shared

    var body: some View {
        Group {
            if let selection {
                List(selection: selection) { sections }
            } else {
                List { sections }
            }
        }
        .scrollContentBackground(.hidden)
        .background { MenuBackground() }
        .navigationTitle("CortiQuiz")
        .navigationSubtitle("Brain Anatomy Trainer")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("About", systemImage: "info.circle", action: onAbout)
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        // On iPad the brain gets the whole detail column until a mode is picked.
        if showsHero {
            Section {
                HeroBrainView(mastery: store.masteryByName, isActive: heroIsActive)
                    .frame(height: 220)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            .listSectionSpacing(4)
        }

        Section {
            if store.totalAnswered > 0 {
                ProgressSummary(store: store)
            } else {
                WelcomeRow { open(.learn) }
            }
        } footer: {
            if store.totalAnswered > 0 {
                Text("Structures you've mastered in the quizzes glow gold on the brain.")
            }
        }

        Section("Practice") {
            ForEach(AppMode.practice) { ModeRow(mode: $0) }
        }

        Section("Explore") {
            ForEach(AppMode.reference) { ModeRow(mode: $0) }
        }
    }
}

/// Grouped background with a faint wash of the accent behind the title and the brain.
private struct MenuBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
            RadialGradient(
                colors: [Theme.accent.opacity(0.30), Theme.accent.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.12),
                startRadius: 0,
                endRadius: 380
            )
            .frame(height: 520)
        }
        .ignoresSafeArea()
    }
}

/// iPad, before a mode is open: the brain, large.
private struct MenuPlaceholder: View {
    let mastery: [String: ProgressStore.Mastery]

    var body: some View {
        ZStack {
            MenuBackground()
            VStack(spacing: 8) {
                HeroBrainView(mastery: mastery)
                    .frame(maxWidth: 720, maxHeight: 460)
                Text("CortiQuiz")
                    .font(Theme.displayFont)
                Text("Choose a mode to start studying.")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(40)
        }
    }
}

// MARK: - Rows

private struct ModeRow: View {
    let mode: AppMode

    var body: some View {
        NavigationLink(value: mode) {
            HStack(spacing: 14) {
                ModeIcon(mode: mode)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.body.weight(.semibold))
                    Text(mode.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            }
            .padding(.vertical, 6)
        }
    }
}

/// Settings-style rounded tile with the mode's symbol.
private struct ModeIcon: View {
    let mode: AppMode

    var body: some View {
        Image(systemName: mode.icon)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(mode.color.gradient, in: .rect(cornerRadius: 11, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// First launch: what the app is for, and where to begin.
private struct WelcomeRow: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start Here")
                    .font(.headline)
                Text("Learn each structure with flashcards, then name them in 3D and on MRI slices. Everything you master lights up on the brain.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(action: onStart) {
                Label("Start Learning", systemImage: "rectangle.portrait.on.rectangle.portrait.angled.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.vertical, 8)
    }
}

/// Lifetime accuracy ring plus totals.
private struct ProgressSummary: View {
    let store: ProgressStore

    var body: some View {
        HStack(spacing: 20) {
            ScoreRing(fraction: store.accuracy, caption: "accuracy")
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 7) {
                Text("Your Progress")
                    .font(.headline)
                stat("\(store.totalAnswered) answered", icon: "checkmark.circle.fill", color: Theme.correct)
                stat("\(store.masteredCount) mastered", icon: "star.circle.fill", color: Color(SceneColors.heroMastered))
                stat("Best streak \(store.bestStreak)", icon: "flame.fill", color: .orange)
                if !store.reviewQueue.isEmpty {
                    stat("\(store.reviewQueue.count) to review", icon: "arrow.uturn.backward.circle.fill", color: Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ text: String, icon: String, color: Color) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
    }
}
