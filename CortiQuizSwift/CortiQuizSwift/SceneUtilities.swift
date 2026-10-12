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

// MARK: - MRI Cut Shader (Uniform-Based)

/// Which faces of a closed structure mesh a slice-scene node draws.
///
/// Looking past the cut plane, the first surface seen from a point *inside* a structure is
/// the inside of that structure's own wall (a back face); from a point *outside* every
/// structure it's some structure's outer wall (a front face). Drawing back faces in the
/// structure's color and front faces in the background color fills every cross-section
/// solidly, using only the surface meshes.
nonisolated enum CutFaces {
    case inside, outside
}

extension SCNNode {
    /// Discards everything between the camera and the cut plane. Compiled once; moving the
    /// cut only changes the `clipZ` uniform (view-space depth).
    nonisolated private static let cutShaderSource = """
    #pragma arguments
    float clipZ;

    #pragma body
    if (_surface.position.z > clipZ) {
        discard_fragment();
    }
    """

    /// Install the cut shader once during setup, drawing only `faces` in a flat `color`.
    nonisolated func installCutShader(color: UIColor, faces: CutFaces) {
        if let geom = geometry {
            for mat in geom.materials {
                mat.shaderModifiers = [.fragment: Self.cutShaderSource]
                mat.isDoubleSided = false
                mat.cullMode = faces == .inside ? .front : .back
                mat.lightingModel = .constant
                mat.diffuse.contents = color
                mat.setValue(NSNumber(value: Float(0)), forKey: "clipZ")
            }
        }
        for child in childNodes { child.installCutShader(color: color, faces: faces) }
    }

    /// Move the cut without shader recompilation.
    nonisolated func updateClipZ(_ viewClipZ: Float) {
        if let geom = geometry {
            for mat in geom.materials {
                mat.setValue(NSNumber(value: viewClipZ), forKey: "clipZ")
            }
        }
        for child in childNodes { child.updateClipZ(viewClipZ) }
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
