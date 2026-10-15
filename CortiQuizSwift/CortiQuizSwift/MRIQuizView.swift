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
    /// World coordinate (mm) of the cut along `activeAxis`.
    var sliceCoord: Float = 0
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

    /// The structure being asked about (one hemisphere of a pair).
    var currentTarget: BrainStructure? {
        currentTargetID.flatMap { indexByID[$0] }.map { structures[$0] }
    }

    /// Builds the scenes and finds quiz-worthy slices off the main actor. Runs from
    /// SwiftUI's `.task`, so leaving the screen mid-load cancels it.
    func load() async {
        guard !hasLoaded else { return }
        let assets = await Background.run {
            let loaded = BrainSceneLoader.load { _, _ in }
            let mini = MiniBrainBuilder.build(structures: loaded.structures, bounds: loaded.bounds)
            let candidates = SliceCandidateCache.shared.candidates {
                SliceClassifier.classify(loaded.ordered)
            }
            let renderer = SliceRenderer(
                scene: loaded.scene,
                nodes: loaded.ordered.map(\.node),
                colors: loaded.structures.map { UIColor($0.color) },
                center: loaded.bounds.center
            )
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

        dimmedColors = assets.renderer.baseColors.map { SceneColors.mriDimmed($0) }
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
                r.setCut(coord: slice.cutCoord)
                // Bright frame: target white, everything else dimmed.
                var colors = dimmed
                colors[targetIndex] = SceneColors.mriTarget
                r.setColors(colors)
                let bright = r.snapshot(size: MRISlicing.sharpSnapshotSize)
                // Dim frame: only the target changes color (cross-fades into a pulse).
                r.setColor(SceneColors.mriTargetDim, at: targetIndex)
                return (bright: bright, dim: r.snapshot(size: MRISlicing.sharpSnapshotSize))
            }
            guard let frames else { return }

            selectedAnswer = nil
            showingFeedback = false
            activeAxis = axis
            sliceCoord = slice.cutCoord
            currentTargetID = target.id
            correctAnswer = target.baseName
            options = QuizOptionBuilder.makeOptions(target: target, pool: pool(for: axis))
            sliceImageBright = frames.value.bright
            sliceImageDim = frames.value.dim

            resetMiniBrain()
            if let slicePlaneNode {
                MRISlicing.placePlane(slicePlaneNode, axis: axis, coord: slice.cutCoord, bounds: bounds)
            }
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
                MiniBrainBuilder.highlight(node, color: SceneColors.correct.withAlphaComponent(0.9))
            } else if wrongIDs.contains(id) {
                MiniBrainBuilder.highlight(node, color: SceneColors.incorrect.withAlphaComponent(0.9))
            }
        }
    }

    private func resetMiniBrain() {
        for node in miniNodes.values {
            MiniBrainBuilder.highlight(node, color: nil)
        }
    }
}

// MARK: - MRI Quiz View

struct MRIQuizView: View {
    @State private var vm = MRIQuizViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.stage.ignoresSafeArea()

            if vm.isLoading || vm.loadFailed {
                LoadingStateView(message: "Loading MRI quiz…", failed: vm.loadFailed)
            } else {
                StageLayout {
                    slice
                        .padding(12)
                } panel: {
                    QuizPanel(
                        prompt: "Identify the highlighted region",
                        tip: "The small brain shows where this slice is",
                        tipIcon: "cube.transparent",
                        session: vm.session,
                        options: vm.options,
                        correctAnswer: vm.correctAnswer,
                        selectedAnswer: vm.selectedAnswer,
                        showingFeedback: vm.showingFeedback,
                        detail: vm.currentTarget?.displayName,
                        nextDisabled: vm.isPreparing,
                        onAnswer: { vm.answer($0) },
                        onNext: { vm.nextQuestion() }
                    )
                }
            }
        }
        .navigationSubtitle(vm.isLoading ? "" : "Question \(vm.session.questionNumber(showingFeedback: vm.showingFeedback)) of \(vm.session.length)")
        .toolbar {
            if !vm.isLoading && !vm.loadFailed {
                ToolbarItem(placement: .topBarTrailing) {
                    ScoreLabel(score: vm.session.score, total: vm.session.answered)
                }
            }
        }
        .sessionSummary(isPresented: $vm.sessionComplete) { done in
            QuizResultsView(
                score: vm.session.score,
                total: vm.session.answered,
                bestStreak: vm.session.bestStreak,
                missed: vm.session.missed,
                onPlayAgain: { vm.startNewSession() },
                onDone: done
            )
        }
        .task { await vm.load() }
    }

    /// The slice with its target pulsing, where it sits on the mini brain, and its location.
    private var slice: some View {
        SliceFrame(axis: vm.activeAxis) {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vm.activeAxis.title) MRI slice with one region highlighted. Identify it.")
        .overlay(alignment: .bottomLeading) {
            MiniBrainView(scene: vm.miniBrainScene)
                .frame(width: 104, height: 104)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.bgCardStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
                .padding(10)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            Text("\(vm.activeAxis.title) · \(vm.activeAxis.locationLabel(vm.sliceCoord))")
                .font(Theme.captionFont)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .padding(10)
        }
    }

    private func sliceImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
    }
}
