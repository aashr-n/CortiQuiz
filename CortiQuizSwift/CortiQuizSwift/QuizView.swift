import SwiftUI
import SceneKit

// MARK: - Quiz ViewModel

@MainActor @Observable
final class QuizViewModel {
    var currentTarget: BrainStructure?
    var options: [String] = []
    var correctAnswer: String = ""
    var selectedAnswer: String?
    var showingFeedback = false
    var session = QuizSession()
    var sessionComplete = false
    var scene = SCNScene()
    var isLoading = true
    var loadFailed = false
    var recenterTrigger = false
    private(set) var explodeFactor: Float = 0

    private var structures: [BrainStructure] = []
    private var structuresByID: [String: BrainStructure] = [:]
    /// Hemisphere pairs share a baseName; targets are picked by name, then by side.
    private var structuresByBaseName: [String: [BrainStructure]] = [:]
    private var baseNames: [String] = []
    private var structureNodes: [String: SCNNode] = [:]
    private var explodeLayout = ExplodeLayout()
    private var hasLoaded = false

    /// Builds the scene off the main actor. Runs from SwiftUI's `.task`, so leaving the
    /// screen mid-load cancels it and a later visit starts over.
    func load() async {
        guard !hasLoaded else { return }
        let loaded = await Background.run {
            BrainSceneLoader.load { node, _ in
                node.applyColor(SceneColors.ghost)
            }
        }
        guard !Task.isCancelled else { return }
        hasLoaded = true
        guard !loaded.structures.isEmpty else {
            loadFailed = true
            isLoading = false
            return
        }

        structures = loaded.structures
        structuresByID = Dictionary(uniqueKeysWithValues: loaded.structures.map { ($0.id, $0) })
        structuresByBaseName = Dictionary(grouping: loaded.structures, by: \.baseName)
        baseNames = structuresByBaseName.keys.sorted()
        scene = loaded.scene
        structureNodes = loaded.nodes
        explodeLayout = loaded.explodeLayout
        startNewSession()
        isLoading = false
    }

    func startNewSession() {
        session = QuizSession()
        sessionComplete = false
        nextQuestion()
    }

    func nextQuestion() {
        guard !session.isFinished else {
            sessionComplete = true
            return
        }
        guard let target = pickTarget() else { return }

        selectedAnswer = nil
        showingFeedback = false
        setExplode(0)
        currentTarget = target
        correctAnswer = target.baseName
        options = QuizOptionBuilder.makeOptions(target: target, pool: structures)
        updateNodeStates()
    }

    private func pickTarget() -> BrainStructure? {
        let store = ProgressStore.shared
        guard let base = QuizTargetPicker.pick(
            from: baseNames,
            flagged: store.reviewQueue,
            weak: store.weakestStructures(limit: 8),
            exclude: session.asked
        ) else { return nil }
        session.markAsked(base)
        return structuresByBaseName[base]?.randomElement()
    }

    func answer(_ choice: String) {
        guard !showingFeedback else { return }
        selectedAnswer = choice
        showingFeedback = true

        let correct = choice == correctAnswer
        session.record(correctAnswer: correctAnswer, wasCorrect: correct)
        ProgressStore.shared.record(baseName: correctAnswer, correct: correct, streak: session.streak)
        if correct { Theme.successHaptic() } else { Theme.errorHaptic() }
        updateNodeStates()
    }

    func setExplode(_ factor: Float) {
        explodeFactor = factor
        explodeLayout.apply(factor, to: structureNodes)
    }

    private func updateNodeStates() {
        let targetID = currentTarget?.id
        let feedback = showingFeedback
        let selected = selectedAnswer
        let selectedIsCorrect = selected == correctAnswer

        restyleNodes(structureNodes) { id in
            if id == targetID {
                return (feedback ? SceneColors.correct : SceneColors.target, 1.0)
            }
            if feedback, let selected, structuresByID[id]?.baseName == selected {
                return selectedIsCorrect
                    ? (SceneColors.pairedCorrect, SceneColors.pairedCorrectOpacity)
                    : (SceneColors.incorrect, 1.0)
            }
            return (SceneColors.ghost, SceneColors.ghostOpacity)
        }
    }
}

// MARK: - Quiz View

struct QuizView: View {
    @State private var vm = QuizViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if vm.isLoading || vm.loadFailed {
                LoadingStateView(message: "Loading quiz…", failed: vm.loadFailed)
            } else {
                VStack(spacing: 0) {
                    header

                    ZStack(alignment: .bottom) {
                        SceneKitView(scene: vm.scene, recenterTrigger: vm.recenterTrigger)
                            .frame(maxHeight: .infinity)
                            .accessibilityLabel("3D brain with one structure highlighted in red. Rotate to inspect.")

                        SceneControlsBar(
                            explodeFactor: Binding(get: { vm.explodeFactor }, set: { vm.setExplode($0) }),
                            onRecenter: { vm.recenterTrigger.toggle() }
                        )
                        .padding(12)
                    }

                    VStack(spacing: 12) {
                        Text("What structure is highlighted?")
                            .font(Theme.headingFont)
                            .foregroundColor(Theme.textPrimary)

                        AnswerOptionsView(
                            options: vm.options,
                            correctAnswer: vm.correctAnswer,
                            selectedAnswer: vm.selectedAnswer,
                            showingFeedback: vm.showingFeedback,
                            onAnswer: { vm.answer($0) },
                            onNext: { vm.nextQuestion() }
                        )
                    }
                    .bottomCard()
                }
            }

            if vm.sessionComplete {
                Color.black.opacity(0.7).ignoresSafeArea()
                QuizResultsView(
                    score: vm.session.score,
                    total: vm.session.answered,
                    bestStreak: vm.session.bestStreak,
                    missed: vm.session.missed,
                    onPlayAgain: { vm.startNewSession() }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.sessionComplete)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await vm.load() }
    }

    private var header: some View {
        HStack {
            ScoreLabel(score: vm.session.score, total: vm.session.answered)
            Spacer()
            Text("Question \(vm.session.questionNumber(showingFeedback: vm.showingFeedback)) of \(vm.session.length)")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
            if let target = vm.currentTarget, vm.showingFeedback {
                Text(target.name)
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
