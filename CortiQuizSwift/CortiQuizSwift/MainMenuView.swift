import SwiftUI

// MARK: - Modes

enum AppMode: String, CaseIterable, Identifiable, Hashable {
    case learn, quiz, explore, mri, mriQuiz

    var id: Self { self }

    var icon: String {
        switch self {
        case .learn: return "graduationcap.fill"
        case .quiz: return "brain.head.profile"
        case .explore: return "cube.transparent"
        case .mri: return "waveform.path.ecg"
        case .mriQuiz: return "brain.filled.head.profile"
        }
    }

    var title: String {
        switch self {
        case .learn: return "Learn Mode"
        case .quiz: return "Normal Mode"
        case .explore: return "Explore Mode"
        case .mri: return "MRI Mode"
        case .mriQuiz: return "MRI Quiz"
        }
    }

    var subtitle: String {
        switch self {
        case .learn: return "Flashcards — study with no pressure"
        case .quiz: return "Identify brain structures"
        case .explore: return "Browse the full brain atlas"
        case .mri: return "Dynamic brain cross-sections"
        case .mriQuiz: return "Identify structures from slices"
        }
    }

    /// Built only when the mode is opened.
    @ViewBuilder var destination: some View {
        switch self {
        case .learn: LearnView()
        case .quiz: QuizView()
        case .explore: ExploreView()
        case .mri: MRIView()
        case .mriQuiz: MRIQuizView()
        }
    }
}

// MARK: - Main Menu

struct MainMenuView: View {
    @State private var appear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let store = ProgressStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Theme.bgPrimary, Theme.bgSecondary],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    VStack(spacing: 8) {
                        Text("CortiQuiz")
                            .font(Theme.displayFont)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Brain Anatomy Trainer")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: slideOffset(-20))
                    .animation(entrance(), value: appear)

                    Spacer()

                    VStack(spacing: 16) {
                        ForEach(Array(AppMode.allCases.enumerated()), id: \.element) { index, mode in
                            NavigationLink(value: mode) {
                                ModeCard(icon: mode.icon, title: mode.title, subtitle: mode.subtitle)
                            }
                            .buttonStyle(PressableStyle())
                            .opacity(appear ? 1 : 0)
                            .offset(y: slideOffset(30))
                            .animation(entrance(delay: Double(index) * 0.08), value: appear)
                        }
                    }
                    .padding(.horizontal)

                    Spacer()

                    if store.totalAnswered > 0 {
                        HStack(spacing: 28) {
                            statItem("Answered", "\(store.totalAnswered)")
                            statItem("Accuracy", "\(Int(store.accuracy * 100))%")
                            statItem("Best streak", "\(store.bestStreak)")
                        }
                        .padding(.bottom, 12)
                        .opacity(appear ? 1 : 0)
                        .animation(entrance(delay: 0.4), value: appear)
                    }
                }
            }
            .navigationDestination(for: AppMode.self) { $0.destination }
            .onAppear { appear = true }
            .onDisappear { appear = false }
        }
        .tint(.white)
    }

    /// Slide-in distance before the entrance animation; none with Reduce Motion.
    private func slideOffset(_ distance: CGFloat) -> CGFloat {
        appear || reduceMotion ? 0 : distance
    }

    /// Staggered spring normally; a plain short fade with Reduce Motion.
    private func entrance(delay: Double = 0) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.2)
            : .spring(response: 0.6, dampingFraction: 0.8).delay(delay)
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.headingFont)
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Mode Card

private struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(Theme.accent)
                .frame(width: 50, height: 50)
                .background(Theme.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.headingFont)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.textTertiary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.bgCardStroke, lineWidth: 1)
                )
        )
    }
}
