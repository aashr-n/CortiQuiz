import SwiftUI
import SceneKit

// MARK: - MRI ViewModel

@MainActor @Observable
final class MRIViewModel {
    var slicePosition: Float = 0.5
    var isLoading = true
    var sliceImage: UIImage?
    
    // Mini-brain scene (atlas colors, translucent, with slice plane)
    var miniBrainScene = SCNScene()
    var recenterMini = false
    
    private var allNodes: [SCNNode] = []
    private var nodeColors: [UIColor] = []  // 4-color per node for MRI render
    // Z-axis bounds (superior-inferior in RAS)
    private var minZ: Float = 0
    private var maxZ: Float = 0
    private var setupStarted = false
    
    private var renderer: SCNRenderer?
    private var mriScene: SCNScene?
    
    // Slice plane node in mini-brain
    private var slicePlaneNode: SCNNode?
    
    // Camera Z for MRI renderer
    nonisolated static let cameraZ: Float = 300
    
    // 4-color MRI palette (applied only to 2D slice render)
    nonisolated static let regionColors: [UIColor] = [
        UIColor(red: 0.92, green: 0.82, blue: 0.62, alpha: 1.0),  // warm sand
        UIColor(red: 0.45, green: 0.58, blue: 0.78, alpha: 1.0),  // slate blue
        UIColor(red: 0.76, green: 0.52, blue: 0.62, alpha: 1.0),  // dusty mauve
        UIColor(red: 0.48, green: 0.72, blue: 0.58, alpha: 1.0),  // eucalyptus
    ]
    
    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true
        
        Task.detached { [weak self] in
            let mriScene = SCNScene()
            let miniScene = SCNScene()
            let structures = AtlasLoader.load()
            let brainStructures = structures.filter { $0.modelFileName != nil && $0.isBrainStructure && !$0.isGroup }
            
            var nodes: [SCNNode] = []
            var colors: [UIColor] = []
            var globalMinZ: Float = .greatestFiniteMagnitude
            var globalMaxZ: Float = -.greatestFiniteMagnitude
            
            for (i, s) in brainStructures.enumerated() {
                guard let fn = s.modelFileName else { continue }
                
                // MRI renderer node — 4-color
                guard let mriNode = ModelCache.shared.node(for: fn) else { continue }
                let color = Self.regionColors[i % Self.regionColors.count]
                Self.applyMaterial(to: mriNode, color: color)
                mriScene.rootNode.addChildNode(mriNode)
                nodes.append(mriNode)
                colors.append(color)
                
                let (bmin, bmax) = mriNode.boundingBox
                globalMinZ = min(globalMinZ, bmin.z)
                globalMaxZ = max(globalMaxZ, bmax.z)
                
                // Mini-brain node — atlas colors, translucent
                if let miniNode = ModelCache.shared.node(for: fn) {
                    let atlasColor = UIColor(s.color).withAlphaComponent(0.35)
                    Self.applyMaterial(to: miniNode, color: atlasColor)
                    miniScene.rootNode.addChildNode(miniNode)
                }
            }
            
            // Add slice plane to mini scene
            let planeHeight: Float = Float(globalMaxZ - globalMinZ) * 0.8
            let plane = SCNPlane(width: CGFloat(planeHeight), height: CGFloat(planeHeight))
            let planeMat = SCNMaterial()
            planeMat.diffuse.contents = UIColor(red: 0.2, green: 0.9, blue: 0.7, alpha: 0.45)
            planeMat.isDoubleSided = true
            planeMat.blendMode = .alpha
            plane.materials = [planeMat]
            let planeNode = SCNNode(geometry: plane)
            planeNode.name = "slicePlane"
            // SCNPlane lies in XY (normal +Z) — perfect for axial slice positioning
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
            
            let finalNodes = nodes
            let finalColors = colors
            let finalMinZ = globalMinZ
            let finalMaxZ = globalMaxZ
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.mriScene = mriScene
                self.miniBrainScene = miniScene
                self.allNodes = finalNodes
                self.nodeColors = finalColors
                self.minZ = finalMinZ
                self.maxZ = finalMaxZ
                self.slicePlaneNode = planeNode
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
        let viewClipZ = clipZ - Self.cameraZ
        for (i, node) in allNodes.enumerated() {
            applyClipShader(to: node, viewClipZ: viewClipZ, thickness: thickness, color: nodeColors[i])
        }
        renderSnapshot()
        
        // Move mini-brain slice plane
        slicePlaneNode?.position.z = clipZ
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

// MARK: - Mini Brain SceneKit View (self-contained, no external camera setup)

private struct MiniBrainView: UIViewRepresentable {
    let scene: SCNScene
    
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.autoenablesDefaultLighting = false
        view.backgroundColor = UIColor(white: 0.06, alpha: 1.0)
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitAngleMapping
        view.defaultCameraController.worldUp = SCNVector3(0, 0, 1)
        view.scene = scene
        return view
    }
    
    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== scene {
            view.scene = scene
        }
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
                    
                    // MRI slice image + mini-brain overlay
                    ZStack(alignment: .bottomLeading) {
                        // 2D slice
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
                        
                        // Mini 3D brain
                        MiniBrainView(scene: vm.miniBrainScene)
                            .frame(width: 140, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
                            .padding(10)
                    }
                    .padding(.horizontal)
                    
                    Spacer().frame(height: 12)
                    
                    // Slider
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
