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
    let z: Float
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
    private static let studyDimensionPixels: CGFloat = 32
    private static let studyMinSliceCandidates = 4
    private static let maxSlicesPerTarget = 8

    static func loadMesh(fileName: String) -> OBJMesh? {
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

    static func sliceFootprint(mesh: OBJMesh, z: Float, thickness: Float) -> SliceFootprint? {
        let lowerZ = z - thickness
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var triangleCount = 0

        for face in mesh.faces {
            guard face.a < mesh.vertices.count,
                  face.b < mesh.vertices.count,
                  face.c < mesh.vertices.count
            else { continue }

            let v1 = mesh.vertices[face.a]
            let v2 = mesh.vertices[face.b]
            let v3 = mesh.vertices[face.c]
            let faceMinZ = min(v1.z, min(v2.z, v3.z))
            let faceMaxZ = max(v1.z, max(v2.z, v3.z))

            guard faceMaxZ >= lowerZ, faceMinZ <= z else { continue }

            triangleCount += 1
            for vertex in [v1, v2, v3] {
                minX = min(minX, vertex.x)
                maxX = max(maxX, vertex.x)
                minY = min(minY, vertex.y)
                maxY = max(maxY, vertex.y)
            }
        }

        guard triangleCount > 0 else { return nil }

        let pxPerUnit = snapshotSize / orthographicScale
        let w = CGFloat(maxX - minX) * pxPerUnit
        let h = CGFloat(maxY - minY) * pxPerUnit
        return SliceFootprint(areaPixels: w * h, maxDimensionPixels: max(w, h), triangleCount: triangleCount)
    }

    static func visibleSliceCandidates(
        for structure: BrainStructure,
        boundingBoxMinZ: Float,
        boundingBoxMaxZ: Float
    ) -> [SliceCandidate] {
        guard let fileName = structure.modelFileName,
              let mesh = loadMesh(fileName: fileName)
        else { return [] }

        let zRange = max(boundingBoxMaxZ - boundingBoxMinZ, 0.1)
        let thickness = adaptiveThickness(for: zRange)
        let sampleCount = 21
        var candidates: [SliceCandidate] = []

        for sample in 1...sampleCount {
            let t = Float(sample) / Float(sampleCount + 1)
            let z = boundingBoxMinZ + zRange * t
            guard let fp = sliceFootprint(mesh: mesh, z: z, thickness: thickness),
                  fp.triangleCount >= minTriangles,
                  fp.areaPixels >= minAreaPixels,
                  fp.maxDimensionPixels >= minDimensionPixels
            else { continue }
            candidates.append(SliceCandidate(z: z, thickness: thickness, footprint: fp))
        }

        return candidates
            .sorted { $0.footprint.visibilityScore > $1.footprint.visibilityScore }
            .prefix(maxSlicesPerTarget)
            .map { $0 }
    }

    static func classifyQuizTargets(
        entries: [(nodeIndex: Int, structure: BrainStructure, minZ: Float, maxZ: Float)]
    ) -> [TargetCandidate] {
        var targets: [TargetCandidate] = []
        for entry in entries {
            let slices = visibleSliceCandidates(
                for: entry.structure,
                boundingBoxMinZ: entry.minZ,
                boundingBoxMaxZ: entry.maxZ
            )
            guard !slices.isEmpty else { continue }
            targets.append(TargetCandidate(nodeIndex: entry.nodeIndex, slices: slices))
        }
        return targets
    }

    private static func adaptiveThickness(for zRange: Float) -> Float {
        min(max(zRange * 0.18, 3.0), 7.0)
    }
}
