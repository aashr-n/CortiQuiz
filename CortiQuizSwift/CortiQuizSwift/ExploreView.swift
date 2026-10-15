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
    /// Something has been selected this visit; the "tap a structure" tip stays away after.
    private(set) var hasSelected = false

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
                node.applyStyle(.solid(UIColor(s.color)))
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
        hasSelected = true
        restyleNodes(structureNodes) { id in
            id == structure.id ? .solid(SceneColors.selection) : .ghost
        }
    }

    /// Hits arrive nearest-first. While something is selected everything else is an x-ray
    /// ghost, so prefer the selected structure — that keeps it tappable through the cortex
    /// in front of it.
    func handleTap(_ hits: [SCNHitTestResult]) {
        let ids = hits.compactMap { structureID(for: $0.node) }
        let preferred = ids.first { $0 == selectedStructure?.id }
        if let id = preferred ?? ids.first, let structure = structuresByID[id] {
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
            .solid(structuresByID[id].map { UIColor($0.color) } ?? SceneColors.ghost)
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
    @State private var searching = false

    var body: some View {
        ZStack {
            Theme.stage.ignoresSafeArea()

            if vm.isLoading || vm.loadFailed {
                LoadingStateView(message: "Loading brain atlas…", failed: vm.loadFailed)
            } else {
                SceneKitView(scene: vm.scene, onTap: { hits in
                    vm.handleTap(hits)
                }, recenterTrigger: vm.recenterTrigger)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityLabel("3D brain atlas. Tap a structure to select it.")

                VStack(spacing: 12) {
                    Spacer()
                    if !vm.hasSelected {
                        Label("Tap any structure to name it", systemImage: "hand.tap.fill")
                            .font(Theme.font(.subheadline))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassEffect(.regular, in: .capsule)
                            .transition(.blurReplace)
                    }
                    SceneControlsBar(
                        explodeFactor: Binding(get: { vm.explodeFactor }, set: { vm.setExplode($0) }),
                        onRecenter: { vm.recenterTrigger.toggle() }
                    )
                    if let s = vm.selectedStructure {
                        SelectionCard(structure: s) { vm.clearSelection() }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: Theme.Metrics.panelMaxWidth)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .animation(.snappy, value: vm.selectedStructure?.id)
                .animation(.snappy, value: vm.hasSelected)
            }
        }
        .searchable(text: $vm.searchQuery, isPresented: $searching,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search structures")
        .searchSuggestions {
            ForEach(vm.searchResults) { s in
                Button {
                    vm.select(s)
                    vm.searchQuery = ""
                    searching = false
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.displayName)
                                .foregroundStyle(Theme.textPrimary)
                            if let region = s.hierarchyPath.last {
                                Text(region.sentenceCased)
                                    .font(Theme.font(.caption))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    } icon: {
                        Circle()
                            .fill(s.color)
                            .frame(width: 12, height: 12)
                    }
                }
                .accessibilityLabel(s.displayName)
            }
        }
        .autocorrectionDisabled()
        .task { await vm.load() }
    }
}

/// The selected structure's name and place in the atlas hierarchy, floating over the brain.
private struct SelectionCard: View {
    let structure: BrainStructure
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Matches the structure's highlight in the scene.
            Circle()
                .fill(Color(SceneColors.selection))
                .frame(width: 12, height: 12)
                .shadow(color: Color(SceneColors.selection).opacity(0.7), radius: 4)
                .padding(.top, 5)
                .accessibilityHidden(true)

            StructureTitle(name: structure.displayName, breadcrumb: structure.breadcrumb)
                .frame(maxWidth: .infinity, alignment: .leading)

            ClearButton(label: "Clear selection", action: onClear)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(corners: .concentric(minimum: 24), isUniform: false))
    }
}
