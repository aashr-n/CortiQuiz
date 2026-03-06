import SwiftUI
import SceneKit

// MARK: - Quiz ViewModel

@MainActor @Observable
final class QuizViewModel {
    var allStructures: [BrainStructure] = []
    var brainOnlyStructures: [BrainStructure] = [] // structures with model files, brain-only
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
    private var setupStarted = false
    
    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true
        
        Task.detached { [weak self] in
            let loadedAll = AtlasLoader.load()
            let loadedBrainOnly = loadedAll.filter { $0.modelFileName != nil && $0.isBrainStructure && !$0.isGroup }
            
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.allStructures = loadedAll
                self.brainOnlyStructures = loadedBrainOnly
                self.nextQuestion()
            }
        }
    }
    
    func nextQuestion() {
        guard !brainOnlyStructures.isEmpty else { return }
        
        selectedAnswer = nil
        showingFeedback = false
        isLoading = true
        
        let target = brainOnlyStructures.randomElement()!
        currentTarget = target
        correctAnswer = target.baseName
        
        // Generate 3 distractors with different base names
        var optionSet = Set<String>([target.baseName])
        let shuffled = brainOnlyStructures.shuffled()
        for s in shuffled {
            if optionSet.count >= 4 { break }
            if !optionSet.contains(s.baseName) {
                optionSet.insert(s.baseName)
            }
        }
        let generatedOptions = Array(optionSet).shuffled()
        
        Task.detached { [weak self] in
            let newScene = Self.buildSceneNode(target: target)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.options = generatedOptions
                self.scene = newScene
                self.isLoading = false
            }
        }
    }
    
    func answer(_ choice: String) {
        guard !showingFeedback else { return }
        selectedAnswer = choice
        showingFeedback = true
        total += 1
        if choice == correctAnswer { score += 1 }
    }
    
    func isCorrect(_ choice: String) -> Bool { choice == correctAnswer }
    
    private nonisolated static func buildSceneNode(target: BrainStructure) -> SCNScene {
        let newScene = SCNScene()
        
        // Load ghost brain (white matter hemispheres as transparent reference)
        let ghostFiles = ["Model_2_white_matter_of_left_cerebral_hemisphere.obj",
                          "Model_41_white_matter_of_right_cerebral_hemisphere.obj"]
        for gf in ghostFiles {
            if let node = ModelCache.shared.node(for: gf) {
                node.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.06)
                node.geometry?.firstMaterial?.transparency = 0.06
                node.geometry?.firstMaterial?.isDoubleSided = true
                applyTransparency(to: node, alpha: 0.06)
                newScene.rootNode.addChildNode(node)
            }
        }
        
        // Load target structure highlighted in red
        if let modelFile = target.modelFileName, let node = ModelCache.shared.node(for: modelFile) {
            let red = UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0)
            applyColor(to: node, color: red)
            node.name = "target"
            newScene.rootNode.addChildNode(node)
        }
        
        return newScene
    }
    
    private nonisolated static func applyTransparency(to node: SCNNode, alpha: CGFloat) {
        if let geom = node.geometry {
            for mat in geom.materials {
                mat.diffuse.contents = UIColor.white.withAlphaComponent(alpha)
                mat.transparency = alpha
                mat.isDoubleSided = true
                mat.blendMode = .alpha
            }
        }
        for child in node.childNodes { applyTransparency(to: child, alpha: alpha) }
    }
    
    private nonisolated static func applyColor(to node: SCNNode, color: UIColor) {
        if let geom = node.geometry {
            for mat in geom.materials {
                mat.diffuse.contents = color
                mat.isDoubleSided = true
            }
        }
        for child in node.childNodes { applyColor(to: child, color: color) }
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
                        .foregroundColor(.gray)
                }
            } else {
            VStack(spacing: 0) {
                // Score bar
                HStack {
                    Label("\(vm.score)/\(vm.total)", systemImage: "star.fill")
                        .foregroundColor(Color(hex: "fbbf24"))
                        .font(.headline)
                    Spacer()
                    if let target = vm.currentTarget, vm.showingFeedback {
                        Text(target.name)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                // 3D View
                ZStack(alignment: .bottomTrailing) {
                    SceneKitView(scene: vm.scene, recenterTrigger: vm.recenterTrigger)
                        .frame(maxHeight: .infinity)
                    
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
                    .padding(12)
                }
                
                // Question area
                VStack(spacing: 12) {
                    Text("What structure is highlighted?")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    ForEach(vm.options, id: \.self) { option in
                        Button {
                            vm.answer(option)
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if vm.showingFeedback && vm.isCorrect(option) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                                if vm.showingFeedback && vm.selectedAnswer == option && !vm.isCorrect(option) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
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
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(Color(hex: "8b5cf6"))
                        .clipShape(Capsule())
                        .transition(.scale)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.08))
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            } // End if-else
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { vm.setup() }
        .onDisappear { vm.resetForReentry() }
    }
    
    private func optionBackground(_ option: String) -> Color {
        guard vm.showingFeedback else { return Color.white.opacity(0.1) }
        if vm.isCorrect(option) { return Color.green.opacity(0.3) }
        if vm.selectedAnswer == option { return Color.red.opacity(0.3) }
        return Color.white.opacity(0.05)
    }
}
