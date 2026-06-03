import SceneKit

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

    /// Apply transparency to all materials.
    nonisolated func applyTransparency(alpha: CGFloat) {
        if let geom = geometry {
            for mat in geom.materials {
                mat.diffuse.contents = UIColor.white.withAlphaComponent(alpha)
                mat.transparency = alpha
                mat.isDoubleSided = true
                mat.blendMode = .alpha
                mat.writesToDepthBuffer = false
            }
        }
        for child in childNodes { child.applyTransparency(alpha: alpha) }
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
    func updateClipUniforms(viewClipZ: Float, thickness: Float) {
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
