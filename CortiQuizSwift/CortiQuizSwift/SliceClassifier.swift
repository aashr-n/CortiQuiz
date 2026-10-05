import SceneKit

// MARK: - Triangle Mesh

/// Flat triangle list read straight out of an already-loaded SceneKit node, so MRI Quiz can
/// predict how big a structure will look in a slice without re-reading its OBJ from disk.
nonisolated struct TriangleMesh: Sendable {
    private(set) var vertices: [SIMD3<Float>] = []
    /// Three vertex indices per triangle.
    private(set) var indices: [UInt32] = []

    var triangleCount: Int { indices.count / 3 }

    init(vertices: [SIMD3<Float>], indices: [UInt32]) {
        self.vertices = vertices
        self.indices = indices
    }

    /// Collects the triangles of `node` and its descendants, in `node`'s coordinate space
    /// (world space for atlas models, whose node transforms are identity).
    init(node: SCNNode) {
        append(node, transform: matrix_identity_float4x4)
    }

    private mutating func append(_ node: SCNNode, transform: simd_float4x4) {
        if let geometry = node.geometry,
           let source = geometry.sources(for: .vertex).first {
            let base = UInt32(vertices.count)
            if appendVertices(source, transform: transform) {
                for element in geometry.elements where element.primitiveType == .triangles {
                    appendIndices(element, base: base)
                }
            }
        }
        for child in node.childNodes {
            append(child, transform: transform * child.simdTransform)
        }
    }

    private mutating func appendVertices(_ source: SCNGeometrySource, transform: simd_float4x4) -> Bool {
        let bytes = source.bytesPerComponent
        guard source.usesFloatComponents, source.componentsPerVector >= 3, bytes == 4 || bytes == 8 else {
            return false
        }
        let count = source.vectorCount
        let stride = source.dataStride
        let offset = source.dataOffset
        let isIdentity = transform == matrix_identity_float4x4
        guard source.data.count >= offset + max(count - 1, 0) * stride + 3 * bytes else { return false }

        vertices.reserveCapacity(vertices.count + count)
        source.data.withUnsafeBytes { raw in
            for i in 0..<count {
                let p = offset + i * stride
                var v: SIMD3<Float>
                if bytes == 4 {
                    v = SIMD3(raw.loadUnaligned(fromByteOffset: p, as: Float.self),
                              raw.loadUnaligned(fromByteOffset: p + 4, as: Float.self),
                              raw.loadUnaligned(fromByteOffset: p + 8, as: Float.self))
                } else {
                    v = SIMD3(Float(raw.loadUnaligned(fromByteOffset: p, as: Double.self)),
                              Float(raw.loadUnaligned(fromByteOffset: p + 8, as: Double.self)),
                              Float(raw.loadUnaligned(fromByteOffset: p + 16, as: Double.self)))
                }
                if !isIdentity {
                    let t = transform * SIMD4(v, 1)
                    v = SIMD3(t.x, t.y, t.z)
                }
                vertices.append(v)
            }
        }
        return true
    }

    private mutating func appendIndices(_ element: SCNGeometryElement, base: UInt32) {
        let width = element.bytesPerIndex
        let count = element.primitiveCount * 3
        guard [1, 2, 4].contains(width), element.data.count >= count * width else { return }

        indices.reserveCapacity(indices.count + count)
        element.data.withUnsafeBytes { raw in
            for i in 0..<count {
                let index: UInt32
                switch width {
                case 1: index = UInt32(raw.load(fromByteOffset: i, as: UInt8.self))
                case 2: index = UInt32(raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self))
                default: index = raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                }
                indices.append(base + index)
            }
        }
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
    let structureID: String
    let slices: [SliceCandidate]
}

// MARK: - Slice Classification

/// Picks the slices where an MRI Quiz target is actually visible, by measuring the
/// in-plane extent of the target's triangles that cross each candidate slab.
nonisolated enum SliceClassifier {
    /// A slice qualifies only if the target spans at least this much of the 512 px snapshot.
    /// 14 px is ≈10 pt on an iPhone-width slice view: small nuclei (subthalamic, red nucleus)
    /// still qualify, slivers don't.
    static let minDimensionPixels: CGFloat = 14
    static let minAreaPixels: CGFloat = 80
    static let minTriangles = 20
    static let maxSlicesPerTarget = 8
    static let samplesPerStructure = 21

    /// (slice-axis component, in-plane components) of a vertex.
    private static func components(_ axis: MRIAxis) -> (slice: Int, a: Int, b: Int) {
        switch axis {
        case .axial:    return (2, 0, 1)
        case .coronal:  return (1, 0, 2)
        case .sagittal: return (0, 1, 2)
        }
    }

    /// How the target looks in the slab `[coord - thickness, coord]`, in snapshot pixels.
    static func footprint(mesh: TriangleMesh, axis: MRIAxis, coord: Float, thickness: Float) -> SliceFootprint? {
        let (k, a, b) = components(axis)
        let lower = coord - thickness
        var minA = Float.greatestFiniteMagnitude, maxA = -Float.greatestFiniteMagnitude
        var minB = Float.greatestFiniteMagnitude, maxB = -Float.greatestFiniteMagnitude
        var triangleCount = 0
        let v = mesh.vertices
        let idx = mesh.indices
        let n = v.count

        for t in stride(from: 0, to: idx.count - 2, by: 3) {
            let i0 = Int(idx[t]), i1 = Int(idx[t + 1]), i2 = Int(idx[t + 2])
            guard i0 < n, i1 < n, i2 < n else { continue }
            let p0 = v[i0], p1 = v[i1], p2 = v[i2]
            guard max(p0[k], p1[k], p2[k]) >= lower, min(p0[k], p1[k], p2[k]) <= coord else { continue }

            triangleCount += 1
            minA = min(minA, p0[a], p1[a], p2[a]); maxA = max(maxA, p0[a], p1[a], p2[a])
            minB = min(minB, p0[b], p1[b], p2[b]); maxB = max(maxB, p0[b], p1[b], p2[b])
        }

        guard triangleCount > 0 else { return nil }
        let w = CGFloat(maxA - minA) * MRISlicing.pixelsPerUnit
        let h = CGFloat(maxB - minB) * MRISlicing.pixelsPerUnit
        return SliceFootprint(areaPixels: w * h, maxDimensionPixels: max(w, h), triangleCount: triangleCount)
    }

    /// The best (most visible) qualifying slices through a structure spanning
    /// `lower...upper` along `axis`.
    static func visibleSlices(mesh: TriangleMesh, axis: MRIAxis, lower: Float, upper: Float) -> [SliceCandidate] {
        let range = max(upper - lower, 0.1)
        let thickness = min(max(range * 0.18, 3.0), 7.0)
        var candidates: [SliceCandidate] = []

        for sample in 1...samplesPerStructure {
            let coord = lower + range * Float(sample) / Float(samplesPerStructure + 1)
            guard let fp = footprint(mesh: mesh, axis: axis, coord: coord, thickness: thickness),
                  fp.triangleCount >= minTriangles,
                  fp.areaPixels >= minAreaPixels,
                  fp.maxDimensionPixels >= minDimensionPixels
            else { continue }
            candidates.append(SliceCandidate(coord: coord, thickness: thickness, footprint: fp))
        }

        return Array(
            candidates
                .sorted { $0.footprint.visibilityScore > $1.footprint.visibilityScore }
                .prefix(maxSlicesPerTarget)
        )
    }

    /// Quiz-worthy slices for every structure, per axis. Returns nil if the calling task is
    /// cancelled part-way, so a partial result is never cached.
    static func classify(_ ordered: [(node: SCNNode, structure: BrainStructure)]) -> [MRIAxis: [TargetCandidate]]? {
        var result: [MRIAxis: [TargetCandidate]] = [:]
        for entry in ordered {
            if Task.isCancelled { return nil }
            let mesh = TriangleMesh(node: entry.node)
            guard mesh.triangleCount > 0 else { continue }
            let (bmin, bmax) = entry.node.boundingBox
            for axis in MRIAxis.allCases {
                let k = components(axis).slice
                let lower = [bmin.x, bmin.y, bmin.z][k]
                let upper = [bmax.x, bmax.y, bmax.z][k]
                let slices = visibleSlices(mesh: mesh, axis: axis, lower: lower, upper: upper)
                if !slices.isEmpty {
                    result[axis, default: []].append(TargetCandidate(structureID: entry.structure.id, slices: slices))
                }
            }
        }
        return result
    }
}

// MARK: - Classification Cache

/// Classification depends only on the static atlas, so it runs once per app session (first
/// MRI Quiz visit) and is reused on re-entry. Holds only small candidate lists, not meshes.
nonisolated final class SliceCandidateCache: @unchecked Sendable {
    static let shared = SliceCandidateCache()
    private let lock = NSLock()
    private var cached: [MRIAxis: [TargetCandidate]]?

    func candidates(orCompute compute: () -> [MRIAxis: [TargetCandidate]]?) -> [MRIAxis: [TargetCandidate]]? {
        if let hit = lock.withLock({ cached }) { return hit }
        guard let computed = compute() else { return nil }
        lock.withLock { cached = computed }
        return computed
    }
}
