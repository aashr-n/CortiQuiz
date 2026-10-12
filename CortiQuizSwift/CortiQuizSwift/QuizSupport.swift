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

/// Multiple-choice buttons with correct/incorrect feedback, then "Next" once answered.
struct AnswerOptionsView: View {
    let options: [String]
    let correctAnswer: String
    let selectedAnswer: String?
    let showingFeedback: Bool
    var nextDisabled = false
    let onAnswer: (String) -> Void
    let onNext: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        onAnswer(option)
                    } label: {
                        HStack {
                            Text(option)
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
                }
            }
        }

        if showingFeedback {
            Button(action: onNext) {
                HStack(spacing: 6) {
                    Text("Next")
                    Image(systemName: "arrow.right")
                }
                .font(Theme.headingFont)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(nextDisabled)
            .accessibilityLabel("Next")
            .transition(.scale(0.9).combined(with: .opacity))
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
        case 90...: return "Outstanding"
        case 70..<90: return "Well Done"
        case 50..<70: return "Keep Going"
        default: return "Keep Practicing"
        }
    }

    var body: some View {
        SummarySheet(actionTitle: "Play Again", action: onPlayAgain, onDone: onDone) {
            Text(headline)
                .font(Theme.titleFont)

            ScoreRing(fraction: fraction, caption: "correct", lineWidth: 12)
                .frame(width: 120, height: 120)

            HStack(spacing: 12) {
                statTile("Score", "\(score) of \(total)", icon: "star.fill", color: Theme.scoreGold)
                statTile("Best Streak", "\(bestStreak)", icon: "flame.fill", color: .orange)
            }

            if !missed.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Review These")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ForEach(missed, id: \.self) { name in
                        Label {
                            Text(name)
                                .font(Theme.bodyFont)
                        } icon: {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .foregroundStyle(Theme.incorrect)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.bgCard, in: .rect(cornerRadius: 20))
            }
        }
    }

    private func statTile(_ label: String, _ value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.bgCard, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
