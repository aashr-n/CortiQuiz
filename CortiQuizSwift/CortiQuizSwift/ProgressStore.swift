import SwiftUI

// MARK: - Progress Store

/// Lightweight, persistent learning record shared by both quiz modes.
/// Tracks per-structure accuracy (so we can surface weak spots), lifetime totals,
/// and the best answer streak. Backed by `UserDefaults` as a single JSON blob.
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
    private(set) var bestStreak: Int = 0
    private(set) var totalAnswered: Int = 0
    private(set) var totalCorrect: Int = 0
    /// Resets to 0 on a wrong answer; not persisted (best streak is what we keep).
    private(set) var currentStreak: Int = 0

    private let defaultsKey = "cortiquiz.progress.v1"

    init() { load() }

    /// Record one answered question.
    func record(baseName: String, correct: Bool) {
        var stat = stats[baseName] ?? StructureStat()
        stat.seen += 1
        if correct {
            stat.correct += 1
            currentStreak += 1
            totalCorrect += 1
            bestStreak = max(bestStreak, currentStreak)
        } else {
            stat.wrong += 1
            currentStreak = 0
        }
        stats[baseName] = stat
        totalAnswered += 1
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
    }

    private func save() {
        let snapshot = Persisted(
            stats: stats,
            bestStreak: bestStreak,
            totalAnswered: totalAnswered,
            totalCorrect: totalCorrect
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(Persisted.self, from: data)
        else { return }
        stats = snapshot.stats
        bestStreak = snapshot.bestStreak
        totalAnswered = snapshot.totalAnswered
        totalCorrect = snapshot.totalCorrect
    }
}
