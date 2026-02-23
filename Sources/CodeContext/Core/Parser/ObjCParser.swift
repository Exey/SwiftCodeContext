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

        // Module detection — same logic as SwiftParser
        var packageName = ""
        var buildSystem: BuildSystem = .unknown
        if let pkgIdx = pathComponents.firstIndex(of: "Packages"),
           pkgIdx + 1 < pathComponents.count {
            packageName = pathComponents[pkgIdx + 1]
            buildSystem = .spm
        } else if let sourcesIdx = pathComponents.lastIndex(of: "Sources"), sourcesIdx > 1 {
            let moduleRootPath = pathComponents[0..<sourcesIdx].joined(separator: "/")
            let moduleDirName = pathComponents[sourcesIdx - 1]
            let fm = FileManager.default
            if fm.fileExists(atPath: moduleRootPath + "/Package.swift") {
                packageName = moduleDirName; buildSystem = .spm
            } else if fm.fileExists(atPath: moduleRootPath + "/BUILD") || fm.fileExists(atPath: moduleRootPath + "/BUILD.bazel") {
                packageName = moduleDirName; buildSystem = .bazel
            } else if fm.fileExists(atPath: moduleRootPath + "/Project.swift") {
                packageName = moduleDirName; buildSystem = .tuist
            }
        }

        var moduleName = ""
        if let sourcesIdx = pathComponents.lastIndex(of: "Sources"),
           sourcesIdx + 1 < pathComponents.count {
            moduleName = pathComponents[sourcesIdx + 1]
        }

        return ParsedFile(
            filePath: file.path, moduleName: moduleName, imports: imports,
            description: "", lineCount: content.components(separatedBy: "\n").count,
            declarations: declarations, packageName: packageName,
            buildSystem: buildSystem,
            todoCount: 0, fixmeCount: 0, longestFunction: nil
        )
    }
}
