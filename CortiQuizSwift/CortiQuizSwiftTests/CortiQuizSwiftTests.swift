//
//  CortiQuizSwiftTests.swift
//  CortiQuizSwiftTests
//
//  Created by Aashray N on 3/2/26.
//

import Testing
import SceneKit
import SwiftUI
@testable import CortiQuizSwift

private func structure(_ id: String, _ name: String, parent: String? = nil, model: String? = nil) -> BrainStructure {
    BrainStructure(
        id: id,
        name: name,
        color: .white,
        modelFileName: model,
        hierarchyPath: [],
        isGroup: false,
        memberIDs: [],
        parentID: parent
    )
}

/// Deterministic RNG so probabilistic picker branches can be tested.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Names

struct BaseNameTests {

    @Test func baseNameRemovesAllLeftRightMarkers() async throws {
        let samples = [
            ("left putamen", "putamen"),
            ("right putamen", "putamen"),
            ("left-VIIA crusII-l1", "VIIA crusII-l1"),
            ("right-VI-l", "VI-l"),
            ("caudal part of left anterior cingulate gyrus", "caudal part of anterior cingulate gyrus"),
            ("right superior temporal gyrus (banks of right superior temporal sulcus)", "superior temporal gyrus (banks of superior temporal sulcus)")
        ]

        for (name, expected) in samples {
            #expect(structure("#test", name).baseName == expected)
        }
    }
}

// MARK: - Atlas

@MainActor
struct AtlasTests {
    let brain = BrainSceneLoader.brainOnly(AtlasLoader.load())

    @Test func brainOnlyHasEveryBrainStructureAndNothingElse() {
        #expect(brain.count == 255)
        for s in brain {
            let fn = try! #require(s.modelFileName)
            #expect(!fn.hasPrefix("Model_3_"), "skin leaked into brain set: \(fn)")
            let number = Int(fn.split(separator: "_")[1]) ?? 0
            #expect(!(4001...4100).contains(number), "muscle leaked into brain set: \(fn)")
        }
    }

    @Test func everyBrainStructureHasABundledModel() {
        for s in brain {
            let name = s.modelFileName!.replacingOccurrences(of: ".obj", with: "")
            #expect(Bundle.main.url(forResource: name, withExtension: "obj") != nil, "missing model \(name)")
        }
    }

    @Test func hierarchyIsRootedAtBrain() {
        for s in brain {
            #expect(s.hierarchyPath.first == "Brain", "\(s.name): \(s.hierarchyPath)")
            #expect(s.parentID != nil)
        }
    }

    @Test func hemispherePairsShareABaseName() {
        let names = Set(brain.map(\.name))
        #expect(names.contains("left putamen") && names.contains("right putamen"))
        let putamens = brain.filter { $0.baseName == "putamen" }
        #expect(putamens.count == 2)
    }
}

// MARK: - Quiz logic

@MainActor
struct QuizOptionBuilderTests {

    @Test func optionsAreFourUniqueNamesIncludingTheAnswer() {
        let pool = [
            structure("#lp", "left putamen", parent: "#basal"),
            structure("#rp", "right putamen", parent: "#basal"),
            structure("#lc", "left caudate nucleus", parent: "#basal"),
            structure("#rc", "right caudate nucleus", parent: "#basal"),
            structure("#gp", "left globus pallidus", parent: "#basal"),
            structure("#pons", "pons", parent: "#brainstem"),
            structure("#med", "medulla", parent: "#brainstem"),
        ]
        for _ in 0..<50 {
            let options = QuizOptionBuilder.makeOptions(target: pool[0], pool: pool)
            #expect(options.count == 4)
            #expect(Set(options).count == 4)
            #expect(options.contains("putamen"))
        }
    }

    @Test func siblingsArePreferredAsDistractors() {
        let pool = [
            structure("#a", "a", parent: "#g"), structure("#b", "b", parent: "#g"),
            structure("#c", "c", parent: "#g"), structure("#d", "d", parent: "#g"),
            structure("#x", "x", parent: "#other"), structure("#y", "y", parent: "#other"),
        ]
        for _ in 0..<50 {
            #expect(Set(QuizOptionBuilder.makeOptions(target: pool[0], pool: pool)) == ["a", "b", "c", "d"])
        }
    }
}

@MainActor
struct QuizTargetPickerTests {
    let names = ["amygdala", "hippocampus", "pons", "putamen"]

    @Test func flaggedStructuresComeFirstInQueueOrder() {
        let pick = QuizTargetPicker.pick(from: names, flagged: ["pons", "amygdala"], weak: [], exclude: [])
        #expect(pick == "pons")
    }

    @Test func alreadyAskedFlaggedStructuresAreSkipped() {
        let pick = QuizTargetPicker.pick(from: names, flagged: ["pons", "amygdala"], weak: [], exclude: ["pons"])
        #expect(pick == "amygdala")
    }

    @Test func neverRepeatsWithinASession() {
        for _ in 0..<50 {
            let pick = QuizTargetPicker.pick(from: names, flagged: [], weak: [], exclude: ["amygdala", "pons", "putamen"])
            #expect(pick == "hippocampus")
        }
    }

    @Test func weakSpotsArePickedWhenTheDiceSaySo() {
        var rng = SeededGenerator(state: 1)
        for _ in 0..<20 {
            let always = QuizTargetPicker.pick(from: names, flagged: [], weak: ["putamen"], exclude: [], weakChance: 1, using: &rng)
            #expect(always == "putamen")
        }
        var sawOther = false
        for _ in 0..<50 {
            let never = QuizTargetPicker.pick(from: names, flagged: [], weak: ["putamen"], exclude: [], weakChance: 0, using: &rng)
            if never != "putamen" { sawOther = true }
        }
        #expect(sawOther)
    }

    @Test func fallsBackToTheWholePoolOnceEverythingWasAsked() {
        #expect(QuizTargetPicker.pick(from: names, flagged: [], weak: [], exclude: Set(names)) != nil)
        #expect(QuizTargetPicker.pick(from: [], flagged: ["pons"], weak: [], exclude: []) == nil)
    }
}

@MainActor
struct QuizSessionTests {

    @Test func tracksScoreStreaksAndMisses() {
        var session = QuizSession(length: 5)
        session.record(correctAnswer: "pons", wasCorrect: true)
        session.record(correctAnswer: "putamen", wasCorrect: true)
        session.record(correctAnswer: "amygdala", wasCorrect: false)
        session.record(correctAnswer: "amygdala", wasCorrect: false)
        session.record(correctAnswer: "insula", wasCorrect: true)

        #expect(session.score == 3)
        #expect(session.answered == 5)
        #expect(session.streak == 1)
        #expect(session.bestStreak == 2)
        #expect(session.missed == ["amygdala"])
        #expect(session.isFinished)
    }

    @Test func questionNumberStaysOnTheAnsweredQuestionDuringFeedback() {
        var session = QuizSession(length: 10)
        #expect(session.questionNumber(showingFeedback: false) == 1)
        session.record(correctAnswer: "pons", wasCorrect: true)
        #expect(session.questionNumber(showingFeedback: true) == 1)
        #expect(session.questionNumber(showingFeedback: false) == 2)
    }
}

// MARK: - Progress persistence

@MainActor
struct ProgressStoreTests {
    let defaults: UserDefaults

    init() {
        let suite = "cortiquiz.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func recordsAndPersistsStats() {
        let store = ProgressStore(defaults: defaults)
        store.record(baseName: "putamen", correct: false, streak: 0)
        store.record(baseName: "putamen", correct: true, streak: 1)
        store.record(baseName: "pons", correct: true, streak: 2)

        let reloaded = ProgressStore(defaults: defaults)
        #expect(reloaded.totalAnswered == 3)
        #expect(reloaded.totalCorrect == 2)
        #expect(reloaded.stats["putamen"]?.wrong == 1)
        #expect(reloaded.weakestStructures() == ["putamen"])
    }

    @Test func bestStreakIsTheBestSessionStreak() {
        let store = ProgressStore(defaults: defaults)
        store.record(baseName: "a", correct: true, streak: 3)
        store.record(baseName: "b", correct: true, streak: 1)   // new session
        #expect(store.bestStreak == 3)
    }

    @Test func reviewQueueClearsOnlyOnACorrectQuizAnswer() {
        let store = ProgressStore(defaults: defaults)
        store.flagForReview("amygdala")
        store.flagForReview("pons")
        store.flagForReview("amygdala")
        #expect(store.reviewQueue == ["amygdala", "pons"])

        store.record(baseName: "amygdala", correct: false, streak: 0)
        #expect(store.reviewQueue == ["amygdala", "pons"])
        store.record(baseName: "amygdala", correct: true, streak: 1)
        #expect(ProgressStore(defaults: defaults).reviewQueue == ["pons"])
    }

    @Test func loadsProgressSavedBeforeTheReviewQueueExisted() throws {
        let legacy = #"{"stats":{"putamen":{"seen":3,"correct":1,"wrong":2}},"bestStreak":4,"totalAnswered":3,"totalCorrect":1}"#
        defaults.set(Data(legacy.utf8), forKey: "cortiquiz.progress.v1")

        let store = ProgressStore(defaults: defaults)
        #expect(store.totalAnswered == 3)
        #expect(store.bestStreak == 4)
        #expect(store.reviewQueue.isEmpty)
        #expect(store.weakestStructures() == ["putamen"])
    }
}

// MARK: - Scene helpers

@MainActor
struct ExplodeLayoutTests {

    @Test func factorZeroIsTheNaturalLayout() {
        let node = SCNNode()
        let layout = ExplodeLayout(centers: ["#a": SCNVector3(10, 0, -4)], brainCenter: SCNVector3(2, 0, 0))
        layout.apply(0, to: ["#a": node])
        #expect(node.position.x == 0 && node.position.z == 0)
        layout.apply(2, to: ["#a": node])
        #expect(node.position.x == 16 && node.position.z == -8)
    }
}

// MARK: - MRI slicing

@MainActor
struct SliceClassifierTests {

    @Test func pixelScaleMatchesTheOrthographicCamera() {
        // SceneKit's orthographicScale is half the visible height: 180 mm across 512 px.
        #expect(abs(MRISlicing.pixelsPerUnit - 512.0 / 180.0) < 0.0001)
    }

    @Test func snapshotRendersAtThePredictedScale() throws {
        // A 90-unit box should fill half of the slice snapshot.
        let scene = SCNScene()
        let box = SCNNode(geometry: SCNBox(width: 90, height: 90, length: 1, chamferRadius: 0))
        box.geometry?.firstMaterial?.diffuse.contents = UIColor.white
        box.geometry?.firstMaterial?.lightingModel = .constant
        scene.rootNode.addChildNode(box)

        let image = SliceRenderer(scene: scene, nodes: [box]).snapshot(antialiased: false)
        let cg = try #require(image.cgImage)
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let row = height / 2
        let lit = (0..<width).filter { pixels[(row * width + $0) * 4] > 128 }.count
        let fraction = Double(lit) / Double(width)
        #expect(abs(fraction - 0.5) < 0.02, "box covered \(fraction) of the width")
    }

    @Test func footprintMeasuresTheSlabInSnapshotPixels() {
        // A flat 10 × 20 rectangle in the axial plane at z = 0.
        let mesh = TriangleMesh(
            vertices: [SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(10, 20, 0), SIMD3(0, 20, 0)],
            indices: [0, 1, 2, 0, 2, 3]
        )
        let ppu = MRISlicing.pixelsPerUnit
        let fp = SliceClassifier.footprint(mesh: mesh, axis: .axial, coord: 1, thickness: 2)
        #expect(fp?.triangleCount == 2)
        #expect(abs((fp?.maxDimensionPixels ?? 0) - 20 * ppu) < 0.001)
        #expect(abs((fp?.areaPixels ?? 0) - 200 * ppu * ppu) < 0.01)
        // Slab entirely above the rectangle: nothing visible.
        #expect(SliceClassifier.footprint(mesh: mesh, axis: .axial, coord: 10, thickness: 2) == nil)
    }

    @Test func triangleMeshReadsSceneKitGeometry() {
        let vertices = [SCNVector3(0, 0, 0), SCNVector3(1, 0, 0), SCNVector3(0, 1, 0), SCNVector3(0, 0, 1)]
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let mesh = TriangleMesh(node: SCNNode(geometry: geometry))
        #expect(mesh.vertices.count == 4)
        #expect(mesh.indices == [0, 1, 2, 0, 2, 3])
    }

    @Test func triangleMeshMatchesTheBundledOBJ() throws {
        // Model_17_left_hippocampus.obj has 5,550 `f` lines.
        let node = try #require(ModelCache.shared.node(for: "Model_17_left_hippocampus.obj"))
        let mesh = TriangleMesh(node: node)
        #expect(mesh.triangleCount == 5550)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count })
    }

    @Test func visibleSlicesMeetTheThresholds() throws {
        let node = try #require(ModelCache.shared.node(for: "Model_17_left_hippocampus.obj"))
        let mesh = TriangleMesh(node: node)
        let (bmin, bmax) = node.boundingBox
        let slices = SliceClassifier.visibleSlices(mesh: mesh, axis: .axial, lower: bmin.z, upper: bmax.z)
        #expect(!slices.isEmpty)
        #expect(slices.count <= SliceClassifier.maxSlicesPerTarget)
        for s in slices {
            #expect(s.footprint.maxDimensionPixels >= SliceClassifier.minDimensionPixels)
            #expect(s.footprint.areaPixels >= SliceClassifier.minAreaPixels)
            #expect((bmin.z...bmax.z).contains(s.coord))
        }
    }
}
