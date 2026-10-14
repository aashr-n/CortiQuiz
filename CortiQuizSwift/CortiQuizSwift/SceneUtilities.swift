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

// MARK: - Structure Styles (3D modes)

/// How a structure draws in the 3D modes.
nonisolated enum NodeStyle: Equatable {
    /// Lit and opaque, in this color.
    case solid(UIColor)
    /// X-ray: only the silhouette glows faintly, so the structures inside stay visible.
    case ghost
}

extension SCNNode {
    /// Lit by the scene's lights normally; with `xray` 1, replaced by a rim glow that is added
    /// to what's behind (the material blends additively and skips the depth buffer then).
    /// One program for both looks, so switching a structure's style never recompiles a shader.
    nonisolated private static let styleShaderSource = """
    #pragma arguments
    float xray;
    float rimGain;
    float glow;

    #pragma body
    if (xray > 0.5) {
        float3 n = normalize(_surface.normal);
        float3 v = normalize(_surface.view);
        float rim = pow(1.0 - saturate(abs(dot(n, v))), 3.0);
        _output.color = float4(_surface.diffuse.rgb * (0.002 + rim * rimGain), 1.0);
    } else {
        _output.color.rgb += _surface.diffuse.rgb * glow;
    }
    """

    nonisolated func applyStyle(_ style: NodeStyle) {
        let isGhost = style == .ghost
        if let geom = geometry {
            for mat in geom.materials {
                if mat.shaderModifiers?[.fragment] != Self.styleShaderSource {
                    mat.shaderModifiers = [.fragment: Self.styleShaderSource]
                    mat.setValue(NSNumber(value: Float(SceneColors.ghostRimGain)), forKey: "rimGain")
                    mat.setValue(NSNumber(value: Float(0)), forKey: "glow")
                }
                switch style {
                case .solid(let color): mat.diffuse.contents = color
                case .ghost: mat.diffuse.contents = SceneColors.ghost
                }
                mat.isDoubleSided = true
                mat.blendMode = isGhost ? .add : .alpha
                mat.writesToDepthBuffer = !isGhost
                // A switch, not a value to fade: halfway through an implicit animation the
                // shader would still be on the old branch with the new blending.
                SCNTransaction.begin()
                SCNTransaction.disableActions = true
                mat.setValue(NSNumber(value: Float(isGhost ? 1 : 0)), forKey: "xray")
                SCNTransaction.commit()
            }
        }
        for child in childNodes { child.applyStyle(style) }
    }
}

extension SCNNode {
    private static let pulseKey = "attentionPulse"

    /// Brighten and dim a solid structure a few times to draw the eye to it, then rest. Runs
    /// as an action, so the view only redraws while it pulses. Skipped with Reduce Motion.
    func pulseHighlight(times: Int = 3, period: TimeInterval = 0.75) {
        stopPulse()
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        runAction(Self.pulseAction(times: times, period: period), forKey: Self.pulseKey)
    }

    /// Built outside the main actor: SceneKit runs action blocks on its render thread.
    nonisolated private static func pulseAction(times: Int, period: TimeInterval) -> SCNAction {
        .sequence([
            .customAction(duration: period * Double(times)) { node, elapsed in
                // 0 → peak → 0 once per period.
                node.setGlow(Float(0.3 * (1 - cos(2 * .pi * Double(elapsed) / period))))
            },
            .run { node in node.setGlow(0) },
        ])
    }

    func stopPulse() {
        guard action(forKey: Self.pulseKey) != nil else { return }
        removeAction(forKey: Self.pulseKey)
        setGlow(0)
    }

    nonisolated private func setGlow(_ glow: Float) {
        for mat in geometry?.materials ?? [] {
            mat.setValue(NSNumber(value: glow), forKey: "glow")
        }
        for child in childNodes { child.setGlow(glow) }
    }
}

/// Restyle structure nodes in one animated transaction (colors fade; the ghost/solid switch
/// is immediate). `style` maps a structure id to its style.
func restyleNodes(
    _ nodes: [String: SCNNode],
    duration: TimeInterval = 0.25,
    style: (String) -> NodeStyle
) {
    SCNTransaction.begin()
    SCNTransaction.animationDuration = duration
    for (id, node) in nodes {
        node.applyStyle(style(id))
    }
    SCNTransaction.commit()
}

// MARK: - Hero Glow (home screen)

extension SCNNode {
    /// The home screen's look: a dark, unlit surface whose silhouettes glow in `color`, so
    /// every gyrus is outlined. `fill` (0…1) lifts the whole surface toward `color`.
    nonisolated private static let glowShaderSource = """
    #pragma arguments
    float fill;

    #pragma body
    float3 n = normalize(_surface.normal);
    float3 v = normalize(_surface.view);
    float rim = pow(1.0 - saturate(abs(dot(n, v))), 2.5);
    _output.color = float4(_surface.diffuse.rgb * (fill + rim * 1.2), 1.0);
    """

    nonisolated func applyGlow(_ color: UIColor, fill: CGFloat) {
        if let geom = geometry {
            for mat in geom.materials {
                if mat.shaderModifiers?[.fragment] != Self.glowShaderSource {
                    mat.lightingModel = .constant
                    mat.isDoubleSided = false
                    mat.shaderModifiers = [.fragment: Self.glowShaderSource]
                }
                mat.diffuse.contents = color
                mat.setValue(NSNumber(value: Float(fill)), forKey: "fill")
            }
        }
        for child in childNodes { child.applyGlow(color, fill: fill) }
    }
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
