import SwiftUI
import SceneKit

// MARK: - Explore ViewModel

@MainActor @Observable
final class ExploreViewModel {
    var allStructures: [BrainStructure] = []
    var brainStructures: [BrainStructure] = []
    var scene = SCNScene()
    var selectedStructure: BrainStructure?
    var searchQuery = ""
    var explodeFactor: Float = 0
    var isLoading = true
    
    private var structureNodes: [String: SCNNode] = [:]
    private var originalPositions: [String: SCNVector3] = [:]
    private var brainCenter = SCNVector3Zero
    private var setupStarted = false
    
    var searchResults: [BrainStructure] {
        guard !searchQuery.isEmpty else { return [] }
        let q = searchQuery.lowercased()
        return brainStructures.filter { $0.name.lowercased().contains(q) }
            .prefix(10).map { $0 }
    }
    
    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true
        
        Task.detached { [weak self] in
            let loaded = AtlasLoader.load()
            let brainOnly = loaded.filter { $0.modelFileName != nil && $0.isBrainStructure && !$0.isGroup }
            let newScene = SCNScene()
            
            var nodes: [String: SCNNode] = [:]
            var positions: [String: SCNVector3] = [:]
            var totalX: Float = 0, totalY: Float = 0, totalZ: Float = 0
            var count: Float = 0
            
            for s in brainOnly {
                guard let fn = s.modelFileName, let node = ModelCache.shared.node(for: fn) else { continue }
                let uiColor = UIColor(s.color)
                Self.applyColor(to: node, color: uiColor)
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
                self.allStructures = loaded
                self.brainStructures = brainOnly
                self.scene = newScene
                self.structureNodes = finalNodes
                self.originalPositions = finalPositions
                self.brainCenter = center
                self.isLoading = false
            }
        }
    }
    
    func select(_ structure: BrainStructure) {
        selectedStructure = structure
        
        for (id, node) in structureNodes {
            if id == structure.id {
                Self.applyColor(to: node, color: UIColor.systemGreen)
                node.opacity = 1.0
            } else {
                Self.applyColor(to: node, color: UIColor(white: 0.5, alpha: 1.0))
                node.opacity = 0.15
            }
        }
    }
    
    func selectByID(_ id: String) {
        if let s = brainStructures.first(where: { $0.id == id }) {
            select(s)
        }
    }
    
    func clearSelection() {
        selectedStructure = nil
        for (id, node) in structureNodes {
            if let s = brainStructures.first(where: { $0.id == id }) {
                Self.applyColor(to: node, color: UIColor(s.color))
                node.opacity = 1.0
            }
        }
    }
    
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
    
    private nonisolated static func applyColor(to node: SCNNode, color: UIColor) {
        if let geom = node.geometry {
            for mat in geom.materials {
                mat.diffuse.contents = color
                mat.isDoubleSided = true
            }
        }
        for child in node.childNodes { applyColor(to: child, color: color) }
    }
}

// MARK: - Explore View

struct ExploreView: View {
    @State private var vm = ExploreViewModel()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if vm.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Loading brain atlas…")
                        .foregroundColor(.gray)
                }
            } else {
                // 3D View
                SceneKitView(scene: vm.scene, onTap: { hit in
                    if let name = hit.node.name {
                        vm.selectByID(name)
                    } else if let parent = hit.node.parent?.name {
                        vm.selectByID(parent)
                    }
                })
                .ignoresSafeArea(edges: .bottom)
                
                // Overlays
                VStack {
                    // Search bar
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            TextField("Search structures…", text: $vm.searchQuery)
                                .foregroundColor(.white)
                                .autocorrectionDisabled()
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        
                        if vm.selectedStructure != nil {
                            Button {
                                vm.clearSelection()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    
                    // Search results dropdown
                    if !vm.searchResults.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(vm.searchResults) { s in
                                    Button {
                                        vm.select(s)
                                        vm.searchQuery = ""
                                    } label: {
                                        Text(s.name)
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Divider().background(Color.white.opacity(0.1))
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .background(Color(hex: "1a1a2e").opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Controls (explode slider)
                    HStack {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .foregroundColor(.gray)
                            .font(.caption)
                        Slider(value: Binding(
                            get: { vm.explodeFactor },
                            set: { vm.explodeFactor = $0; vm.updateExplode() }
                        ), in: 0...3)
                        .tint(Color(hex: "06b6d4"))
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .padding(.horizontal, 40)
                    
                    // Info card
                    if let s = vm.selectedStructure {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.name)
                                .font(.headline)
                                .foregroundColor(.white)
                            if !s.hierarchyPath.isEmpty {
                                Text(s.hierarchyPath.joined(separator: " → ") + " → " + s.name)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { vm.setup() }
    }
}
