//
//  CortiQuizSwiftTests.swift
//  CortiQuizSwiftTests
//
//  Created by Aashray N on 3/2/26.
//

import Testing
import SwiftUI
@testable import CortiQuizSwift

struct CortiQuizSwiftTests {

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
            let structure = BrainStructure(
                id: "#test",
                name: name,
                color: .white,
                modelFileName: nil,
                hierarchyPath: [],
                isGroup: false,
                memberIDs: []
            )
            #expect(structure.baseName == expected)
        }
    }

}
