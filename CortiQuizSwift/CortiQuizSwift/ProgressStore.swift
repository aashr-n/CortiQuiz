import SwiftUI

// MARK: - Progress Store

/// Lightweight, persistent learning record shared by every study mode.
/// Tracks per-structure accuracy (so we can surface weak spots), lifetime totals, the best
/// single-session streak, and the structures Learn mode flagged for review.
/// Backed by `UserDefaults` as a single JSON blob.
@MainActor
@Observable
final class ProgressStore {
    static let shared = ProgressStore()

    struct StructureStat: Codable {
        var seen: Int = 0
        var correct: Int = 0
        var wrong: Int = 0
        var accuracy: Double { seen == 0 ? 0 : Double(correct) / Double(seen) }
    }

    private(set) var stats: [String: StructureStat] = [:]   // keyed by baseName
    /// Longest run of correct answers within one quiz session.
    private(set) var bestStreak: Int = 0
    private(set) var totalAnswered: Int = 0
    private(set) var totalCorrect: Int = 0
    /// baseNames the user marked "Study again" in Learn mode, oldest first. Quizzes ask these
    /// first; a structure leaves the queue once it's answered correctly in a quiz.
    private(set) var reviewQueue: [String] = []

    private let defaults: UserDefaults
    private let defaultsKey = "cortiquiz.progress.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Record one answered quiz question. `streak` is the session's current streak
    /// after this answer.
    func record(baseName: String, correct: Bool, streak: Int) {
        var stat = stats[baseName] ?? StructureStat()
        stat.seen += 1
        if correct {
            stat.correct += 1
            totalCorrect += 1
            reviewQueue.removeAll { $0 == baseName }
        } else {
            stat.wrong += 1
        }
        stats[baseName] = stat
        totalAnswered += 1
        bestStreak = max(bestStreak, streak)
        save()
    }

    /// Learn mode: queue a structure to come up first in the next quiz.
    func flagForReview(_ baseName: String) {
        guard !reviewQueue.contains(baseName) else { return }
        reviewQueue.append(baseName)
        save()
    }

    var accuracy: Double { totalAnswered == 0 ? 0 : Double(totalCorrect) / Double(totalAnswered) }

    /// Structures you miss most often (seen a few times, with at least one miss),
    /// worst accuracy first. Used to nudge study focus.
    func weakestStructures(limit: Int = 3) -> [String] {
        stats
            .filter { $0.value.seen >= 2 && $0.value.wrong > 0 }
            .sorted { $0.value.accuracy < $1.value.accuracy }
            .prefix(limit)
            .map { $0.key }
    }

    // MARK: Persistence

    private struct Persisted: Codable {
        var stats: [String: StructureStat]
        var bestStreak: Int
        var totalAnswered: Int
        var totalCorrect: Int
        /// Optional so blobs saved before Learn-mode review existed still decode.
        var reviewQueue: [String]?
    }

    private func save() {
        let snapshot = Persisted(
            stats: stats,
            bestStreak: bestStreak,
            totalAnswered: totalAnswered,
            totalCorrect: totalCorrect,
            reviewQueue: reviewQueue
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(Persisted.self, from: data)
        else { return }
        stats = snapshot.stats
        bestStreak = snapshot.bestStreak
        totalAnswered = snapshot.totalAnswered
        totalCorrect = snapshot.totalCorrect
        reviewQueue = snapshot.reviewQueue ?? []
    }
}
