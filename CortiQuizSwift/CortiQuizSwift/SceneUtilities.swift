import SceneKit

// MARK: - Background Work

/// Runs synchronous, CPU-heavy work (mesh loading, slice classification) off the main actor.
/// It's a structured call, so when the calling task is cancelled — e.g. SwiftUI's `.task`
/// when the view disappears — `work` sees it via `Task.isCancelled` and can stop early.
nonisolated enum Background {
    @concurrent static func run<T>(_ work: @Sendable () -> T) async -> T {
        work()
    }
}

// MARK: - Shared SCNNode Material Helpers

extension SCNNode {
    /// Apply a solid color to all materials on this node and its children.
    nonisolated func applyColor(_ color: UIColor, doubleSided: Bool = true) {
        if let geom = geometry {
            for mat in geom.materials {
                mat.diffuse.contents = color
                mat.isDoubleSided = doubleSided
            }
        }
        for child in childNodes { child.applyColor(color, doubleSided: doubleSided) }
    }
}

/// Recolor structure nodes in one animated transaction. `style` maps a structure id to
/// its color and opacity.
func restyleNodes(
    _ nodes: [String: SCNNode],
    duration: TimeInterval = 0.25,
    style: (String) -> (color: UIColor, opacity: CGFloat)
) {
    SCNTransaction.begin()
    SCNTransaction.animationDuration = duration
    for (id, node) in nodes {
        let s = style(id)
        node.applyColor(s.color)
        node.opacity = s.opacity
    }
    SCNTransaction.commit()
}

// MARK: - Explode View

/// Pushes each structure out from the brain center by `factor` × its offset. Mesh vertices
/// are already in world space (node positions start at zero), so factor 0 is the natural layout.
nonisolated struct ExplodeLayout {
    var centers: [String: SCNVector3] = [:]
    var brainCenter = SCNVector3Zero

    func apply(_ factor: Float, to nodes: [String: SCNNode]) {
        for (id, node) in nodes {
            guard let c = centers[id] else { continue }
            node.position = SCNVector3(
                (c.x - brainCenter.x) * factor,
                (c.y - brainCenter.y) * factor,
                (c.z - brainCenter.z) * factor
            )
        }
    }
}

// MARK: - MRI Clip Shader (Uniform-Based)

extension SCNNode {
    /// Stable shader source using uniforms — compiled once, updated via setValue.
    nonisolated private static let clipShaderSource = """
    #pragma arguments
    float clipZ;
    float clipThickness;

    #pragma body
    float vz = _surface.position.z;
    if (vz > clipZ || vz < clipZ - clipThickness) {
        discard_fragment();
    }
    """

    /// Install the clip shader once during setup. Does NOT recompile on value changes.
    nonisolated func installClipShader(color: UIColor) {
        if let geom = geometry {
            for mat in geom.materials {
                mat.shaderModifiers = [.fragment: Self.clipShaderSource]
                mat.isDoubleSided = true
                mat.diffuse.contents = color
                // Set initial uniform values
                mat.setValue(NSNumber(value: Float(0)), forKey: "clipZ")
                mat.setValue(NSNumber(value: Float(2)), forKey: "clipThickness")
            }
        }
        for child in childNodes { child.installClipShader(color: color) }
    }

    /// Update clip uniforms without shader recompilation.
    nonisolated func updateClipUniforms(viewClipZ: Float, thickness: Float) {
        if let geom = geometry {
            for mat in geom.materials {
                mat.setValue(NSNumber(value: viewClipZ), forKey: "clipZ")
                mat.setValue(NSNumber(value: thickness), forKey: "clipThickness")
            }
        }
        for child in childNodes { child.updateClipUniforms(viewClipZ: viewClipZ, thickness: thickness) }
    }

    /// Update diffuse color without touching the shader.
    nonisolated func updateDiffuseColor(_ color: UIColor) {
        if let geom = geometry {
            for mat in geom.materials {
                mat.diffuse.contents = color
            }
        }
        for child in childNodes { child.updateDiffuseColor(color) }
    }
}
