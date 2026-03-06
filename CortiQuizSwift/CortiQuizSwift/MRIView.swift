import SwiftUI
import SceneKit

// MARK: - MRI ViewModel

@MainActor @Observable
final class MRIViewModel {
    var slicePosition: Float = 0.5
    var isLoading = true
    var sliceImage: UIImage?
    
    private var allNodes: [SCNNode] = []
    private var nodeColors: [UIColor] = []  // 4-color assignment per node
    // Z-axis bounds (superior-inferior in RAS)
    private var minZ: Float = 0
    private var maxZ: Float = 0
    private var setupStarted = false
    
    private var renderer: SCNRenderer?
    private var mriScene: SCNScene?
    
    // Camera Z position — must match setupRenderer
    nonisolated static let cameraZ: Float = 300
    
    // 4 distinct MRI-palette colors (four color theorem)
    nonisolated static let regionColors: [UIColor] = [
        UIColor(red: 0.95, green: 0.85, blue: 0.55, alpha: 1.0),  // warm cream
        UIColor(red: 0.60, green: 0.75, blue: 0.90, alpha: 1.0),  // soft blue
        UIColor(red: 0.85, green: 0.55, blue: 0.65, alpha: 1.0),  // muted rose
        UIColor(red: 0.55, green: 0.80, blue: 0.65, alpha: 1.0),  // sage green
    ]
    
    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true
        
        Task.detached { [weak self] in
            let newScene = SCNScene()
            let structures = AtlasLoader.load()
            let brainStructures = structures.filter { $0.modelFileName != nil && $0.isBrainStructure && !$0.isGroup }
            
            var nodes: [SCNNode] = []
            var colors: [UIColor] = []
            var globalMinZ: Float = .greatestFiniteMagnitude
            var globalMaxZ: Float = -.greatestFiniteMagnitude
            
            for (i, s) in brainStructures.enumerated() {
                guard let fn = s.modelFileName, let node = ModelCache.shared.node(for: fn) else { continue }
                let color = Self.regionColors[i % Self.regionColors.count]
                Self.applyMaterial(to: node, color: color)
                newScene.rootNode.addChildNode(node)
                nodes.append(node)
                colors.append(color)
                
                let (bmin, bmax) = node.boundingBox
                globalMinZ = min(globalMinZ, bmin.z)
                globalMaxZ = max(globalMaxZ, bmax.z)
            }
            
            let finalNodes = nodes
            let finalColors = colors
            let finalMinZ = globalMinZ
            let finalMaxZ = globalMaxZ
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.mriScene = newScene
                self.allNodes = finalNodes
                self.nodeColors = finalColors
                self.minZ = finalMinZ
                self.maxZ = finalMaxZ
                self.setupRenderer()
                self.isLoading = false
                self.updateSlice()
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
        camNode.name = "mriCamera"
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
    
    func updateSlice() {
        let clipZ = minZ + (maxZ - minZ) * slicePosition
        let thickness: Float = 2.0
        // Convert world-space Z to view-space Z (camera at +cameraZ looking toward origin)
        let viewClipZ = clipZ - Self.cameraZ
        for (i, node) in allNodes.enumerated() {
            applyClipShader(to: node, viewClipZ: viewClipZ, thickness: thickness, color: nodeColors[i])
        }
        renderSnapshot()
    }
    
    private func renderSnapshot() {
        guard let renderer else { return }
        let size = CGSize(width: 512, height: 512)
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        self.sliceImage = image
    }
    
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

// MARK: - MRI View

struct MRIView: View {
    @State private var vm = MRIViewModel()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if vm.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Loading MRI data…")
                        .foregroundColor(.gray)
                }
            } else {
                VStack(spacing: 0) {
                    Text("Axial MRI Slice")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.top, 8)
                    
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
                    
                    VStack(spacing: 6) {
                        HStack {
                            Text("Inferior")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("Position: \(Int(vm.slicePosition * 100))%")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text("Superior")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 4)
                        
                        Slider(value: Binding(
                            get: { vm.slicePosition },
                            set: { vm.slicePosition = $0; vm.updateSlice() }
                        ), in: 0...1)
                        .tint(Color(hex: "10b981"))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { vm.setup() }
        .onDisappear { vm.resetForReentry() }
    }
}
