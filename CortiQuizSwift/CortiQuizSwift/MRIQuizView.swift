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
    
    // Mini-brain scene (single gray color, with slice plane)
    var miniBrainScene = SCNScene()
    
    private var brainStructures: [BrainStructure] = []
    private var allNodes: [(node: SCNNode, structure: BrainStructure)] = []
    private var miniNodes: [String: SCNNode] = [:]
    private var mriScene: SCNScene?
    private var renderer: SCNRenderer?
    private var minZ: Float = 0
    private var maxZ: Float = 0
    private var setupStarted = false
    private var currentTargetIndex: Int = -1
    private var slicePlaneNode: SCNNode?
    
    nonisolated static let cameraZ: Float = 300
    
    // Bright highlight for pulse peak — pure white
    nonisolated static let highlightBright = UIColor.white
    // Dim highlight for pulse trough — black
    nonisolated static let highlightDim = UIColor.black
    
    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true
        
        Task.detached { [weak self] in
            let newScene = SCNScene()
            let miniScene = SCNScene()
            let structures = AtlasLoader.load()
            let brainOnly = structures.filter { $0.modelFileName != nil && $0.isBrainStructure && !$0.isGroup }
            
            var entries: [(node: SCNNode, structure: BrainStructure)] = []
            var globalMinZ: Float = .greatestFiniteMagnitude
            var globalMaxZ: Float = -.greatestFiniteMagnitude
            
            for s in brainOnly {
                guard let fn = s.modelFileName, let node = ModelCache.shared.node(for: fn) else { continue }
                let color = UIColor(s.color)
                Self.applyMaterial(to: node, color: color)
                newScene.rootNode.addChildNode(node)
                entries.append((node: node, structure: s))
                
                let (bmin, bmax) = node.boundingBox
                globalMinZ = min(globalMinZ, bmin.z)
                globalMaxZ = max(globalMaxZ, bmax.z)
                
                // Mini-brain node — single gray, translucent
                if let miniNode = ModelCache.shared.node(for: fn) {
                    let gray = UIColor(white: 0.7, alpha: 0.35)
                    Self.applyMaterial(to: miniNode, color: gray)
                    miniNode.name = s.id
                    miniScene.rootNode.addChildNode(miniNode)
                }
            }
            
            // Slice plane for mini-brain
            let planeHeight: Float = Float(globalMaxZ - globalMinZ) * 0.8
            let plane = SCNPlane(width: CGFloat(planeHeight), height: CGFloat(planeHeight))
            let planeMat = SCNMaterial()
            planeMat.diffuse.contents = UIColor(red: 0.2, green: 0.9, blue: 0.7, alpha: 0.45)
            planeMat.isDoubleSided = true
            planeMat.blendMode = .alpha
            plane.materials = [planeMat]
            let planeNode = SCNNode(geometry: plane)
            planeNode.name = "slicePlane"
            let midZ = (globalMinZ + globalMaxZ) / 2
            planeNode.position = SCNVector3(0, 0, midZ)
            miniScene.rootNode.addChildNode(planeNode)
            
            // Mini-brain camera + lighting
            let cam = SCNCamera()
            cam.fieldOfView = 40
            cam.zNear = 1
            cam.zFar = 2000
            let camNode = SCNNode()
            camNode.camera = cam
            camNode.position = SCNVector3(0, -300, 40)
            camNode.look(at: SCNVector3(0, 0, midZ), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
            camNode.name = "miniCamera"
            miniScene.rootNode.addChildNode(camNode)
            
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 500
            ambient.light?.color = UIColor.white
            miniScene.rootNode.addChildNode(ambient)
            
            let dir = SCNNode()
            dir.light = SCNLight()
            dir.light?.type = .directional
            dir.light?.intensity = 600
            dir.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
            miniScene.rootNode.addChildNode(dir)
            
            let finalEntries = entries
            let finalMinZ = globalMinZ
            let finalMaxZ = globalMaxZ
            // Build mini-node lookup by name
            var miniNodeMap: [String: SCNNode] = [:]
            for child in miniScene.rootNode.childNodes {
                if let name = child.name, name != "slicePlane" && name != "miniCamera" {
                    miniNodeMap[name] = child
                }
            }
            let finalMiniNodes = miniNodeMap
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.mriScene = newScene
                self.miniBrainScene = miniScene
                self.brainStructures = brainOnly
                self.allNodes = finalEntries
                self.miniNodes = finalMiniNodes
                self.minZ = finalMinZ
                self.maxZ = finalMaxZ
                self.slicePlaneNode = planeNode
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
        
        let targetIdx = Int.random(in: 0..<allNodes.count)
        currentTargetIndex = targetIdx
        let targetNode = allNodes[targetIdx].node
        let target = allNodes[targetIdx].structure
        
        let (bmin, bmax) = targetNode.boundingBox
        let targetSlice = Float.random(in: bmin.z...bmax.z)
        slicePosition = (targetSlice - minZ) / (maxZ - minZ)
        
        correctAnswer = target.baseName
        targetColor = target.color
        
        var optionSet = Set<String>([target.baseName])
        let shuffled = brainStructures.shuffled()
        for s in shuffled {
            if optionSet.count >= 4 { break }
            if !optionSet.contains(s.baseName) { optionSet.insert(s.baseName) }
        }
        options = Array(optionSet).shuffled()
        
        // Reset mini-brain to gray
        resetMiniBrain()
        
        // Render two snapshots for pulsing effect
        let clipZ = targetSlice
        let thickness: Float = 2.0
        let viewClipZ = clipZ - Self.cameraZ
        
        // Bright frame: target in bright white, non-target dimmed
        for (i, entry) in allNodes.enumerated() {
            if i == targetIdx {
                applyClipShader(to: entry.node, viewClipZ: viewClipZ, thickness: thickness, color: Self.highlightBright)
            } else {
                let dimmed = Self.dimmedColor(UIColor(entry.structure.color))
                applyClipShader(to: entry.node, viewClipZ: viewClipZ, thickness: thickness, color: dimmed)
            }
        }
        guard let renderer else { isLoading = false; return }
        let size = CGSize(width: 512, height: 512)
        sliceImageBright = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        
        // Dim frame: target in dim highlight, non-target still dimmed
        for (i, entry) in allNodes.enumerated() {
            if i == targetIdx {
                applyClipShader(to: entry.node, viewClipZ: viewClipZ, thickness: thickness, color: Self.highlightDim)
            } else {
                let dimmed = Self.dimmedColor(UIColor(entry.structure.color))
                applyClipShader(to: entry.node, viewClipZ: viewClipZ, thickness: thickness, color: dimmed)
            }
        }
        sliceImageDim = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        
        // Update mini-brain slice plane
        slicePlaneNode?.position.z = clipZ
        
        isLoading = false
    }
    
    func answer(_ choice: String) {
        guard !showingFeedback else { return }
        selectedAnswer = choice
        showingFeedback = true
        total += 1
        if choice == correctAnswer { score += 1 }
        showFeedbackOnMiniBrain(chosen: choice)
    }
    
    /// Dim color: 20% brightness, 40% alpha
    private nonisolated static func dimmedColor(_ color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * 0.2, green: g * 0.2, blue: b * 0.2, alpha: 0.4)
    }
    
    /// Color correct region green and wrong region red on mini-brain
    private func showFeedbackOnMiniBrain(chosen: String) {
        guard currentTargetIndex >= 0 && currentTargetIndex < allNodes.count else { return }
        let correctID = allNodes[currentTargetIndex].structure.id
        let wrongID: String? = (chosen != correctAnswer)
            ? allNodes.first(where: { $0.structure.baseName == chosen })?.structure.id
            : nil
        
        for (id, node) in miniNodes {
            if id == correctID {
                Self.applyMaterial(to: node, color: UIColor(red: 0.2, green: 0.9, blue: 0.3, alpha: 0.9))
            } else if let wid = wrongID, id == wid {
                Self.applyMaterial(to: node, color: UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.9))
            }
        }
    }
    
    /// Reset mini-brain to uniform gray
    private func resetMiniBrain() {
        let gray = UIColor(white: 0.7, alpha: 0.35)
        for (_, node) in miniNodes {
            Self.applyMaterial(to: node, color: gray)
        }
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
                    
                    // MRI slice image with pulsing + mini-brain
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
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        
                        // Mini 3D brain
                        MiniBrainView(scene: vm.miniBrainScene)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
                            .padding(10)
                    }
                    .padding(.horizontal)
                    
                    Spacer().frame(height: 12)
                    
                    // Question area
                    VStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(vm.targetColor)
                                .frame(width: 10, height: 10)
                                .shadow(color: vm.targetColor.opacity(0.8), radius: 4)
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
        guard vm.showingFeedback else { return Color.white.opacity(0.1) }
        if vm.isCorrect(option) { return Color.green.opacity(0.3) }
        if vm.selectedAnswer == option && !vm.isCorrect(option) {
            return Color.red.opacity(0.4)
        }
        return Color.white.opacity(0.05)
    }
}
