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

struct MainMenuView: View {
    private let store = ProgressStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.totalAnswered > 0 {
                        ProgressSummary(store: store)
                    } else {
                        WelcomeRow()
                    }
                }

                Section("Practice") {
                    ForEach(AppMode.practice) { ModeRow(mode: $0) }
                }

                Section {
                    ForEach(AppMode.reference) { ModeRow(mode: $0) }
                } header: {
                    Text("Explore")
                } footer: {
                    Text("Anatomy from the SPL-PNL Brain Atlas, Surgical Planning Lab and Psychiatry Neuroimaging Lab, Brigham and Women's Hospital.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { MenuBackground() }
            .navigationTitle("CortiQuiz")
            .navigationSubtitle("Brain Anatomy Trainer")
            .navigationDestination(for: AppMode.self) { mode in
                mode.destination
                    .navigationTitle(mode.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .tint(Theme.accent)
    }
}

/// Grouped background with a faint wash of the accent behind the title.
private struct MenuBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
            LinearGradient(
                colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 420)
        }
        .ignoresSafeArea()
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

private struct WelcomeRow: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "brain.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent.gradient)
                .symbolEffect(.breathe)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome")
                    .font(.headline)
                Text("Start with Learn to study each structure, then test yourself in a quiz. Your progress will show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
                .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 8) {
                Text("Your Progress")
                    .font(.headline)
                stat("\(store.totalAnswered) answered", icon: "checkmark.circle.fill", color: Theme.correct)
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
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
    }
}
