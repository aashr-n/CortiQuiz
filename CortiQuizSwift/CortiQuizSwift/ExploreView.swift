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
    var recenterTrigger = false
    
    private var structureNodes: [String: SCNNode] = [:]
    private var originalPositions: [String: SCNVector3] = [:]
    private var brainCenter = SCNVector3Zero
    private var setupStarted = false
    
    var searchResults: [BrainStructure] {
        guard !searchQuery.isEmpty else { return [] }
        let q = searchQuery.lowercased()
        return Array(brainStructures.filter { $0.name.lowercased().contains(q) }.prefix(10))
    }
    
    func setup() {
        guard !setupStarted else { return }
        setupStarted = true
        isLoading = true

        Task.detached { [weak self] in
            let loaded = BrainSceneLoader.load { node, s in
                node.applyColor(UIColor(s.color))
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.allStructures = loaded.allStructures
                self.brainStructures = loaded.structures
                self.scene = loaded.scene
                self.structureNodes = loaded.nodes
                self.originalPositions = loaded.nodeCenters
                self.brainCenter = loaded.center
                self.isLoading = false
            }
        }
    }
    
    func select(_ structure: BrainStructure) {
        Theme.tapHaptic()
        selectedStructure = structure
        
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.25
        for (id, node) in structureNodes {
            if id == structure.id {
                node.applyColor(UIColor.systemGreen)
                node.opacity = 1.0
            } else {
                node.applyColor(UIColor(white: 0.5, alpha: 1.0))
                node.opacity = 0.15
            }
        }
        SCNTransaction.commit()
    }
    
    func selectByID(_ id: String) {
        if let s = brainStructures.first(where: { $0.id == id }) {
            select(s)
        }
    }
    
    func clearSelection() {
        selectedStructure = nil
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.25
        for (id, node) in structureNodes {
            if let s = brainStructures.first(where: { $0.id == id }) {
                node.applyColor(UIColor(s.color))
                node.opacity = 1.0
            }
        }
        SCNTransaction.commit()
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
    
    func resetForReentry() {
        setupStarted = false
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
                        .foregroundColor(Theme.textSecondary)
                }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    SceneKitView(scene: vm.scene, onTap: { hit in
                        if let name = hit.node.name {
                            vm.selectByID(name)
                        } else if let parent = hit.node.parent?.name {
                            vm.selectByID(parent)
                        }
                    }, recenterTrigger: vm.recenterTrigger)
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityLabel("3D brain atlas. Tap a structure to select it.")

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
                    .accessibilityLabel("Recenter camera")
                    .padding(12)
                }
                
                VStack {
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(Theme.textSecondary)
                            TextField("Search structures…", text: $vm.searchQuery)
                                .foregroundColor(.white)
                                .autocorrectionDisabled()
                        }
                        .padding(10)
                        .background(Theme.bgInput)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        
                        if vm.selectedStructure != nil {
                            Button {
                                vm.clearSelection()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    
                    if !vm.searchResults.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(vm.searchResults) { s in
                                    Button {
                                        vm.select(s)
                                        vm.searchQuery = ""
                                    } label: {
                                        Text(s.name)
                                            .font(Theme.bodyFont)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Divider().background(Theme.divider)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .background(Theme.bgSecondary.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    HStack {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .foregroundColor(Theme.textSecondary)
                            .font(Theme.captionFont)
                        Slider(value: Binding(
                            get: { vm.explodeFactor },
                            set: { vm.explodeFactor = $0; vm.updateExplode() }
                        ), in: 0...3)
                        .tint(Theme.accent)
                        .accessibilityLabel("Explode view")
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundColor(Theme.textSecondary)
                            .font(Theme.captionFont)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Theme.bgCard)
                    .clipShape(Capsule())
                    .padding(.horizontal, 40)
                    
                    if let s = vm.selectedStructure {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.name)
                                .font(Theme.headingFont)
                                .foregroundColor(Theme.textPrimary)
                            if !s.hierarchyPath.isEmpty {
                                Text(s.hierarchyPath.joined(separator: " → ") + " → " + s.name)
                                    .font(Theme.captionFont)
                                    .foregroundColor(Theme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Theme.bgCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Theme.bgCardStroke, lineWidth: 1)
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
        .onDisappear { vm.resetForReentry() }
    }
}
