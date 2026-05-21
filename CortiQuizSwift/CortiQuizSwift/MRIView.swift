import SwiftUI
import SceneKit

// MARK: - MRI Axis Enum

enum MRIAxis: Int, CaseIterable, Identifiable {
    case axial, coronal, sagittal
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .axial: return "Axial"
        case .coronal: return "Coronal"
        case .sagittal: return "Sagittal"
        }
    }
    var labelStart: String {
        switch self {
        case .axial: return "Inferior"
        case .coronal: return "Posterior"
        case .sagittal: return "Left"
        }
    }
    var labelEnd: String {
        switch self {
        case .axial: return "Superior"
        case .coronal: return "Anterior"
        case .sagittal: return "Right"
        }
    }
}

// MARK: - MRI ViewModel

@MainActor @Observable
final class MRIViewModel {
    var slicePosition: Float = 0.5
    var isLoading = true
    var sliceImage: UIImage?
    var miniBrainScene = SCNScene()
    var recenterMini = false
    var activeAxis: MRIAxis = .axial
    
    private var allNodes: [SCNNode] = []
    private var bounds = MiniBrainBuilder.Bounds()
    private var setupStarted = false
    private var renderer: SCNRenderer?
    private var mriScene: SCNScene?
    private var slicePlaneNode: SCNNode?
    
    nonisolated static let cameraZ: Float = 300
    
    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true
        
        Task.detached { [weak self] in
            let mriScene = SCNScene()
            let structures = AtlasLoader.load()
            let brainStructures = structures.filter { $0.modelFileName != nil && $0.isBrainStructure && !$0.isGroup }
            
            var nodes: [SCNNode] = []
            var globalBounds = MiniBrainBuilder.Bounds()
            
            for s in brainStructures {
                guard let fn = s.modelFileName, let mriNode = ModelCache.shared.node(for: fn) else { continue }
                let color = UIColor(s.color)
                mriNode.installClipShader(color: color)
                mriScene.rootNode.addChildNode(mriNode)
                nodes.append(mriNode)
                
                let (bmin, bmax) = mriNode.boundingBox
                globalBounds.minX = min(globalBounds.minX, bmin.x)
                globalBounds.maxX = max(globalBounds.maxX, bmax.x)
                globalBounds.minY = min(globalBounds.minY, bmin.y)
                globalBounds.maxY = max(globalBounds.maxY, bmax.y)
                globalBounds.minZ = min(globalBounds.minZ, bmin.z)
                globalBounds.maxZ = max(globalBounds.maxZ, bmax.z)
            }
            
            let miniResult = MiniBrainBuilder.build(
                structures: brainStructures,
                bounds: globalBounds
            )
            
            let finalNodes = nodes
            let finalBounds = globalBounds
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.mriScene = mriScene
                self.miniBrainScene = miniResult.scene
                self.allNodes = finalNodes
                self.bounds = finalBounds
                self.slicePlaneNode = miniResult.planeNode
                self.setupRenderer()
                self.isLoading = false
                self.updateAxis()
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
    
    func updateAxis() {
        guard let camNode = mriScene?.rootNode.childNode(withName: "mriCamera", recursively: false) else { return }
        
        switch activeAxis {
        case .axial:
            // Slicing Z. Camera looks from Superior (+Z) to Inferior (-Z)
            camNode.position = SCNVector3(0, 0, Self.cameraZ)
            camNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, -1, 0), localFront: SCNVector3(0, 0, -1))
            slicePlaneNode?.eulerAngles = SCNVector3(0, 0, 0)
        case .coronal:
            // Slicing Y. Camera looks from Anterior (+Y) to Posterior (-Y)
            camNode.position = SCNVector3(0, Self.cameraZ, 0)
            camNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
            slicePlaneNode?.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        case .sagittal:
            // Slicing X. Camera looks from Right (+X) to Left (-X)
            camNode.position = SCNVector3(Self.cameraZ, 0, 0)
            camNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
            slicePlaneNode?.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
        }
        
        updateSlice()
    }
    
    func updateSlice() {
        let minVal: Float
        let maxVal: Float
        
        switch activeAxis {
        case .axial:
            minVal = bounds.minZ
            maxVal = bounds.maxZ
        case .coronal:
            minVal = bounds.minY
            maxVal = bounds.maxY
        case .sagittal:
            minVal = bounds.minX
            maxVal = bounds.maxX
        }
        
        let clipVal = minVal + (maxVal - minVal) * slicePosition
        let thickness: Float = 2.0
        let viewClipZ = clipVal - Self.cameraZ
        
        for node in allNodes {
            node.updateClipUniforms(viewClipZ: viewClipZ, thickness: thickness)
        }
        renderSnapshot()
        
        switch activeAxis {
        case .axial:
            slicePlaneNode?.position = SCNVector3(0, 0, clipVal)
        case .coronal:
            slicePlaneNode?.position = SCNVector3(0, clipVal, 0)
        case .sagittal:
            slicePlaneNode?.position = SCNVector3(clipVal, 0, 0)
        }
    }
    
    private func renderSnapshot() {
        guard let renderer else { return }
        let size = CGSize(width: 512, height: 512)
        sliceImage = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }
    
    func resetForReentry() {
        setupStarted = false
    }
}

// MARK: - Mini Brain SceneKit View

struct MiniBrainView: UIViewRepresentable {
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
                        .foregroundColor(Theme.textSecondary)
                }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(vm.activeAxis.title) MRI Slice")
                            .font(Theme.headingFont)
                            .foregroundColor(Theme.textPrimary)
                        
                        Spacer()
                        
                        Picker("Axis", selection: Binding(
                            get: { vm.activeAxis },
                            set: { vm.activeAxis = $0; vm.updateAxis() }
                        )) {
                            ForEach(MRIAxis.allCases) { axis in
                                Text(axis.title).tag(axis)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    Spacer().frame(height: 12)
                    
                    HStack(spacing: 8) {
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
                                .stroke(Theme.bgCardStroke, lineWidth: 1)
                        )
                        
                        MiniBrainView(scene: vm.miniBrainScene)
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.bgCardStroke, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal)
                    
                    Spacer().frame(height: 12)
                    
                    VStack(spacing: 6) {
                        HStack {
                            Text(vm.activeAxis.labelStart)
                                .font(Theme.captionFont)
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text("Position: \(Int(vm.slicePosition * 100))%")
                                .font(Theme.captionFont)
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text(vm.activeAxis.labelEnd)
                                .font(Theme.captionFont)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.horizontal, 4)
                        
                        Slider(value: Binding(
                            get: { vm.slicePosition },
                            set: { vm.slicePosition = $0; vm.updateSlice() }
                        ), in: 0...1)
                        .tint(Theme.accent)
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

