import SwiftUI
import SceneKit

// MARK: - Quiz ViewModel

@MainActor @Observable
final class QuizViewModel {
    var allStructures: [BrainStructure] = []
    var brainOnlyStructures: [BrainStructure] = []
    var currentTarget: BrainStructure?
    var options: [String] = []
    var correctAnswer: String = ""
    var selectedAnswer: String?
    var score = 0
    var total = 0
    var showingFeedback = false
    var scene = SCNScene()
    var isLoading = true
    var recenterTrigger = false
    var explodeFactor: Float = 0

    // Session
    let sessionLength = 10
    var questionsThisSession = 0
    var sessionComplete = false
    var missedThisSession: [String] = []

    private var structureNodes: [String: SCNNode] = [:]
    private var structuresByID: [String: BrainStructure] = [:]
    private var originalPositions: [String: SCNVector3] = [:]
    private var brainCenter = SCNVector3Zero
    private var setupStarted = false
    private var lastTargetID: String?
    private nonisolated static let backgroundRegionColor = UIColor(white: 0.58, alpha: 1.0)
    private nonisolated static let backgroundRegionOpacity: CGFloat = 0.16
    private nonisolated static let targetRegionColor = UIColor(red: 0.96, green: 0.24, blue: 0.36, alpha: 1.0)
    private nonisolated static let pairedCorrectRegionColor = UIColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1.0)
    private nonisolated static let pairedCorrectRegionOpacity: CGFloat = 0.75

    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true

        Task.detached { [weak self] in
            let loaded = BrainSceneLoader.load { node, _ in
                node.applyColor(Self.backgroundRegionColor)
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.allStructures = loaded.allStructures
                self.brainOnlyStructures = loaded.structures
                self.structuresByID = Dictionary(uniqueKeysWithValues: loaded.structures.map { ($0.id, $0) })
                self.scene = loaded.scene
                self.structureNodes = loaded.nodes
                self.originalPositions = loaded.nodeCenters
                self.brainCenter = loaded.center
                self.startNewSession()
            }
        }
    }

    func startNewSession() {
        score = 0
        total = 0
        questionsThisSession = 0
        missedThisSession = []
        sessionComplete = false
        nextQuestion()
    }

    func nextQuestion() {
        guard !brainOnlyStructures.isEmpty else { return }

        if questionsThisSession >= sessionLength {
            sessionComplete = true
            return
        }

        selectedAnswer = nil
        showingFeedback = false
        explodeFactor = 0
        updateExplode()

        guard let target = pickTarget() else { return }
        lastTargetID = target.id
        currentTarget = target
        correctAnswer = target.baseName
        options = QuizOptionBuilder.makeOptions(target: target, pool: brainOnlyStructures)

        updateNodeStates()
        isLoading = false
    }

    /// Avoid showing the same structure twice in a row.
    private func pickTarget() -> BrainStructure? {
        guard brainOnlyStructures.count > 1 else { return brainOnlyStructures.first }
        for _ in 0..<6 {
            if let candidate = brainOnlyStructures.randomElement(), candidate.id != lastTargetID {
                return candidate
            }
        }
        return brainOnlyStructures.randomElement()
    }

    func answer(_ choice: String) {
        guard !showingFeedback else { return }
        Theme.tapHaptic()
        selectedAnswer = choice
        showingFeedback = true
        total += 1
        questionsThisSession += 1

        let correct = choice == correctAnswer
        if correct {
            score += 1
            Theme.successHaptic()
        } else {
            missedThisSession.append(correctAnswer)
            Theme.errorHaptic()
        }
        ProgressStore.shared.record(baseName: correctAnswer, correct: correct)
        updateNodeStates()
    }

    func isCorrect(_ choice: String) -> Bool { choice == correctAnswer }

    func updateExplode() {
        let factor = explodeFactor
        for (id, node) in structureNodes {
            guard let orig = originalPositions[id] else { continue }
            let dx = (orig.x - brainCenter.x) * factor
            let dy = (orig.y - brainCenter.y) * factor
            let dz = (orig.z - brainCenter.z) * factor
            node.position = SCNVector3(dx, dy, dz)
        }
    }

    func updateNodeStates() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.25

        let feedback = showingFeedback
        let selectedName = selectedAnswer
        let selectedAnswerIsCorrect = selectedName == correctAnswer

        for (id, node) in structureNodes {
            guard let s = structuresByID[id] else { continue }

            if feedback {
                if s.id == currentTarget?.id {
                    node.applyColor(UIColor(Theme.correct))
                    node.opacity = 1.0
                } else if let sel = selectedName, s.baseName == sel {
                    if selectedAnswerIsCorrect {
                        node.applyColor(Self.pairedCorrectRegionColor)
                        node.opacity = Self.pairedCorrectRegionOpacity
                    } else {
                        node.applyColor(UIColor(Theme.incorrect))
                        node.opacity = 1.0
                    }
                } else {
                    node.applyColor(Self.backgroundRegionColor)
                    node.opacity = Self.backgroundRegionOpacity
                }
            } else {
                if s.id == currentTarget?.id {
                    node.applyColor(Self.targetRegionColor)
                    node.opacity = 1.0
                } else {
                    node.applyColor(Self.backgroundRegionColor)
                    node.opacity = Self.backgroundRegionOpacity
                }
            }
        }
        SCNTransaction.commit()
    }

    func resetForReentry() {
        setupStarted = false
    }
}

// MARK: - Quiz View

struct QuizView: View {
    @State private var vm = QuizViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if vm.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Loading quiz…")
                        .foregroundColor(Theme.textSecondary)
                }
            } else {
            VStack(spacing: 0) {
                HStack {
                    Label("\(vm.score)/\(vm.total)", systemImage: "star.fill")
                        .foregroundColor(Theme.scoreGold)
                        .font(Theme.headingFont)
                        .accessibilityLabel("Score \(vm.score) of \(vm.total)")
                    Spacer()
                    Text("Question \(min(vm.questionsThisSession + (vm.showingFeedback ? 0 : 1), vm.sessionLength)) of \(vm.sessionLength)")
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

                ZStack(alignment: .bottom) {
                    SceneKitView(scene: vm.scene, recenterTrigger: vm.recenterTrigger)
                        .frame(maxHeight: .infinity)
                        .accessibilityLabel("3D brain with one structure highlighted in red. Rotate to inspect.")

                    HStack {
                        HStack {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .foregroundColor(Theme.textSecondary)
                                .font(Theme.captionFont)
                            Slider(value: Binding(
                                get: { vm.explodeFactor },
                                set: { vm.explodeFactor = $0; vm.updateExplode() }
                            ), in: 0...3)
                            .tint(Theme.accent)
                            .accessibilityLabel("Explode view")
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .foregroundColor(Theme.textSecondary)
                                .font(Theme.captionFont)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(Theme.bgSecondary.opacity(0.8))
                        .clipShape(Capsule())

                        Spacer()

                        Button {
                            vm.recenterTrigger.toggle()
                        } label: {
                            Image(systemName: "scope")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Recenter camera")
                    }
                    .padding(12)
                }

                VStack(spacing: 12) {
                    Text("What structure is highlighted?")
                        .font(Theme.headingFont)
                        .foregroundColor(Theme.textPrimary)

                    ForEach(vm.options, id: \.self) { option in
                        Button {
                            vm.answer(option)
                        } label: {
                            HStack {
                                Text(option)
                                    .font(Theme.bodyFont)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if vm.showingFeedback && vm.isCorrect(option) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Theme.correct)
                                }
                                if vm.showingFeedback && vm.selectedAnswer == option && !vm.isCorrect(option) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Theme.incorrect)
                                }
                            }
                            .padding()
                            .background(optionBackground(option))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(vm.showingFeedback)
                    }

                    if vm.showingFeedback {
                        Button("Next →") {
                            vm.nextQuestion()
                        }
                        .font(Theme.headingFont)
                        .foregroundColor(.black)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                        .transition(.scale)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Theme.bgCard)
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            }

            if vm.sessionComplete {
                Color.black.opacity(0.7).ignoresSafeArea()
                QuizResultsView(
                    score: vm.score,
                    total: vm.total,
                    bestStreak: ProgressStore.shared.bestStreak,
                    missed: Array(Set(vm.missedThisSession)).sorted(),
                    onPlayAgain: { vm.startNewSession() }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.sessionComplete)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { vm.setup() }
        .onDisappear { vm.resetForReentry() }
    }

    private func optionBackground(_ option: String) -> Color {
        guard vm.showingFeedback else { return Theme.bgCard }
        if vm.isCorrect(option) { return Theme.correct.opacity(0.3) }
        if vm.selectedAnswer == option { return Theme.incorrect.opacity(0.3) }
        return Color.white.opacity(0.05)
    }
}
