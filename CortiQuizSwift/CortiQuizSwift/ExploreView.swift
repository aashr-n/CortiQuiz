import SwiftUI
import SceneKit

// MARK: - Explore ViewModel

@MainActor @Observable
final class ExploreViewModel {
    var brainStructures: [BrainStructure] = []
    var scene = SCNScene()
    var selectedStructure: BrainStructure?
    var searchQuery = ""
    private(set) var explodeFactor: Float = 0
    var isLoading = true
    var loadFailed = false
    var recenterTrigger = false

    private var structuresByID: [String: BrainStructure] = [:]
    private var structureNodes: [String: SCNNode] = [:]
    private var explodeLayout = ExplodeLayout()
    private var hasLoaded = false

    var searchResults: [BrainStructure] {
        guard !searchQuery.isEmpty else { return [] }
        let q = searchQuery.lowercased()
        return Array(brainStructures.filter { $0.name.lowercased().contains(q) }.prefix(10))
    }

    /// Builds the scene off the main actor. Runs from SwiftUI's `.task`, so leaving the
    /// screen mid-load cancels it and a later visit starts over.
    func load() async {
        guard !hasLoaded else { return }
        let loaded = await Background.run {
            BrainSceneLoader.load { node, s in
                node.applyColor(UIColor(s.color))
            }
        }
        guard !Task.isCancelled else { return }
        hasLoaded = true
        guard !loaded.structures.isEmpty else {
            loadFailed = true
            isLoading = false
            return
        }

        brainStructures = loaded.structures
        structuresByID = Dictionary(uniqueKeysWithValues: loaded.structures.map { ($0.id, $0) })
        scene = loaded.scene
        structureNodes = loaded.nodes
        explodeLayout = loaded.explodeLayout
        isLoading = false
    }

    func select(_ structure: BrainStructure) {
        Theme.tapHaptic()
        selectedStructure = structure
        restyleNodes(structureNodes) { id in
            id == structure.id
                ? (SceneColors.selection, 1.0)
                : (SceneColors.ghost, SceneColors.ghostOpacity)
        }
    }

    /// Hits arrive nearest-first. While something is selected everything else is a faded
    /// ghost, so prefer the first fully opaque hit — that keeps the highlighted structure
    /// tappable through the translucent cortex in front of it.
    func handleTap(_ hits: [SCNHitTestResult]) {
        let ids = hits.compactMap { structureID(for: $0.node) }
        let opaque = ids.first { (structureNodes[$0]?.opacity ?? 0) > 0.99 }
        if let id = opaque ?? ids.first, let structure = structuresByID[id] {
            select(structure)
        }
    }

    /// The structure a hit belongs to (the hit node may be a child of the structure node).
    private func structureID(for node: SCNNode) -> String? {
        var current: SCNNode? = node
        while let n = current {
            if let name = n.name, structureNodes[name] != nil { return name }
            current = n.parent
        }
        return nil
    }

    func clearSelection() {
        selectedStructure = nil
        restyleNodes(structureNodes) { id in
            (structuresByID[id].map { UIColor($0.color) } ?? SceneColors.ghost, 1.0)
        }
    }

    func setExplode(_ factor: Float) {
        explodeFactor = factor
        explodeLayout.apply(factor, to: structureNodes)
    }
}

// MARK: - Explore View

struct ExploreView: View {
    @State private var vm = ExploreViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if vm.isLoading || vm.loadFailed {
                LoadingStateView(message: "Loading brain atlas…", failed: vm.loadFailed)
            } else {
                ZStack(alignment: .bottomTrailing) {
                    SceneKitView(scene: vm.scene, onTap: { hits in
                        vm.handleTap(hits)
                    }, recenterTrigger: vm.recenterTrigger)
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityLabel("3D brain atlas. Tap a structure to select it.")

                    RecenterButton { vm.recenterTrigger.toggle() }
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
                            .accessibilityLabel("Clear selection")
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

                    ExplodeSlider(value: Binding(get: { vm.explodeFactor }, set: { vm.setExplode($0) }))
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
        .task { await vm.load() }
    }
}
