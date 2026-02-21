// Exey Panteleev
import Foundation

// MARK: - Swift Parser

/// Parses Swift source files to extract imports, type declarations, doc comments, line count.
/// Infers package membership from file path (Packages/<Name>/Sources/...).
final class SwiftParser: LanguageParser, @unchecked Sendable {

    // Patterns
    private let importPattern = try! NSRegularExpression(
        pattern: #"^\s*import\s+(?:struct\s+|class\s+|enum\s+|protocol\s+|func\s+|var\s+|let\s+|typealias\s+)?(\w[\w.]*)"#,
        options: .anchorsMatchLines
    )

    /// Matches top-level type declarations:
    ///   [access] [final] (class|struct|enum|protocol|actor|extension) Name
    private let declarationPattern = try! NSRegularExpression(
        pattern: #"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|open\s+)?(?:final\s+)?(?:nonisolated\s+)?(class|struct|enum|protocol|actor|extension)\s+(\w+)"#,
        options: .anchorsMatchLines
    )

    private let docCommentBlockPattern = try! NSRegularExpression(
        pattern: #"/\*\*([\s\S]*?)\*/"#,
        options: []
    )
    private let docCommentLinePattern = try! NSRegularExpression(
        pattern: #"^\s*///\s?(.*)"#,
        options: .anchorsMatchLines
    )

    func parse(file: URL) throws -> ParsedFile {
        let content = try String(contentsOf: file, encoding: .utf8)
        let range = NSRange(content.startIndex..., in: content)

        // Line count
        let lineCount = content.components(separatedBy: "\n").count

        // Extract imports
        let imports = importPattern.matches(in: content, range: range).compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[r])
        }

        // Extract declarations
        let declarations = declarationPattern.matches(in: content, range: range).compactMap { match -> Declaration? in
            guard let kindRange = Range(match.range(at: 1), in: content),
                  let nameRange = Range(match.range(at: 2), in: content) else { return nil }
            let kindStr = String(content[kindRange])
            let name = String(content[nameRange])
            guard let kind = Declaration.Kind(rawValue: kindStr) else { return nil }
            return Declaration(name: name, kind: kind)
        }

        // Infer module name from directory: Sources/<ModuleName>/...
        let pathComponents = file.pathComponents
        var moduleName = ""
        if let sourcesIdx = pathComponents.lastIndex(of: "Sources"),
           sourcesIdx + 1 < pathComponents.count {
            moduleName = pathComponents[sourcesIdx + 1]
        }

        // Infer package name from: Packages/<PackageName>/...
        let packageName: String = {
            if let pkgIdx = pathComponents.firstIndex(of: "Packages"),
               pkgIdx + 1 < pathComponents.count {
                return pathComponents[pkgIdx + 1]
            }
            return ""
        }()

        // Extract description from doc comments
        var description = ""

        if let blockMatch = docCommentBlockPattern.firstMatch(in: content, range: range),
           let r = Range(blockMatch.range(at: 1), in: content) {
            description = String(content[r])
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .map { $0.hasPrefix("*") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        if description.isEmpty {
            let lineMatches = docCommentLinePattern.matches(in: content, range: range)
            let lines = lineMatches.prefix(10).compactMap { match -> String? in
                guard let r = Range(match.range(at: 1), in: content) else { return nil }
                return String(content[r]).trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            description = lines.joined(separator: " ")
        }

        return ParsedFile(
            filePath: file.path,
            moduleName: moduleName,
            imports: imports,
            description: description,
            lineCount: lineCount,
            declarations: declarations,
            packageName: packageName
        )
    }
}
