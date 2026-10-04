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
