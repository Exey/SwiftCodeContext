// Exey Panteleev
import Foundation

// MARK: - Git Metadata

struct GitMetadata: Codable, Sendable {
    var lastModified: TimeInterval = 0
    var changeFrequency: Int = 0
    var topAuthors: [String] = []
    var recentMessages: [String] = []
    /// Earliest known commit timestamp for this file
    var firstCommitDate: TimeInterval = 0
}

// MARK: - Declaration Info

struct Declaration: Codable, Sendable {
    let name: String
    let kind: Kind   // class, struct, enum, protocol, actor

    enum Kind: String, Codable, Sendable {
        case `class`, `struct`, `enum`, `protocol`, actor, `extension`
    }
}

// MARK: - Build System

enum BuildSystem: String, Codable, Sendable {
    case spm = "SwiftPM"
    case bazel = "Bazel"
    case tuist = "Tuist"
    case unknown = "Unknown"
}

// MARK: - Function Info

struct FunctionInfo: Codable, Sendable {
    let name: String
    let lineCount: Int
    let filePath: String
}

// MARK: - Parsed File

struct ParsedFile: Codable, Sendable {
    let filePath: String
    let moduleName: String
    let imports: [String]
    var gitMetadata: GitMetadata = GitMetadata()
    let description: String
    let lineCount: Int
    let declarations: [Declaration]

    /// Package name inferred from directory structure.
    let packageName: String

    /// Build system that manages this module.
    let buildSystem: BuildSystem

    /// Count of // TODO comments
    let todoCount: Int
    /// Count of // FIXME comments
    let fixmeCount: Int
    /// Longest function in this file
    let longestFunction: FunctionInfo?

    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    var fileNameWithoutExtension: String {
        URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
    }

    /// Returns the "scene" or logical group from the path.
    /// e.g. Sphere/Scenes/CreditHistory/... → "CreditHistory"
    var sceneGroup: String? {
        let parts = filePath.components(separatedBy: "/")
        if let idx = parts.firstIndex(of: "Scenes"), idx + 1 < parts.count {
            return parts[idx + 1]
        }
        return nil
    }
}

// MARK: - Language Parser Protocol

protocol LanguageParser: Sendable {
    func parse(file: URL) throws -> ParsedFile
}
