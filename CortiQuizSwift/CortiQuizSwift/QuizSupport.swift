import SwiftUI

// MARK: - Distractor Builder

enum QuizOptionBuilder {
    /// Build `count` answer options for `target`, preferring anatomically plausible
    /// distractors: structures sharing the target's parent group come first, then a
    /// random fill. Returned shuffled, always including the correct `baseName`.
    static func makeOptions(target: BrainStructure, pool: [BrainStructure], count: Int = 4) -> [String] {
        var options = Set<String>([target.baseName])

        let siblings = pool.filter { $0.parentID == target.parentID && $0.baseName != target.baseName }
        for s in siblings.shuffled() {
            if options.count >= count { break }
            options.insert(s.baseName)
        }

        if options.count < count {
            for s in pool.shuffled() {
                if options.count >= count { break }
                if !options.contains(s.baseName) { options.insert(s.baseName) }
            }
        }

        return options.shuffled()
    }
}

// MARK: - Target Picker

/// Chooses the next quiz target by anatomical name (`baseName`), so a left/right pair is
/// no more likely than a midline structure. In order of preference:
/// 1. structures flagged "Study again" in Learn mode (oldest first),
/// 2. now and then, one of your weakest structures,
/// 3. any structure not yet asked this session.
enum QuizTargetPicker {
    static func pick<R: RandomNumberGenerator>(
        from baseNames: [String],
        flagged: [String],
        weak: [String],
        exclude asked: Set<String>,
        weakChance: Double = 0.3,
        using rng: inout R
    ) -> String? {
        var available = baseNames.filter { !asked.contains($0) }
        if available.isEmpty { available = baseNames }
        let availableSet = Set(available)

        if let next = flagged.first(where: availableSet.contains) { return next }

        let weakAvailable = weak.filter(availableSet.contains)
        if !weakAvailable.isEmpty, Double.random(in: 0..<1, using: &rng) < weakChance {
            return weakAvailable.randomElement(using: &rng)
        }
        return available.randomElement(using: &rng)
    }

    static func pick(from baseNames: [String], flagged: [String], weak: [String], exclude asked: Set<String>) -> String? {
        var rng = SystemRandomNumberGenerator()
        return pick(from: baseNames, flagged: flagged, weak: weak, exclude: asked, using: &rng)
    }
}

// MARK: - Session

/// Score and streak bookkeeping for one fixed-length session, shared by both quiz modes.
struct QuizSession {
    let length: Int
    private(set) var answered = 0
    private(set) var score = 0
    private(set) var streak = 0
    private(set) var bestStreak = 0
    /// Whether each answered question was right, in order.
    private(set) var results: [Bool] = []
    /// Correct answers the user got wrong, without duplicates, in the order missed.
    private(set) var missed: [String] = []
    /// baseNames already asked, so a session never repeats a structure.
    private(set) var asked: Set<String> = []

    init(length: Int = 10) {
        self.length = length
    }

    var isFinished: Bool { answered >= length }

    /// 1-based number of the question on screen.
    func questionNumber(showingFeedback: Bool) -> Int {
        min(answered + (showingFeedback ? 0 : 1), length)
    }

    mutating func markAsked(_ baseName: String) {
        asked.insert(baseName)
    }

    mutating func record(correctAnswer: String, wasCorrect: Bool) {
        answered += 1
        results.append(wasCorrect)
        if wasCorrect {
            score += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
        } else {
            streak = 0
            if !missed.contains(correctAnswer) { missed.append(correctAnswer) }
        }
    }
}

// MARK: - Shared Quiz Views

/// Running score, shown in the navigation bar.
struct ScoreLabel: View {
    let score: Int
    let total: Int

    var body: some View {
        Label("\(score)/\(total)", systemImage: "star.fill")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.scoreGold)
            .contentTransition(.numericText())
            .animation(.snappy, value: score)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 4)
            .accessibilityLabel("Score \(score) of \(total)")
    }
}

/// The question area shared by both quizzes: session progress, the prompt (the verdict once
/// answered), the answer options, and an action row that shows a tip until Next replaces it.
/// Both states get the same space, so the panel and the stage above it keep their size.
/// The verdict is only built once answered: it names the structure.
struct QuizPanel: View {
    let prompt: String
    let tip: String
    var tipIcon = "hand.draw"
    let session: QuizSession
    let options: [String]
    let correctAnswer: String
    let selectedAnswer: String?
    let showingFeedback: Bool
    /// The structure asked about with its hemisphere ("Left putamen"), shown with the verdict.
    var detail: String?
    var nextDisabled = false
    let onAnswer: (String) -> Void
    let onNext: () -> Void

    private var answeredCorrectly: Bool { selectedAnswer == correctAnswer }

    /// Room for the verdict's two lines, and for the Next button.
    @ScaledMetric(relativeTo: .headline) private var headerHeight: CGFloat = 46
    @ScaledMetric(relativeTo: .headline) private var actionHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 14) {
            SessionProgressBar(results: session.results, total: session.length)
                .padding(.horizontal, 2)

            Group {
                if showingFeedback {
                    verdict
                } else {
                    Text(prompt)
                        .font(Theme.headingFont)
                        .multilineTextAlignment(.center)
                }
            }
            .transition(.blurReplace)
            .frame(minHeight: headerHeight)

            AnswerOptionsView(
                options: options,
                correctAnswer: correctAnswer,
                selectedAnswer: selectedAnswer,
                showingFeedback: showingFeedback,
                onAnswer: onAnswer
            )

            Group {
                if showingFeedback {
                    nextButton
                        .transition(.scale(0.92).combined(with: .opacity))
                } else {
                    Label(tip, systemImage: tipIcon)
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: actionHeight)
        }
        .animation(.snappy, value: showingFeedback)
    }

    /// "Correct" or "Not quite", the exact structure, and the streak once it's worth noting.
    private var verdict: some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                Label(answeredCorrectly ? "Correct" : "Not quite",
                      systemImage: answeredCorrectly ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(Theme.headingFont)
                    .foregroundStyle(answeredCorrectly ? Theme.correct : Theme.incorrect)
                    .symbolEffect(.bounce, value: showingFeedback)
                if answeredCorrectly, session.streak >= 3 {
                    Label("\(session.streak) in a row", systemImage: "flame.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.16), in: .capsule)
                }
            }
            if let detail {
                Text(detail)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var nextButton: some View {
        Button(action: onNext) {
            HStack(spacing: 6) {
                Text(session.isFinished ? "See Results" : "Next")
                Image(systemName: session.isFinished ? "flag.checkered" : "arrow.right")
            }
            .font(Theme.headingFont)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(nextDisabled)
        .accessibilityLabel(session.isFinished ? "See Results" : "Next")
    }
}

/// Multiple-choice buttons with correct/incorrect feedback.
struct AnswerOptionsView: View {
    let options: [String]
    let correctAnswer: String
    let selectedAnswer: String?
    let showingFeedback: Bool
    let onAnswer: (String) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        onAnswer(option)
                    } label: {
                        HStack {
                            Text(option.sentenceCased)
                                .font(Theme.bodyFont.weight(.medium))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            feedbackIcon(for: option)
                        }
                        .foregroundStyle(dimmed(option) ? Theme.textSecondary : Theme.textPrimary)
                    }
                    .buttonStyle(AnswerButtonStyle(tint: tint(for: option)))
                    .disabled(showingFeedback)
                    .accessibilityIdentifier("answerOption")
                    .accessibilityValue(accessibilityValue(for: option))
                }
            }
        }
    }

    @ViewBuilder
    private func feedbackIcon(for option: String) -> some View {
        if showingFeedback && option == correctAnswer {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.correct)
                .transition(.scale.combined(with: .opacity))
        } else if showingFeedback && option == selectedAnswer {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Theme.incorrect)
                .transition(.scale.combined(with: .opacity))
        }
    }

    /// Answered: options that were neither right nor picked fade back.
    private func dimmed(_ option: String) -> Bool {
        showingFeedback && option != correctAnswer && option != selectedAnswer
    }

    private func tint(for option: String) -> Color? {
        guard showingFeedback else { return nil }
        if option == correctAnswer { return Theme.correct.opacity(0.45) }
        if option == selectedAnswer { return Theme.incorrect.opacity(0.45) }
        return nil
    }

    private func accessibilityValue(for option: String) -> String {
        guard showingFeedback else { return "" }
        if option == correctAnswer { return option == selectedAnswer ? "Your answer, correct" : "Correct answer" }
        if option == selectedAnswer { return "Your answer, incorrect" }
        return ""
    }
}

/// Full-width answer row in Liquid Glass, tinted once answered.
private struct AnswerButtonStyle: ButtonStyle {
    let tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: 18))
    }
}

// MARK: - Session Results

/// Shared end-of-session summary for both quiz modes, shown in a sheet.
struct QuizResultsView: View {
    let score: Int
    let total: Int
    let bestStreak: Int
    let missed: [String]
    let onPlayAgain: () -> Void
    let onDone: () -> Void

    private var fraction: Double { total == 0 ? 0 : Double(score) / Double(total) }

    private var headline: String {
        switch Int((fraction * 100).rounded()) {
        case 100: return "Perfect Round"
        case 90...: return "Outstanding"
        case 70..<90: return "Well Done"
        case 50..<70: return "Keep Going"
        default: return "Keep Practicing"
        }
    }

    var body: some View {
        SummarySheet(actionTitle: "Play Again", action: onPlayAgain, onDone: onDone) {
            VStack(spacing: 4) {
                Text(headline)
                    .font(Theme.displayFont)
                Text("You named \(score) of \(total) structures.")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)

            ScoreRing(fraction: fraction, caption: "correct", lineWidth: 14)
                .frame(width: 148, height: 148)
                .padding(.vertical, 4)

            HStack(spacing: 12) {
                StatTile(label: "Score", value: "\(score) of \(total)", icon: "star.fill", color: Theme.scoreGold)
                StatTile(label: "Best Streak", value: "\(bestStreak)", icon: "flame.fill", color: .orange)
            }

            if missed.isEmpty {
                Label("Every structure named. Try the other quiz next.", systemImage: "sparkles")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Theme.bgCard, in: .rect(cornerRadius: Theme.Metrics.cardRadius))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Missed This Round")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                    ForEach(missed, id: \.self) { name in
                        Label {
                            Text(name.sentenceCased)
                                .font(Theme.bodyFont)
                        } icon: {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .foregroundStyle(Theme.incorrect)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.bgCard, in: .rect(cornerRadius: Theme.Metrics.cardRadius))
            }
        }
    }
}
