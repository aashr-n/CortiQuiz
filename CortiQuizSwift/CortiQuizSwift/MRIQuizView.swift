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
    var score = 0
    var total = 0
    var showingFeedback = false
    var isLoading = true
    var slicePosition: Float = 0.5
    var targetColor: Color = .white
    var miniBrainScene = SCNScene()
    var activeAxis: MRIAxis = .axial

    // Session
    let sessionLength = 10
    var questionsThisSession = 0
    var sessionComplete = false
    var missedThisSession: [String] = []

    private var allNodes: [(node: SCNNode, structure: BrainStructure)] = []
    private var quizCandidatesByAxis: [MRIAxis: [TargetCandidate]] = [:]
    private var miniNodes: [String: SCNNode] = [:]
    private var mriScene: SCNScene?
    private var renderer: SCNRenderer?
    private var bounds = MiniBrainBuilder.Bounds()
    private var setupStarted = false
    private var currentTargetIndex: Int = -1
    private var lastTargetIndex: Int = -1
    private var slicePlaneNode: SCNNode?

    nonisolated static let highlightBright = UIColor.white
    nonisolated static let highlightDim = UIColor(red: 0.0, green: 0.82, blue: 0.78, alpha: 1.0)

    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true

        Task.detached { [weak self] in
            let loaded = BrainSceneLoader.load { node, s in
                node.installClipShader(color: UIColor(s.color))
            }
            let miniResult = MiniBrainBuilder.build(structures: loaded.structures, bounds: loaded.bounds)

            // Classify quiz-able slices for every axis (mesh parsing is cached across axes).
            var candidatesByAxis: [MRIAxis: [TargetCandidate]] = [:]
            for axis in MRIAxis.allCases {
                var classifyEntries: [(nodeIndex: Int, structure: BrainStructure, axisMin: Float, axisMax: Float)] = []
                for (idx, entry) in loaded.ordered.enumerated() {
                    let (bmin, bmax) = entry.node.boundingBox
                    let lo: Float, hi: Float
                    switch axis {
                    case .axial:    lo = bmin.z; hi = bmax.z
                    case .coronal:  lo = bmin.y; hi = bmax.y
                    case .sagittal: lo = bmin.x; hi = bmax.x
                    }
                    classifyEntries.append((nodeIndex: idx, structure: entry.structure, axisMin: lo, axisMax: hi))
                }
                candidatesByAxis[axis] = OBJMeshParser.classifyQuizTargets(entries: classifyEntries, axis: axis)
            }
            let finalCandidatesByAxis = candidatesByAxis

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.mriScene = loaded.scene
                self.miniBrainScene = miniResult.scene
                self.allNodes = loaded.ordered
                self.quizCandidatesByAxis = finalCandidatesByAxis
                self.miniNodes = miniResult.nodeMap
                self.bounds = loaded.bounds
                self.slicePlaneNode = miniResult.planeNode
                self.setupRenderer()
                self.startNewSession()
            }
        }
    }

    private func setupRenderer() {
        guard let scene = mriScene else { return }

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 90
        camera.zNear = 1
        camera.zFar = 2000
        let camNode = SCNNode()
        camNode.camera = camera
        camNode.name = "mriQuizCamera"
        MRISlicing.orientCamera(camNode, for: .axial)
        scene.rootNode.addChildNode(camNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1000
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let r = SCNRenderer(device: nil, options: nil)
        r.scene = scene
        r.pointOfView = camNode
        self.renderer = r
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
        guard !allNodes.isEmpty else {
            isLoading = false
            return
        }

        if questionsThisSession >= sessionLength {
            sessionComplete = true
            return
        }

        selectedAnswer = nil
        showingFeedback = false
        isLoading = true

        let availableAxes = MRIAxis.allCases.filter { !(quizCandidatesByAxis[$0]?.isEmpty ?? true) }
        guard let pick = pickQuestion(from: availableAxes) else {
            isLoading = false
            return
        }
        lastTargetIndex = pick.candidate.nodeIndex
        activeAxis = pick.axis

        let targetIdx = pick.candidate.nodeIndex
        currentTargetIndex = targetIdx
        let target = allNodes[targetIdx].structure

        let (lo, hi) = MRISlicing.extent(bounds, for: pick.axis)
        slicePosition = (pick.slice.coord - lo) / max(hi - lo, 0.0001)
        correctAnswer = target.baseName
        targetColor = Color(red: 0.0, green: 0.9, blue: 0.85)

        let pool = (quizCandidatesByAxis[pick.axis] ?? []).map { allNodes[$0.nodeIndex].structure }
        options = QuizOptionBuilder.makeOptions(target: target, pool: pool)

        resetMiniBrain()

        if let cam = mriScene?.rootNode.childNode(withName: "mriQuizCamera", recursively: false) {
            MRISlicing.orientCamera(cam, for: pick.axis)
        }
        slicePlaneNode?.eulerAngles = MRISlicing.planeEuler(for: pick.axis)

        let clipCoord = pick.slice.coord
        let thickness = pick.slice.thickness
        let viewClipZ = MRISlicing.viewClip(forCoord: clipCoord)

        // Bright frame: target white, everything else dimmed.
        for (i, entry) in allNodes.enumerated() {
            let color = i == targetIdx ? Self.highlightBright : Self.dimmedColor(UIColor(entry.structure.color))
            entry.node.updateDiffuseColor(color)
            entry.node.updateClipUniforms(viewClipZ: viewClipZ, thickness: thickness)
        }
        guard let renderer else { isLoading = false; return }
        let size = CGSize(width: 512, height: 512)
        sliceImageBright = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)

        // Dim frame: only the target changes color (cross-fades into a subtle pulse).
        for (i, entry) in allNodes.enumerated() where i == targetIdx {
            entry.node.updateDiffuseColor(Self.highlightDim)
        }
        sliceImageDim = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)

        slicePlaneNode?.position = MRISlicing.planePosition(forCoord: clipCoord, axis: pick.axis)
        isLoading = false
    }

    /// Pick an axis/target/slice, avoiding the immediately preceding target when possible.
    private func pickQuestion(
        from axes: [MRIAxis]
    ) -> (axis: MRIAxis, candidate: TargetCandidate, slice: SliceCandidate)? {
        var fallback: (axis: MRIAxis, candidate: TargetCandidate, slice: SliceCandidate)?
        for _ in 0..<6 {
            guard let axis = axes.randomElement(),
                  let candidates = quizCandidatesByAxis[axis],
                  let candidate = candidates.randomElement(),
                  let slice = candidate.slices.randomElement()
            else { continue }
            fallback = (axis, candidate, slice)
            if candidate.nodeIndex != lastTargetIndex { return fallback }
        }
        return fallback
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
        showFeedbackOnMiniBrain(chosen: choice)
    }

    func isCorrect(_ choice: String) -> Bool { choice == correctAnswer }

    private nonisolated static func dimmedColor(_ color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * 0.2, green: g * 0.2, blue: b * 0.2, alpha: 0.4)
    }

    private func showFeedbackOnMiniBrain(chosen: String) {
        guard currentTargetIndex >= 0 && currentTargetIndex < allNodes.count else { return }
        let correctID = allNodes[currentTargetIndex].structure.id
        let wrongID: String? = (chosen != correctAnswer)
            ? allNodes.first(where: { $0.structure.baseName == chosen })?.structure.id
            : nil

        for (id, node) in miniNodes {
            if id == correctID {
                node.applyColor(UIColor(red: 0.2, green: 0.9, blue: 0.3, alpha: 0.9))
            } else if let wid = wrongID, id == wid {
                node.applyColor(UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.9))
            }
        }
    }

    private func resetMiniBrain() {
        let gray = UIColor(white: 0.7, alpha: 0.35)
        for (_, node) in miniNodes {
            node.applyColor(gray)
        }
    }

    func resetForReentry() {
        setupStarted = false
    }
}

// MARK: - MRI Quiz View

struct MRIQuizView: View {
    @State private var vm = MRIQuizViewModel()
    @State private var pulsePhase = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if vm.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Loading MRI quiz…")
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
                                Image(uiImage: imgDim)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(8)
                            }

                            if let imgBright = vm.sliceImageBright {
                                Image(uiImage: imgBright)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(8)
                                    .opacity(pulsePhase ? 1.0 : 0.0)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Theme.bgCardStroke, lineWidth: 1)
                        )
                        .accessibilityLabel("\(vm.activeAxis.title) MRI slice with one region pulsing. Identify it.")

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
                                .fill(vm.targetColor)
                                .frame(width: 10, height: 10)
                                .shadow(color: vm.targetColor.opacity(0.8), radius: 4)
                            Text("Identify the highlighted region")
                                .font(Theme.headingFont)
                                .foregroundColor(Theme.textPrimary)
                        }

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
                                .background(answerBg(option))
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(vm.showingFeedback)
                        }

                        if vm.showingFeedback {
                            Button("Next →") {
                                pulsePhase = false
                                vm.nextQuestion()
                                startPulse()
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
                    onPlayAgain: {
                        pulsePhase = false
                        vm.startNewSession()
                        startPulse()
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.sessionComplete)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            vm.setup()
            startPulse()
        }
        .onDisappear { vm.resetForReentry() }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulsePhase = true
        }
    }

    private func answerBg(_ option: String) -> Color {
        guard vm.showingFeedback else { return Theme.bgCard }
        if vm.isCorrect(option) { return Theme.correct.opacity(0.3) }
        if vm.selectedAnswer == option && !vm.isCorrect(option) {
            return Theme.incorrect.opacity(0.4)
        }
        return Color.white.opacity(0.05)
    }
}
