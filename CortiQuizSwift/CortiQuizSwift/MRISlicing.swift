import SceneKit

// MARK: - MRI Axis

enum MRIAxis: Int, CaseIterable, Identifiable {
    case axial, coronal, sagittal
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .axial: return "Axial"
        case .coronal: return "Coronal"
        case .sagittal: return "Sagittal"
        }
    }
    var labelStart: String {
        switch self {
        case .axial: return "Inferior"
        case .coronal: return "Posterior"
        case .sagittal: return "Left"
        }
    }
    var labelEnd: String {
        switch self {
        case .axial: return "Superior"
        case .coronal: return "Anterior"
        case .sagittal: return "Right"
        }
    }
}

// MARK: - Shared MRI Slice Geometry

/// Camera, clip, and slice-plane geometry shared by MRI Mode and MRI Quiz.
///
/// The clip shader (see `SceneUtilities`) discards fragments by *view-space* depth, and the
/// orthographic camera always sits `cameraZ` units out along the slice axis. That's why the
/// same `clipCoord - cameraZ` mapping works for every axis — only the camera orientation and
/// the world-space plane transform change.
enum MRISlicing {
    static let cameraZ: Float = 300

    /// Position + orient the orthographic camera to look down the given slice axis.
    static func orientCamera(_ cam: SCNNode, for axis: MRIAxis) {
        switch axis {
        case .axial:    // Slicing Z. Look from Superior (+Z) to Inferior (-Z).
            cam.position = SCNVector3(0, 0, cameraZ)
            cam.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, -1, 0), localFront: SCNVector3(0, 0, -1))
        case .coronal:  // Slicing Y. Look from Anterior (+Y) to Posterior (-Y).
            cam.position = SCNVector3(0, cameraZ, 0)
            cam.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
        case .sagittal: // Slicing X. Look from Right (+X) to Left (-X).
            cam.position = SCNVector3(cameraZ, 0, 0)
            cam.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 0, -1))
        }
    }

    /// Min/max extent along the slice axis.
    static func extent(_ bounds: MiniBrainBounds, for axis: MRIAxis) -> (min: Float, max: Float) {
        switch axis {
        case .axial:    return (bounds.minZ, bounds.maxZ)
        case .coronal:  return (bounds.minY, bounds.maxY)
        case .sagittal: return (bounds.minX, bounds.maxX)
        }
    }

    /// View-space clip depth fed to the clip shader for a world-space slice coordinate.
    static func viewClip(forCoord coord: Float) -> Float {
        coord - cameraZ
    }

    /// World-space position of the slice-plane indicator in the mini brain.
    static func planePosition(forCoord coord: Float, axis: MRIAxis) -> SCNVector3 {
        switch axis {
        case .axial:    return SCNVector3(0, 0, coord)
        case .coronal:  return SCNVector3(0, coord, 0)
        case .sagittal: return SCNVector3(coord, 0, 0)
        }
    }

    /// Orientation of the slice-plane indicator in the mini brain.
    static func planeEuler(for axis: MRIAxis) -> SCNVector3 {
        switch axis {
        case .axial:    return SCNVector3(0, 0, 0)
        case .coronal:  return SCNVector3(Float.pi / 2, 0, 0)
        case .sagittal: return SCNVector3(0, Float.pi / 2, 0)
        }
    }
}
