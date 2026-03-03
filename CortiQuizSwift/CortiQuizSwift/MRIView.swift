import SwiftUI
import SceneKit

// MARK: - MRI ViewModel

@MainActor @Observable
final class MRIViewModel {
    var scene = SCNScene()
    var slicePosition: Float = 0.5
    var isLoading = true
    private var whiteNodes: [SCNNode] = []
    
    // Y-axis bounds of the loaded models
    private var minY: Float = 0
    private var maxY: Float = 0
    private var setupStarted = false
    
    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true
        
        Task.detached { [weak self] in
            let newScene = SCNScene()
            let files = ["Model_2_white_matter_of_left_cerebral_hemisphere.obj",
                         "Model_41_white_matter_of_right_cerebral_hemisphere.obj"]
            
            var nodes: [SCNNode] = []
            var globalMinY: Float = .greatestFiniteMagnitude
            var globalMaxY: Float = -.greatestFiniteMagnitude
            
            for f in files {
                guard let node = ModelCache.shared.node(for: f) else { continue }
                let color = UIColor(white: 0.85, alpha: 1.0)
                Self.applyMaterial(to: node, color: color)
                newScene.rootNode.addChildNode(node)
                nodes.append(node)
                
                let (bmin, bmax) = node.boundingBox
                globalMinY = min(globalMinY, bmin.y)
                globalMaxY = max(globalMaxY, bmax.y)
            }
            
            await MainActor.run {
                guard let self else { return }
                self.scene = newScene
                self.whiteNodes = nodes
                self.minY = globalMinY
                self.maxY = globalMaxY
                self.isLoading = false
                self.updateClip()
            }
        }
    }
    
    func updateClip() {
        let clipY = minY + (maxY - minY) * slicePosition
        let thickness: Float = 2.0
        for node in whiteNodes {
            applyShader(to: node, clipY: clipY, thickness: thickness)
        }
    }
    
    private func applyShader(to node: SCNNode, clipY: Float, thickness: Float) {
        if let geom = node.geometry {
            for mat in geom.materials {
                mat.shaderModifiers = [
                    .fragment: """
                    float worldY = _surface.position.y;
                    if (worldY > \(clipY) || worldY < \(clipY - thickness)) {
                        discard_fragment();
                    }
                    """
                ]
                mat.isDoubleSided = true
            }
        }
        for child in node.childNodes {
            applyShader(to: child, clipY: clipY, thickness: thickness)
        }
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
                HStack(spacing: 0) {
                    // 3D view
                    SceneKitView(scene: vm.scene)
                        .frame(maxWidth: .infinity)
                    
                    // Vertical slider
                    VStack {
                        Text("S")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        
                        GeometryReader { geo in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 6)
                                
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: "10b981"))
                                    .frame(width: 6, height: geo.size.height * CGFloat(vm.slicePosition))
                                
                                Circle()
                                    .fill(Color(hex: "10b981"))
                                    .frame(width: 24, height: 24)
                                    .shadow(color: Color(hex: "10b981").opacity(0.5), radius: 6)
                                    .offset(y: -geo.size.height * CGFloat(vm.slicePosition) + 12)
                            }
                            .frame(maxWidth: .infinity)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { val in
                                        let pct = 1.0 - (val.location.y / geo.size.height)
                                        vm.slicePosition = Float(max(0, min(1, pct)))
                                        vm.updateClip()
                                    }
                            )
                        }
                        
                        Text("I")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .frame(width: 44)
                    .padding(.vertical)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { vm.setup() }
    }
}
