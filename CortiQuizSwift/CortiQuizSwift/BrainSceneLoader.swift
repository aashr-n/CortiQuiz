import SceneKit

// MARK: - Shared Brain Scene Loader

/// Result of building a brain scene on a background thread. Safe to hand to the MainActor.
nonisolated struct LoadedBrainScene {
    /// Every structure from the atlas (groups included), for hierarchy/search.
    let allStructures: [BrainStructure]
    /// Brain-only, model-backed, non-group structures — the set every mode renders.
    let structures: [BrainStructure]
    let scene: SCNScene
    /// id → node, for fast recolor/lookup.
    let nodes: [String: SCNNode]
    /// Same nodes in stable order alongside their structure (MRI modes index into this).
    let ordered: [(node: SCNNode, structure: BrainStructure)]
    /// id → that structure's bounding-box center (explode mode pushes nodes out from here).
    let nodeCenters: [String: SCNVector3]
    /// Mean of per-structure bounding-box centers (used to frame/explode).
    let center: SCNVector3
    /// Combined min/max extent across all loaded structures.
    let bounds: MiniBrainBounds
}

/// Loads the atlas and builds an `SCNScene` of the brain. Every mode shared this same
/// "filter brain structures → clone nodes → accumulate bounds/center" sequence; it now
/// lives here so the filter predicate and bounds math can't drift between modes.
nonisolated enum BrainSceneLoader {

    /// The canonical "is this a model-backed brain structure we quiz/render?" predicate.
    static func brainOnly(_ all: [BrainStructure]) -> [BrainStructure] {
        all.filter { $0.modelFileName != nil && $0.isBrainStructure && !$0.isGroup }
    }

    /// Build the scene. `configure` sets up each node's appearance (solid color, ghost,
    /// clip shader, …) and is called synchronously per node before it's added to the scene.
    static func load(configure: (SCNNode, BrainStructure) -> Void) -> LoadedBrainScene {
        let all = AtlasLoader.load()
        let brain = brainOnly(all)

        let scene = SCNScene()
        var nodes: [String: SCNNode] = [:]
        var ordered: [(node: SCNNode, structure: BrainStructure)] = []
        var nodeCenters: [String: SCNVector3] = [:]
        var bounds = MiniBrainBounds()
        var totalX: Float = 0, totalY: Float = 0, totalZ: Float = 0
        var count: Float = 0

        for s in brain {
            guard let fn = s.modelFileName, let node = ModelCache.shared.node(for: fn) else { continue }
            configure(node, s)
            node.name = s.id
            scene.rootNode.addChildNode(node)
            nodes[s.id] = node
            ordered.append((node: node, structure: s))

            let (bmin, bmax) = node.boundingBox
            let cx = (bmin.x + bmax.x) / 2
            let cy = (bmin.y + bmax.y) / 2
            let cz = (bmin.z + bmax.z) / 2
            nodeCenters[s.id] = SCNVector3(cx, cy, cz)
            totalX += cx; totalY += cy; totalZ += cz
            count += 1

            bounds.minX = min(bounds.minX, bmin.x); bounds.maxX = max(bounds.maxX, bmax.x)
            bounds.minY = min(bounds.minY, bmin.y); bounds.maxY = max(bounds.maxY, bmax.y)
            bounds.minZ = min(bounds.minZ, bmin.z); bounds.maxZ = max(bounds.maxZ, bmax.z)
        }

        let center = count > 0
            ? SCNVector3(totalX / count, totalY / count, totalZ / count)
            : SCNVector3Zero

        return LoadedBrainScene(
            allStructures: all,
            structures: brain,
            scene: scene,
            nodes: nodes,
            ordered: ordered,
            nodeCenters: nodeCenters,
            center: center,
            bounds: bounds
        )
    }
}
