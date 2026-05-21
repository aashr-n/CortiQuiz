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
    
    private var allNodes: [(node: SCNNode, structure: BrainStructure)] = []
    private var quizCandidates: [TargetCandidate] = []
    private var miniNodes: [String: SCNNode] = [:]
    private var mriScene: SCNScene?
    private var renderer: SCNRenderer?
    private var minZ: Float = 0
    private var maxZ: Float = 0
    private var setupStarted = false
    private var currentTargetIndex: Int = -1
    private var slicePlaneNode: SCNNode?
    
    nonisolated static let cameraZ: Float = 300
    nonisolated static let highlightBright = UIColor.white
    nonisolated static let highlightDim = UIColor(red: 0.0, green: 0.82, blue: 0.78, alpha: 1.0)
    
    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true
        
        Task.detached { [weak self] in
            let newScene = SCNScene()
            let structures = AtlasLoader.load()
            let brainOnly = structures.filter { $0.modelFileName != nil && $0.isBrainStructure && !$0.isGroup }
            
            var entries: [(node: SCNNode, structure: BrainStructure)] = []
            var classifyEntries: [(nodeIndex: Int, structure: BrainStructure, minZ: Float, maxZ: Float)] = []
            var globalBounds = MiniBrainBuilder.Bounds()
            
            for s in brainOnly {
                guard let fn = s.modelFileName, let node = ModelCache.shared.node(for: fn) else { continue }
                let color = UIColor(s.color)
                node.installClipShader(color: color)
                newScene.rootNode.addChildNode(node)
                
                let (bmin, bmax) = node.boundingBox
                globalBounds.minX = min(globalBounds.minX, bmin.x)
                globalBounds.maxX = max(globalBounds.maxX, bmax.x)
                globalBounds.minY = min(globalBounds.minY, bmin.y)
                globalBounds.maxY = max(globalBounds.maxY, bmax.y)
                globalBounds.minZ = min(globalBounds.minZ, bmin.z)
                globalBounds.maxZ = max(globalBounds.maxZ, bmax.z)
                
                let idx = entries.count
                entries.append((node: node, structure: s))
                classifyEntries.append((nodeIndex: idx, structure: s, minZ: bmin.z, maxZ: bmax.z))
            }
            
            let miniResult = MiniBrainBuilder.build(
                structures: brainOnly,
                bounds: globalBounds
            )
            
            let targetCandidates = OBJMeshParser.classifyQuizTargets(entries: classifyEntries)
            
            let finalEntries = entries
            let finalMinZ = globalBounds.minZ
            let finalMaxZ = globalBounds.maxZ
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.mriScene = newScene
                self.miniBrainScene = miniResult.scene
                self.allNodes = finalEntries
                self.quizCandidates = targetCandidates
                self.miniNodes = miniResult.nodeMap
                self.minZ = finalMinZ
                self.maxZ = finalMaxZ
                self.slicePlaneNode = miniResult.planeNode
                self.setupRenderer()
                self.nextQuestion()
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
        camNode.position = SCNVector3(0, 0, Self.cameraZ)
        camNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, -1, 0), localFront: SCNVector3(0, 0, -1))
        camNode.name = "mriQuizCamera"
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
    
    func nextQuestion() {
        guard !allNodes.isEmpty, !quizCandidates.isEmpty else {
            isLoading = false
            return
        }
        selectedAnswer = nil
        showingFeedback = false
        isLoading = true
        
        guard let targetCandidate = quizCandidates.randomElement(),
              let sliceCandidate = targetCandidate.slices.randomElement()
        else {
            isLoading = false
            return
        }
        
        let targetIdx = targetCandidate.nodeIndex
        currentTargetIndex = targetIdx
        let target = allNodes[targetIdx].structure
        
        slicePosition = (sliceCandidate.z - minZ) / (maxZ - minZ)
        correctAnswer = target.baseName
        targetColor = Color(red: 0.0, green: 0.9, blue: 0.85)
        
        var optionSet = Set<String>([target.baseName])
        let quizStructures = quizCandidates.map { allNodes[$0.nodeIndex].structure }
        for s in quizStructures.shuffled() {
            if optionSet.count >= 4 { break }
            if !optionSet.contains(s.baseName) { optionSet.insert(s.baseName) }
        }
        options = Array(optionSet).shuffled()
        
        resetMiniBrain()
        
        let clipZ = sliceCandidate.z
        let thickness = sliceCandidate.thickness
        let viewClipZ = clipZ - Self.cameraZ
        
        // Bright frame
        for (i, entry) in allNodes.enumerated() {
            let color = i == targetIdx ? Self.highlightBright : Self.dimmedColor(UIColor(entry.structure.color))
            entry.node.updateDiffuseColor(color)
            entry.node.updateClipUniforms(viewClipZ: viewClipZ, thickness: thickness)
        }
        guard let renderer else { isLoading = false; return }
        let size = CGSize(width: 512, height: 512)
        sliceImageBright = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        
        // Dim frame
        for (i, entry) in allNodes.enumerated() {
            if i == targetIdx {
                entry.node.updateDiffuseColor(Self.highlightDim)
            }
        }
        sliceImageDim = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        
        slicePlaneNode?.position.z = clipZ
        isLoading = false
    }
    
    func answer(_ choice: String) {
        guard !showingFeedback else { return }
        Theme.tapHaptic()
        selectedAnswer = choice
        showingFeedback = true
        total += 1
        if choice == correctAnswer {
            score += 1
            Theme.successHaptic()
        } else {
            Theme.errorHaptic()
        }
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
                        Spacer()
                        Text("Slice: \(Int(vm.slicePosition * 100))%")
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
                        
                        MiniBrainView(scene: vm.miniBrainScene)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.bgCardStroke, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
                            .padding(10)
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
        }
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
