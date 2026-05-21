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
    }
    
    func isCorrect(_ choice: String) -> Bool { choice == correctAnswer }
    
    private nonisolated static func buildSceneNode(target: BrainStructure) -> SCNScene {
        let newScene = SCNScene()
        
        let ghostFiles = ["Model_2_white_matter_of_left_cerebral_hemisphere.obj",
                          "Model_41_white_matter_of_right_cerebral_hemisphere.obj"]
        for gf in ghostFiles {
            if let node = ModelCache.shared.node(for: gf) {
                node.applyTransparency(alpha: 0.06)
                newScene.rootNode.addChildNode(node)
            }
        }
        
        if let modelFile = target.modelFileName, let node = ModelCache.shared.node(for: modelFile) {
            let red = UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0)
            node.applyColor(red)
            node.name = "target"
            newScene.rootNode.addChildNode(node)
        }
        
        return newScene
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
