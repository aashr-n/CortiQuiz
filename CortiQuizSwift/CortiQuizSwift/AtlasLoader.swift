import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO

// MARK: - Atlas Loader

nonisolated enum AtlasLoader {

    /// Parsed once per app session; Swift initializes static lets lazily and thread-safely.
    private static let cached = parse()

    static func load() -> [BrainStructure] { cached }

    private static func parse() -> [BrainStructure] {
        guard let url = Bundle.main.url(forResource: "atlasStructure", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([AtlasEntry].self, from: data)
        else {
            print("Failed to load atlasStructure.json")
            return []
        }
        
        // Map DataSource IDs to model file names
        var dsToFile: [String: String] = [:]
        for e in entries where e.type == "DataSource" {
            if let src = e.source {
                let objName = src.replacingOccurrences(of: "models/", with: "")
                    .replacingOccurrences(of: ".vtk", with: ".obj")
                dsToFile[e.id] = objName
            }
        }
        
        // Build structures
        var structures: [BrainStructure] = []
        for e in entries where e.type == "Structure" || e.type == "Group" {
            let isGroup = e.type == "Group"
            let name = e.annotation?.name ?? e.id.replacingOccurrences(of: "#", with: "")
            let color = Color.fromRGB(e.renderOption?.color)
            
            var modelFile: String? = nil
            if let selectors = e.sourceSelector {
                for sel in selectors {
                    if sel.type.isGeometry, let ds = sel.dataSource {
                        modelFile = dsToFile[ds]
                        break
                    }
                }
            }
            
            structures.append(BrainStructure(
                id: e.id,
                name: name,
                color: color,
                modelFileName: modelFile,
                hierarchyPath: [],
                isGroup: isGroup,
                memberIDs: e.member ?? []
            ))
        }
        
        // Build hierarchy paths
        let structByID = Dictionary(structures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var parentMap: [String: String] = [:]
        for s in structures where s.isGroup {
            for m in s.memberIDs { parentMap[m] = s.id }
        }
        
        for i in structures.indices {
            structures[i].parentID = parentMap[structures[i].id]
            var path: [String] = []
            var current = structures[i].id
            while let pid = parentMap[current], let parent = structByID[pid] {
                path.insert(parent.name, at: 0)
                current = pid
            }
            structures[i].hierarchyPath = path
        }
        
        return structures
    }
}

// MARK: - Model Loader (OBJ → SCNNode)

nonisolated final class ModelCache: @unchecked Sendable {
    static let shared = ModelCache()
    private var cache: [String: SCNNode] = [:]
    private let queue = DispatchQueue(label: "modelcache")
    
    /// Returns a deep clone of the cached template. Loading and cloning both happen on the
    /// serial queue, so two modes loading at once never parse the same file twice or clone
    /// a template from two threads.
    func node(for fileName: String) -> SCNNode? {
        queue.sync {
            if let cached = cache[fileName] { return Self.deepClone(cached) }

            guard let url = Bundle.main.url(forResource: fileName.replacingOccurrences(of: ".obj", with: ""),
                                             withExtension: "obj") else {
                return nil
            }

            let asset = MDLAsset(url: url)
            guard asset.count > 0 else { return nil }
            let node = SCNNode(mdlObject: asset.object(at: 0))
            node.name = fileName
            cache[fileName] = node
            return Self.deepClone(node)
        }
    }
    
    /// Deep clone: copies geometry + materials so mutations don't bleed across modes
    private static func deepClone(_ node: SCNNode) -> SCNNode {
        let clone = node.clone()
        if let geom = clone.geometry {
            clone.geometry = geom.copy() as? SCNGeometry
            clone.geometry?.materials = geom.materials.map { $0.copy() as! SCNMaterial }
        }
        for child in clone.childNodes {
            let deepChild = deepClone(child)
            clone.replaceChildNode(child, with: deepChild)
        }
        return clone
    }
}
