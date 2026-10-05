import SwiftUI
import SceneKit

// MARK: - MRI Quiz ViewModel

@MainActor @Observable
final class MRIQuizViewModel {
    var sliceImageBright: UIImage?
    var sliceImageDim: UIImage?
    var options: [String] = []
    var correctAnswer: String = ""
    var selectedAnswer: String?
    var showingFeedback = false
    var session = QuizSession()
    var sessionComplete = false
    var isLoading = true
    var loadFailed = false
    /// True while the next question's slice renders; "Next" is disabled meanwhile.
    var isPreparing = false
    var slicePosition: Float = 0.5
    var miniBrainScene = SCNScene()
    var activeAxis: MRIAxis = .axial

    /// Index-aligned with `sliceRenderer.nodes`.
    private var structures: [BrainStructure] = []
    private var indexByID: [String: Int] = [:]
    private var candidatesByAxis: [MRIAxis: [TargetCandidate]] = [:]
    /// Every visible (axis, slice set) for a name, across both hemispheres.
    private var candidatesByBaseName: [String: [(axis: MRIAxis, candidate: TargetCandidate)]] = [:]
    private var quizBaseNames: [String] = []
    /// Each structure's atlas color, darkened, for non-target regions.
    private var dimmedColors: [UIColor] = []
    private var miniNodes: [String: SCNNode] = [:]
    private var sliceRenderer: SliceRenderer?
    private var bounds = MiniBrainBounds()
    private var slicePlaneNode: SCNNode?
    private var currentTargetID: String?
    private var hasLoaded = false

    /// Builds the scenes and finds quiz-worthy slices off the main actor. Runs from
    /// SwiftUI's `.task`, so leaving the screen mid-load cancels it.
    func load() async {
        guard !hasLoaded else { return }
        let assets = await Background.run {
            let loaded = BrainSceneLoader.load { node, s in
                node.installClipShader(color: UIColor(s.color))
            }
            let mini = MiniBrainBuilder.build(structures: loaded.structures, bounds: loaded.bounds)
            let candidates = SliceCandidateCache.shared.candidates {
                SliceClassifier.classify(loaded.ordered)
            }
            let renderer = SliceRenderer(scene: loaded.scene, nodes: loaded.ordered.map(\.node))
            return (loaded: loaded, mini: mini, candidates: candidates, renderer: renderer)
        }
        guard !Task.isCancelled, let candidates = assets.candidates else { return }
        hasLoaded = true

        structures = assets.loaded.structures
        indexByID = Dictionary(uniqueKeysWithValues: structures.enumerated().map { ($1.id, $0) })
        candidatesByAxis = candidates
        var byName: [String: [(axis: MRIAxis, candidate: TargetCandidate)]] = [:]
        for (axis, list) in candidates {
            for candidate in list {
                guard let i = indexByID[candidate.structureID] else { continue }
                byName[structures[i].baseName, default: []].append((axis, candidate))
            }
        }
        candidatesByBaseName = byName
        quizBaseNames = byName.keys.sorted()
        guard !quizBaseNames.isEmpty else {
            loadFailed = true
            isLoading = false
            return
        }

        dimmedColors = structures.map { SceneColors.mriDimmed(UIColor($0.color)) }
        miniBrainScene = assets.mini.scene
        miniNodes = assets.mini.nodeMap
        slicePlaneNode = assets.mini.planeNode
        bounds = assets.loaded.bounds
        sliceRenderer = assets.renderer
        startNewSession()
    }

    func startNewSession() {
        session = QuizSession()
        sessionComplete = false
        nextQuestion()
    }

    /// Picks the next target, renders its slice on the render queue, then swaps the slice,
    /// answers, and mini-brain state in together so they never disagree.
    func nextQuestion() {
        guard !session.isFinished else {
            sessionComplete = true
            return
        }
        guard !isPreparing, let renderer = sliceRenderer, let pick = pickQuestion() else { return }
        isPreparing = true

        let target = structures[pick.index]
        let targetIndex = pick.index
        let axis = pick.axis
        let slice = pick.slice
        let dimmed = dimmedColors

        Task {
            let frames = await renderer.run { r in
                r.orient(axis)
                r.setSlice(coord: slice.coord, thickness: slice.thickness)
                // Bright frame: target white, everything else dimmed.
                for (i, node) in r.nodes.enumerated() {
                    node.updateDiffuseColor(i == targetIndex ? SceneColors.mriTarget : dimmed[i])
                }
                let bright = r.snapshot()
                // Dim frame: only the target changes color (cross-fades into a pulse).
                r.nodes[targetIndex].updateDiffuseColor(SceneColors.mriTargetDim)
                return (bright: bright, dim: r.snapshot())
            }
            guard let frames else { return }

            selectedAnswer = nil
            showingFeedback = false
            activeAxis = axis
            let (lo, hi) = MRISlicing.extent(bounds, for: axis)
            slicePosition = (slice.coord - lo) / max(hi - lo, 0.0001)
            currentTargetID = target.id
            correctAnswer = target.baseName
            options = QuizOptionBuilder.makeOptions(target: target, pool: pool(for: axis))
            sliceImageBright = frames.value.bright
            sliceImageDim = frames.value.dim

            resetMiniBrain()
            slicePlaneNode?.eulerAngles = MRISlicing.planeEuler(for: axis)
            slicePlaneNode?.position = MRISlicing.planePosition(forCoord: slice.coord, axis: axis)
            isPreparing = false
            isLoading = false
        }
    }

    /// Choose a target by name (flagged / weak / unasked first), then a random hemisphere,
    /// axis, and slice where it's visible.
    private func pickQuestion() -> (axis: MRIAxis, index: Int, slice: SliceCandidate)? {
        let store = ProgressStore.shared
        guard let base = QuizTargetPicker.pick(
                  from: quizBaseNames,
                  flagged: store.reviewQueue,
                  weak: store.weakestStructures(limit: 8),
                  exclude: session.asked
              ),
              let choice = candidatesByBaseName[base]?.randomElement(),
              let slice = choice.candidate.slices.randomElement(),
              let index = indexByID[choice.candidate.structureID]
        else { return nil }
        session.markAsked(base)
        return (choice.axis, index, slice)
    }

    /// Distractors come from structures that are also visible on this axis.
    private func pool(for axis: MRIAxis) -> [BrainStructure] {
        (candidatesByAxis[axis] ?? []).compactMap { indexByID[$0.structureID].map { structures[$0] } }
    }

    func answer(_ choice: String) {
        guard !showingFeedback, !isPreparing else { return }
        selectedAnswer = choice
        showingFeedback = true

        let correct = choice == correctAnswer
        session.record(correctAnswer: correctAnswer, wasCorrect: correct)
        ProgressStore.shared.record(baseName: correctAnswer, correct: correct, streak: session.streak)
        if correct { Theme.successHaptic() } else { Theme.errorHaptic() }
        showFeedbackOnMiniBrain(chosen: choice)
    }

    private func showFeedbackOnMiniBrain(chosen: String) {
        guard let correctID = currentTargetID else { return }
        // Like Normal Mode, a wrong pick lights up both hemispheres of that structure.
        let wrongIDs: Set<String> = chosen == correctAnswer
            ? []
            : Set(structures.filter { $0.baseName == chosen }.map(\.id))

        for (id, node) in miniNodes {
            if id == correctID {
                node.applyColor(SceneColors.correct.withAlphaComponent(0.9))
            } else if wrongIDs.contains(id) {
                node.applyColor(SceneColors.incorrect.withAlphaComponent(0.9))
            }
        }
    }

    private func resetMiniBrain() {
        for node in miniNodes.values {
            node.applyColor(SceneColors.miniBrain)
        }
    }
}

// MARK: - MRI Quiz View

struct MRIQuizView: View {
    @State private var vm = MRIQuizViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let targetDot = Color(SceneColors.mriTargetDim)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if vm.isLoading || vm.loadFailed {
                LoadingStateView(message: "Loading MRI quiz…", failed: vm.loadFailed)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        ScoreLabel(score: vm.session.score, total: vm.session.answered)
                        Spacer()
                        Text("\(vm.activeAxis.title) · \(Int(vm.slicePosition * 100))%")
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    ZStack(alignment: .bottomLeading) {
                        ZStack {
                            Color(white: 0.05)

                            if let imgDim = vm.sliceImageDim {
                                sliceImage(imgDim)
                            }

                            if let imgBright = vm.sliceImageBright {
                                if reduceMotion {
                                    // Static highlight instead of a pulse.
                                    sliceImage(imgBright)
                                } else {
                                    sliceImage(imgBright)
                                        .phaseAnimator([false, true]) { content, bright in
                                            content.opacity(bright ? 1 : 0)
                                        } animation: { _ in
                                            .easeInOut(duration: 0.8)
                                        }
                                }
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Theme.bgCardStroke, lineWidth: 1)
                        )
                        .accessibilityLabel("\(vm.activeAxis.title) MRI slice with one region highlighted. Identify it.")

                        MiniBrainView(scene: vm.miniBrainScene)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.bgCardStroke, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
                            .padding(10)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal)

                    Spacer().frame(height: 12)

                    VStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Self.targetDot)
                                .frame(width: 10, height: 10)
                                .shadow(color: Self.targetDot.opacity(0.8), radius: 4)
                            Text("Identify the highlighted region")
                                .font(Theme.headingFont)
                                .foregroundColor(Theme.textPrimary)
                        }

                        AnswerOptionsView(
                            options: vm.options,
                            correctAnswer: vm.correctAnswer,
                            selectedAnswer: vm.selectedAnswer,
                            showingFeedback: vm.showingFeedback,
                            nextDisabled: vm.isPreparing,
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

    private func sliceImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(8)
    }
}
