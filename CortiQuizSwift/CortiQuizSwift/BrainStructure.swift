import SwiftUI

// MARK: - JSON Decodable types from atlasStructure.json

struct AtlasEntry: Decodable {
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

struct BrainStructure: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
    let modelFileName: String?
    var hierarchyPath: [String]
    let isGroup: Bool
    let memberIDs: [String]
    
    /// Name without left/right prefix for matching
    var baseName: String {
        name.replacingOccurrences(of: "left ", with: "")
            .replacingOccurrences(of: "right ", with: "")
            .replacingOccurrences(of: "Left ", with: "")
            .replacingOccurrences(of: "Right ", with: "")
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

// MARK: - Color Parsing

extension Color {
    static func fromRGB(_ str: String?) -> Color {
        guard let str = str,
              str.hasPrefix("rgb("),
              let inner = str.dropFirst(4).dropLast().components(separatedBy: ",") as [Substring]?,
              inner.count == 3,
              let r = Double(inner[0].trimmingCharacters(in: .whitespaces)),
              let g = Double(inner[1].trimmingCharacters(in: .whitespaces)),
              let b = Double(inner[2].trimmingCharacters(in: .whitespaces))
        else { return .gray }
        return Color(red: r / 255, green: g / 255, blue: b / 255)
    }
}
