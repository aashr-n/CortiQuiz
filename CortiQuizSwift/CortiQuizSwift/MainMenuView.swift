import SwiftUI

struct MainMenuView: View {
    @State private var appear = false
    private let store = ProgressStore.shared

    private struct ModeInfo: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
        let destination: AnyView
    }

    private var modes: [ModeInfo] {
        [
            ModeInfo(icon: "graduationcap.fill", title: "Learn Mode",
                     subtitle: "Flashcards — study with no pressure", destination: AnyView(LearnView())),
            ModeInfo(icon: "brain.head.profile", title: "Normal Mode",
                     subtitle: "Identify brain structures", destination: AnyView(QuizView())),
            ModeInfo(icon: "cube.transparent", title: "Explore Mode",
                     subtitle: "Browse the full brain atlas", destination: AnyView(ExploreView())),
            ModeInfo(icon: "waveform.path.ecg", title: "MRI Mode",
                     subtitle: "Dynamic brain cross-sections", destination: AnyView(MRIView())),
            ModeInfo(icon: "brain.filled.head.profile", title: "MRI Quiz",
                     subtitle: "Identify structures from slices", destination: AnyView(MRIQuizView())),
        ]
    }

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
                    .offset(y: appear ? 0 : -20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: appear)

                    Spacer()

                    VStack(spacing: 16) {
                        ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                            NavigationLink(destination: mode.destination) {
                                ModeCard(icon: mode.icon, title: mode.title, subtitle: mode.subtitle)
                            }
                            .buttonStyle(PressableStyle())
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 30)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8)
                                .delay(Double(index) * 0.08), value: appear)
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
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: appear)
                    }
                }
            }
            .onAppear { appear = true }
            .onDisappear { appear = false }
        }
        .tint(.white)
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
