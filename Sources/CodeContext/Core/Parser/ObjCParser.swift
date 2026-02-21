// Exey Panteleev
import Foundation

// MARK: - ObjC Header Parser

/// Lightweight parser for Objective-C .h/.m files.
final class ObjCParser: LanguageParser, @unchecked Sendable {

    private let importPattern = try! NSRegularExpression(
        pattern: #"^\s*(?:#import|#include|@import)\s+[<"]([^>"]+)[>"]"#,
        options: .anchorsMatchLines
    )

    private let interfacePattern = try! NSRegularExpression(
        pattern: #"^\s*@(?:interface|protocol)\s+(\w+)"#,
        options: .anchorsMatchLines
    )

    func parse(file: URL) throws -> ParsedFile {
        let content = try String(contentsOf: file, encoding: .utf8)
        let range = NSRange(content.startIndex..., in: content)

        let imports = importPattern.matches(in: content, range: range).compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[r])
        }

        let declarations = interfacePattern.matches(in: content, range: range).compactMap { match -> Declaration? in
            guard let r = Range(match.range(at: 1), in: content) else { return nil }
            return Declaration(name: String(content[r]), kind: .class)
        }

        let pathComponents = file.pathComponents
        let packageName: String = {
            if let pkgIdx = pathComponents.firstIndex(of: "Packages"),
               pkgIdx + 1 < pathComponents.count {
                return pathComponents[pkgIdx + 1]
            }
            return ""
        }()

        return ParsedFile(
            filePath: file.path,
            moduleName: "",
            imports: imports,
            description: "",
            lineCount: content.components(separatedBy: "\n").count,
            declarations: declarations,
            packageName: packageName
        )
    }
}
