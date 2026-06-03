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
    
    private var structureNodes: [String: SCNNode] = [:]
    private var originalPositions: [String: SCNVector3] = [:]
    private var brainCenter = SCNVector3Zero
    private var setupStarted = false
    
    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true
        
        Task.detached { [weak self] in
            let loadedAll = AtlasLoader.load()
            let loadedBrainOnly = loadedAll.filter { $0.modelFileName != nil && $0.isBrainStructure && !$0.isGroup }
            
            let newScene = SCNScene()
            var nodes: [String: SCNNode] = [:]
            var positions: [String: SCNVector3] = [:]
            var totalX: Float = 0, totalY: Float = 0, totalZ: Float = 0
            var count: Float = 0
            
            for s in loadedBrainOnly {
                guard let fn = s.modelFileName, let node = ModelCache.shared.node(for: fn) else { continue }
                node.applyColor(UIColor(s.color))
                node.name = s.id
                newScene.rootNode.addChildNode(node)
                nodes[s.id] = node
                
                let (min, max) = node.boundingBox
                let cx = (min.x + max.x) / 2
                let cy = (min.y + max.y) / 2
                let cz = (min.z + max.z) / 2
                positions[s.id] = SCNVector3(cx, cy, cz)
                totalX += cx; totalY += cy; totalZ += cz
                count += 1
            }
            
            let center = count > 0
                ? SCNVector3(totalX / count, totalY / count, totalZ / count)
                : SCNVector3Zero
            
            let finalNodes = nodes
            let finalPositions = positions
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.allStructures = loadedAll
                self.brainOnlyStructures = loadedBrainOnly
                self.scene = newScene
                self.structureNodes = finalNodes
                self.originalPositions = finalPositions
                self.brainCenter = center
                self.nextQuestion()
            }
        }
    }
    
    func nextQuestion() {
        guard !brainOnlyStructures.isEmpty else { return }
        
        selectedAnswer = nil
        showingFeedback = false
        explodeFactor = 0
        updateExplode()
        
        guard let target = brainOnlyStructures.randomElement() else { return }
        currentTarget = target
        correctAnswer = target.baseName
        
        var optionSet = Set<String>([target.baseName])
        let shuffled = brainOnlyStructures.shuffled()
        for s in shuffled {
            if optionSet.count >= 4 { break }
            if !optionSet.contains(s.baseName) {
                optionSet.insert(s.baseName)
            }
        }
        options = Array(optionSet).shuffled()
        
        updateNodeStates()
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
        
        for (id, node) in structureNodes {
            guard let s = brainOnlyStructures.first(where: { $0.id == id }) else { continue }
            
            if feedback {
                if s.id == currentTarget?.id {
                    node.applyColor(UIColor(Theme.correct))
                    node.opacity = 1.0
                } else if let sel = selectedName, s.baseName == sel {
                    node.applyColor(UIColor(Theme.incorrect))
                    node.opacity = 1.0
                } else {
                    node.applyColor(UIColor(s.color))
                    node.opacity = 0.15
                }
            } else {
                if s.id == currentTarget?.id {
                    node.applyColor(UIColor.systemCyan)
                    node.opacity = 1.0
                } else {
                    node.applyColor(UIColor(s.color))
                    node.opacity = 0.15
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
                    Spacer()
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
        }
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
