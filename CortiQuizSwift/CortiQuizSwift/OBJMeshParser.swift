import Foundation

// MARK: - OBJ Mesh Data

nonisolated struct OBJVertex: Sendable {
    let x: Float
    let y: Float
    let z: Float
}

nonisolated struct OBJFace: Sendable {
    let a: Int
    let b: Int
    let c: Int
}

nonisolated struct OBJMesh: Sendable {
    let vertices: [OBJVertex]
    let faces: [OBJFace]
}

// MARK: - Parsed Mesh Cache

/// Caches parsed `OBJMesh` values so MRI Quiz re-entry doesn't re-read and re-parse every
/// `.obj` from disk. `OBJMesh` is an immutable value type, so it's safe to share.
nonisolated final class MeshCache: @unchecked Sendable {
    static let shared = MeshCache()
    private var cache: [String: OBJMesh] = [:]
    private let queue = DispatchQueue(label: "objmeshcache")

    func mesh(for fileName: String, build: () -> OBJMesh?) -> OBJMesh? {
        if let hit = queue.sync(execute: { cache[fileName] }) { return hit }
        guard let built = build() else { return nil }
        queue.sync { cache[fileName] = built }
        return built
    }
}

// MARK: - Slice Visibility

nonisolated struct SliceFootprint: Sendable {
    let areaPixels: CGFloat
    let maxDimensionPixels: CGFloat
    let triangleCount: Int

    var visibilityScore: CGFloat {
        areaPixels + maxDimensionPixels * 16 + CGFloat(triangleCount)
    }
}

nonisolated struct SliceCandidate: Sendable {
    /// World-space coordinate along the slice axis (Z for axial, Y coronal, X sagittal).
    let coord: Float
    let thickness: Float
    let footprint: SliceFootprint
}

nonisolated struct TargetCandidate: Sendable {
    let nodeIndex: Int
    let slices: [SliceCandidate]
}

// MARK: - OBJ Parser + Slice Classification

nonisolated enum OBJMeshParser {
    private static let snapshotSize: CGFloat = 512
    private static let orthographicScale: CGFloat = 90
    private static let minAreaPixels: CGFloat = 180
    private static let minDimensionPixels: CGFloat = 24
    private static let minTriangles = 20
    private static let maxSlicesPerTarget = 8

    static func loadMesh(fileName: String) -> OBJMesh? {
        MeshCache.shared.mesh(for: fileName) { parseMesh(fileName: fileName) }
    }

    private static func parseMesh(fileName: String) -> OBJMesh? {
        let resourceName = fileName.replacingOccurrences(of: ".obj", with: "")
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "obj"),
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }

        var vertices: [OBJVertex] = []
        var faces: [OBJFace] = []

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("v ") {
                let parts = line.split(separator: " ")
                guard parts.count >= 4,
                      let x = Float(parts[1]),
                      let y = Float(parts[2]),
                      let z = Float(parts[3])
                else { continue }
                vertices.append(OBJVertex(x: x, y: y, z: z))
            } else if line.hasPrefix("f ") {
                let indices = line
                    .split(separator: " ")
                    .dropFirst()
                    .compactMap { token -> Int? in
                        guard let vt = token.split(separator: "/").first,
                              let idx = Int(vt)
                        else { return nil }
                        return idx - 1
                    }
                guard indices.count >= 3 else { continue }
                let first = indices[0]
                for i in 1..<(indices.count - 1) {
                    faces.append(OBJFace(a: first, b: indices[i], c: indices[i + 1]))
                }
            }
        }

        guard !vertices.isEmpty, !faces.isEmpty else { return nil }
        return OBJMesh(vertices: vertices, faces: faces)
    }

    /// Component of a vertex along the slice axis.
    private static func sliceComponent(_ v: OBJVertex, _ axis: MRIAxis) -> Float {
        switch axis {
        case .axial:    return v.z
        case .coronal:  return v.y
        case .sagittal: return v.x
        }
    }

    /// The two in-plane components of a vertex for the slice axis (the visible footprint).
    private static func footprintComponents(_ v: OBJVertex, _ axis: MRIAxis) -> (Float, Float) {
        switch axis {
        case .axial:    return (v.x, v.y)
        case .coronal:  return (v.x, v.z)
        case .sagittal: return (v.y, v.z)
        }
    }

    static func sliceFootprint(mesh: OBJMesh, axis: MRIAxis, coord: Float, thickness: Float) -> SliceFootprint? {
        let lower = coord - thickness
        var minA = Float.greatestFiniteMagnitude
        var maxA = -Float.greatestFiniteMagnitude
        var minB = Float.greatestFiniteMagnitude
        var maxB = -Float.greatestFiniteMagnitude
        var triangleCount = 0

        for face in mesh.faces {
            guard face.a < mesh.vertices.count,
                  face.b < mesh.vertices.count,
                  face.c < mesh.vertices.count
            else { continue }

            let v1 = mesh.vertices[face.a]
            let v2 = mesh.vertices[face.b]
            let v3 = mesh.vertices[face.c]
            let s1 = sliceComponent(v1, axis)
            let s2 = sliceComponent(v2, axis)
            let s3 = sliceComponent(v3, axis)
            let faceMin = min(s1, min(s2, s3))
            let faceMax = max(s1, max(s2, s3))

            guard faceMax >= lower, faceMin <= coord else { continue }

            triangleCount += 1
            for vertex in [v1, v2, v3] {
                let (a, b) = footprintComponents(vertex, axis)
                minA = min(minA, a); maxA = max(maxA, a)
                minB = min(minB, b); maxB = max(maxB, b)
            }
        }

        guard triangleCount > 0 else { return nil }

        let pxPerUnit = snapshotSize / orthographicScale
        let w = CGFloat(maxA - minA) * pxPerUnit
        let h = CGFloat(maxB - minB) * pxPerUnit
        return SliceFootprint(areaPixels: w * h, maxDimensionPixels: max(w, h), triangleCount: triangleCount)
    }

    static func visibleSliceCandidates(
        for structure: BrainStructure,
        axis: MRIAxis,
        boundingBoxMin: Float,
        boundingBoxMax: Float
    ) -> [SliceCandidate] {
        guard let fileName = structure.modelFileName,
              let mesh = loadMesh(fileName: fileName)
        else { return [] }

        let range = max(boundingBoxMax - boundingBoxMin, 0.1)
        let thickness = adaptiveThickness(for: range)
        let sampleCount = 21
        var candidates: [SliceCandidate] = []

        for sample in 1...sampleCount {
            let t = Float(sample) / Float(sampleCount + 1)
            let coord = boundingBoxMin + range * t
            guard let fp = sliceFootprint(mesh: mesh, axis: axis, coord: coord, thickness: thickness),
                  fp.triangleCount >= minTriangles,
                  fp.areaPixels >= minAreaPixels,
                  fp.maxDimensionPixels >= minDimensionPixels
            else { continue }
            candidates.append(SliceCandidate(coord: coord, thickness: thickness, footprint: fp))
        }

        return candidates
            .sorted { $0.footprint.visibilityScore > $1.footprint.visibilityScore }
            .prefix(maxSlicesPerTarget)
            .map { $0 }
    }

    static func classifyQuizTargets(
        entries: [(nodeIndex: Int, structure: BrainStructure, axisMin: Float, axisMax: Float)],
        axis: MRIAxis
    ) -> [TargetCandidate] {
        var targets: [TargetCandidate] = []
        for entry in entries {
            let slices = visibleSliceCandidates(
                for: entry.structure,
                axis: axis,
                boundingBoxMin: entry.axisMin,
                boundingBoxMax: entry.axisMax
            )
            guard !slices.isEmpty else { continue }
            targets.append(TargetCandidate(nodeIndex: entry.nodeIndex, slices: slices))
        }
        return targets
    }

    private static func adaptiveThickness(for range: Float) -> Float {
        min(max(range * 0.18, 3.0), 7.0)
    }
}
