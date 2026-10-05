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

struct ScoreLabel: View {
    let score: Int
    let total: Int

    var body: some View {
        Label("\(score)/\(total)", systemImage: "star.fill")
            .foregroundColor(Theme.scoreGold)
            .font(Theme.headingFont)
            .accessibilityLabel("Score \(score) of \(total)")
    }
}

/// Multiple-choice buttons with correct/incorrect feedback, then "Next →" once answered.
struct AnswerOptionsView: View {
    let options: [String]
    let correctAnswer: String
    let selectedAnswer: String?
    let showingFeedback: Bool
    var nextDisabled = false
    let onAnswer: (String) -> Void
    let onNext: () -> Void

    var body: some View {
        ForEach(options, id: \.self) { option in
            Button {
                onAnswer(option)
            } label: {
                HStack {
                    Text(option)
                        .font(Theme.bodyFont)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if showingFeedback && option == correctAnswer {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.correct)
                    }
                    if showingFeedback && option == selectedAnswer && option != correctAnswer {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.incorrect)
                    }
                }
                .padding()
                .background(background(for: option))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(showingFeedback)
            .accessibilityIdentifier("answerOption")
        }

        if showingFeedback {
            Button("Next →", action: onNext)
                .font(Theme.headingFont)
                .foregroundColor(.black)
                .padding(.horizontal, 40)
                .padding(.vertical, 12)
                .background(Theme.accent)
                .clipShape(Capsule())
                .disabled(nextDisabled)
                .transition(.scale)
        }
    }

    private func background(for option: String) -> Color {
        guard showingFeedback else { return Theme.bgCard }
        if option == correctAnswer { return Theme.correct.opacity(0.3) }
        if option == selectedAnswer { return Theme.incorrect.opacity(0.3) }
        return Color.white.opacity(0.05)
    }
}

// MARK: - Session Results

/// Shared end-of-session summary for both quiz modes.
struct QuizResultsView: View {
    let score: Int
    let total: Int
    let bestStreak: Int
    let missed: [String]
    let onPlayAgain: () -> Void

    private var percent: Int { total == 0 ? 0 : Int(round(Double(score) / Double(total) * 100)) }

    private var headline: String {
        switch percent {
        case 90...: return "Outstanding"
        case 70..<90: return "Well done"
        case 50..<70: return "Keep going"
        default: return "Keep practicing"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(headline)
                .font(Theme.titleFont)
                .foregroundColor(Theme.textPrimary)

            Text("\(score) / \(total)")
                .font(.system(size: 44, weight: .bold, design: .serif))
                .foregroundColor(Theme.accent)

            HStack(spacing: 24) {
                stat("Accuracy", "\(percent)%")
                stat("Best streak", "\(bestStreak)")
            }

            if !missed.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review these")
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textTertiary)
                    ForEach(missed, id: \.self) { name in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.left.circle")
                                .foregroundColor(Theme.incorrect)
                                .font(Theme.captionFont)
                            Text(name)
                                .font(Theme.bodyFont)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            }

            Button(action: onPlayAgain) {
                Text("Play Again")
                    .font(Theme.headingFont)
                    .foregroundColor(.black)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            .accessibilityLabel("Play again")
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.bgSecondary)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.bgCardStroke, lineWidth: 1))
        )
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.headingFont)
                .foregroundColor(Theme.textPrimary)
            Text(label)
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
        }
    }
}
