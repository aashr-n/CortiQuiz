import SwiftUI

// MARK: - JSON Decodable types from atlasStructure.json

nonisolated struct AtlasEntry: Decodable {
    let id: String
    let type: String
    let annotation: Annotation?
    let member: [String]?
    let renderOption: RenderOption?
    let sourceSelector: [SourceSelector]?
    let source: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "@id"
        case type = "@type"
        case annotation, member, renderOption, sourceSelector, source
    }
    
    struct Annotation: Decodable {
        let name: String
    }
    
    struct RenderOption: Decodable {
        let color: String?
    }
    
    struct SourceSelector: Decodable {
        let type: SelectorType
        let dataSource: String?
        
        enum CodingKeys: String, CodingKey {
            case type = "@type"
            case dataSource
        }
        
        enum SelectorType: Decodable {
            case single(String)
            case multiple([String])
            
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let s = try? container.decode(String.self) {
                    self = .single(s)
                } else if let arr = try? container.decode([String].self) {
                    self = .multiple(arr)
                } else {
                    self = .single("")
                }
            }
            
            var isGeometry: Bool {
                switch self {
                case .single(let s): return s.contains("Geometry")
                case .multiple(let arr): return arr.contains { $0.contains("Geometry") }
                }
            }
        }
    }
}

// MARK: - Domain Model

nonisolated struct BrainStructure: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let color: Color
    let modelFileName: String?
    var hierarchyPath: [String]
    let isGroup: Bool
    let memberIDs: [String]
    /// ID of the immediate parent group, if any. Used to pick anatomically plausible quiz distractors.
    var parentID: String?
    /// Name without left/right markers, computed once at init (the regex is hot on quiz paths).
    let baseName: String

    init(
        id: String,
        name: String,
        color: Color,
        modelFileName: String?,
        hierarchyPath: [String],
        isGroup: Bool,
        memberIDs: [String],
        parentID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.modelFileName = modelFileName
        self.hierarchyPath = hierarchyPath
        self.isGroup = isGroup
        self.memberIDs = memberIDs
        self.parentID = parentID
        self.baseName = Self.computeBaseName(name)
    }

    /// Strip left/right markers and collapse whitespace, for matching hemisphere pairs.
    static func computeBaseName(_ name: String) -> String {
        name.replacingOccurrences(
            of: #"\b(left|right)[\s_-]+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        .replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBrainStructure: Bool {
        guard let fn = modelFileName else { return isGroup }
        // Model_4xxx = muscles/face, Model_3_skin = skin
        // Keep Model_3xxx that aren't skin (claustrum, mammillary, corpus callosum, etc.)
        if fn.hasPrefix("Model_3_") { return false } // skin
        if fn.contains("_4") {
            // Check if it's a 4-digit model number starting with 4 (4001-4100 = muscles/face)
            let parts = fn.split(separator: "_")
            if parts.count >= 2, let num = Int(parts[1]), num >= 4001 && num <= 4100 { return false }
        }
        return true
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: BrainStructure, rhs: BrainStructure) -> Bool { lhs.id == rhs.id }
}
