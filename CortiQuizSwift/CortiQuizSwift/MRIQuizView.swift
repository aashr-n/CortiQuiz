import SwiftUI
import SceneKit

// MARK: - MRI Quiz ViewModel

@MainActor @Observable
final class MRIQuizViewModel {
    var sliceImage: UIImage?
    var options: [String] = []
    var correctAnswer: String = ""
    var selectedAnswer: String?
    var score = 0
    var total = 0
    var showingFeedback = false
    var isLoading = true
    var slicePosition: Float = 0.5
    
    private var brainStructures: [BrainStructure] = []
    private var allNodes: [(node: SCNNode, structure: BrainStructure)] = []
    private var mriScene: SCNScene?
    private var renderer: SCNRenderer?
    private var minZ: Float = 0
    private var maxZ: Float = 0
    private var setupStarted = false
    private var currentTargetIndex: Int = -1
    
    nonisolated static let cameraZ: Float = 300
    
    // Same palette as MRI mode
    nonisolated static let regionColors: [UIColor] = [
        UIColor(red: 0.92, green: 0.82, blue: 0.62, alpha: 1.0),
        UIColor(red: 0.45, green: 0.58, blue: 0.78, alpha: 1.0),
        UIColor(red: 0.76, green: 0.52, blue: 0.62, alpha: 1.0),
        UIColor(red: 0.48, green: 0.72, blue: 0.58, alpha: 1.0),
    ]
    
    nonisolated static let highlightColor = UIColor(red: 0.1, green: 0.95, blue: 0.85, alpha: 1.0)
    
    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true
        
        Task.detached { [weak self] in
            let newScene = SCNScene()
            let structures = AtlasLoader.load()
            let brainOnly = structures.filter { $0.modelFileName != nil && $0.isBrainStructure && !$0.isGroup }
            
            var entries: [(node: SCNNode, structure: BrainStructure)] = []
            var globalMinZ: Float = .greatestFiniteMagnitude
            var globalMaxZ: Float = -.greatestFiniteMagnitude
            
            for (i, s) in brainOnly.enumerated() {
                guard let fn = s.modelFileName, let node = ModelCache.shared.node(for: fn) else { continue }
                let color = Self.regionColors[i % Self.regionColors.count]
                Self.applyMaterial(to: node, color: color)
                newScene.rootNode.addChildNode(node)
                entries.append((node: node, structure: s))
                
                let (bmin, bmax) = node.boundingBox
                globalMinZ = min(globalMinZ, bmin.z)
                globalMaxZ = max(globalMaxZ, bmax.z)
            }
            
            let finalEntries = entries
            let finalMinZ = globalMinZ
            let finalMaxZ = globalMaxZ
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.mriScene = newScene
                self.brainStructures = brainOnly
                self.allNodes = finalEntries
                self.minZ = finalMinZ
                self.maxZ = finalMaxZ
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
        guard !allNodes.isEmpty else { return }
        selectedAnswer = nil
        showingFeedback = false
        isLoading = true
        
        // Pick a random structure and find a slice where it's visible
        let targetIdx = Int.random(in: 0..<allNodes.count)
        currentTargetIndex = targetIdx
        let targetNode = allNodes[targetIdx].node
        let target = allNodes[targetIdx].structure
        
        // Find Z range of target and pick a slice in its range
        let (bmin, bmax) = targetNode.boundingBox
        let targetSlice = Float.random(in: bmin.z...bmax.z)
        slicePosition = (targetSlice - minZ) / (maxZ - minZ)
        
        correctAnswer = target.baseName
        
        // Generate options
        var optionSet = Set<String>([target.baseName])
        let shuffled = brainStructures.shuffled()
        for s in shuffled {
            if optionSet.count >= 4 { break }
            if !optionSet.contains(s.baseName) { optionSet.insert(s.baseName) }
        }
        options = Array(optionSet).shuffled()
        
        // Render: highlight target, normal colors for rest
        let clipZ = targetSlice
        let thickness: Float = 2.0
        let viewClipZ = clipZ - Self.cameraZ
        
        for (i, entry) in allNodes.enumerated() {
            let color = (i == targetIdx) ? Self.highlightColor : Self.regionColors[i % Self.regionColors.count]
            applyClipShader(to: entry.node, viewClipZ: viewClipZ, thickness: thickness, color: color)
        }
        
        guard let renderer else { isLoading = false; return }
        let size = CGSize(width: 512, height: 512)
        sliceImage = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        isLoading = false
    }
    
    func answer(_ choice: String) {
        guard !showingFeedback else { return }
        selectedAnswer = choice
        showingFeedback = true
        total += 1
        if choice == correctAnswer { score += 1 }
    }
    
    func isCorrect(_ choice: String) -> Bool { choice == correctAnswer }
    
    private func applyClipShader(to node: SCNNode, viewClipZ: Float, thickness: Float, color: UIColor) {
        if let geom = node.geometry {
            for mat in geom.materials {
                mat.shaderModifiers = [
                    .fragment: """
                    float vz = _surface.position.z;
                    if (vz > \(viewClipZ) || vz < \(viewClipZ - thickness)) {
                        discard_fragment();
                    }
                    """
                ]
                mat.isDoubleSided = true
                mat.diffuse.contents = color
            }
        }
        for child in node.childNodes {
            applyClipShader(to: child, viewClipZ: viewClipZ, thickness: thickness, color: color)
        }
    }
    
    func resetForReentry() {
        setupStarted = false
    }
    
    private nonisolated static func applyMaterial(to node: SCNNode, color: UIColor) {
        if let geom = node.geometry {
            for mat in geom.materials {
                mat.diffuse.contents = color
                mat.isDoubleSided = true
            }
        }
        for child in node.childNodes { applyMaterial(to: child, color: color) }
    }
}

// MARK: - MRI Quiz View

struct MRIQuizView: View {
    @State private var vm = MRIQuizViewModel()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if vm.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Loading MRI quiz…")
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
                        Text("Slice: \(Int(vm.slicePosition * 100))%")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    // MRI slice image
                    ZStack {
                        Color(white: 0.05)
                        
                        if let img = vm.sliceImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(8)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.horizontal)
                    
                    Spacer().frame(height: 12)
                    
                    // Question area
                    VStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 0.1, green: 0.95, blue: 0.85))
                                .frame(width: 10, height: 10)
                            Text("Identify the highlighted region")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        
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
                            .background(Color(hex: "10b981"))
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
            }
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
