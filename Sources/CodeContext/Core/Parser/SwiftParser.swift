// Exey Panteleev
import Foundation

// MARK: - Swift Parser

/// Parses Swift source files to extract imports, type declarations, doc comments, line count.
/// Detects module membership from directory structure:
///   - SPM: Packages/<Name>/Sources/... or any dir with Package.swift + Sources/
///   - Bazel: dir with BUILD + Sources/
///   - Tuist: dir with Project.swift + Sources/
///   - Submodules: parent dir containing Sources/ and a manifest
final class SwiftParser: LanguageParser, @unchecked Sendable {

    private let importPattern = try! NSRegularExpression(
        pattern: #"^\s*import\s+(?:struct\s+|class\s+|enum\s+|protocol\s+|func\s+|var\s+|let\s+|typealias\s+)?(\w[\w.]*)"#,
        options: .anchorsMatchLines
    )

    private let declarationPattern = try! NSRegularExpression(
        pattern: #"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|open\s+)?(?:final\s+)?(?:nonisolated\s+)?(class|struct|enum|protocol|actor|extension)\s+([\w.]+)"#,
        options: .anchorsMatchLines
    )

    private let docCommentBlockPattern = try! NSRegularExpression(
        pattern: #"/\*\*([\s\S]*?)\*/"#, options: []
    )
    private let docCommentLinePattern = try! NSRegularExpression(
        pattern: #"^\s*///\s?(.*)"#, options: .anchorsMatchLines
    )

    /// Cache of directory → (moduleName, buildSystem)
    private static var moduleCache: [String: (String, BuildSystem)] = [:]
    private static let moduleCacheLock = NSLock()

    func parse(file: URL) throws -> ParsedFile {
        let content = try String(contentsOf: file, encoding: .utf8)
        let range = NSRange(content.startIndex..., in: content)
        let lineCount = content.components(separatedBy: "\n").count

        let imports = importPattern.matches(in: content, range: range).compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[r])
        }

        let declarations = declarationPattern.matches(in: content, range: range).compactMap { match -> Declaration? in
            guard let kindRange = Range(match.range(at: 1), in: content),
                  let nameRange = Range(match.range(at: 2), in: content) else { return nil }
            let name = String(content[nameRange])
            // "class func foo()" → kind=class, name=func → skip
            guard !Declaration.invalidNames.contains(name) else { return nil }
            guard let kind = Declaration.Kind(rawValue: String(content[kindRange])) else { return nil }
            return Declaration(name: name, kind: kind)
        }

        let pathComponents = file.pathComponents

        var moduleName = ""
        if let sourcesIdx = pathComponents.lastIndex(of: "Sources"),
           sourcesIdx + 1 < pathComponents.count {
            moduleName = pathComponents[sourcesIdx + 1]
        }

        let (packageName, buildSystem) = detectModule(for: file, pathComponents: pathComponents)

        // Doc comments
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
            description = lineMatches.prefix(10).compactMap { match -> String? in
                guard let r = Range(match.range(at: 1), in: content) else { return nil }
                return String(content[r]).trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }.joined(separator: " ")
        }

        // TODO / FIXME counts
        let lines = content.components(separatedBy: "\n")
        var todoCount = 0
        var fixmeCount = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("// TODO") || trimmed.contains("// MARK: TODO") { todoCount += 1 }
            if trimmed.contains("// FIXME") { fixmeCount += 1 }
        }

        // Longest function detection (simple brace-counting heuristic)
        let longestFunc = detectLongestFunction(lines: lines, filePath: file.path)

        return ParsedFile(
            filePath: file.path, moduleName: moduleName, imports: imports,
            description: description, lineCount: lineCount,
            declarations: declarations, packageName: packageName,
            buildSystem: buildSystem,
            todoCount: todoCount, fixmeCount: fixmeCount,
            longestFunction: longestFunc
        )
    }

    /// Detect the longest function/method by brace counting.
    private func detectLongestFunction(lines: [String], filePath: String) -> FunctionInfo? {
        var best: FunctionInfo?
        var currentFunc: String?
        var funcStartLine = 0
        var braceDepth = 0
        var inFunc = false

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect function start
            if !inFunc && (trimmed.hasPrefix("func ") || trimmed.hasPrefix("private func ") ||
                trimmed.hasPrefix("internal func ") || trimmed.hasPrefix("public func ") ||
                trimmed.hasPrefix("static func ") || trimmed.hasPrefix("override func ") ||
                trimmed.hasPrefix("@objc func ") || trimmed.hasPrefix("mutating func ") ||
                trimmed.hasPrefix("class func ") || trimmed.hasPrefix("open func ")) {
                // Extract function name
                if let funcRange = trimmed.range(of: "func\\s+(\\w+)", options: .regularExpression) {
                    let match = trimmed[funcRange]
                    if let nameRange = match.range(of: "\\w+$", options: .regularExpression) {
                        currentFunc = String(match[nameRange])
                        funcStartLine = i
                        inFunc = true
                        braceDepth = 0
                    }
                }
            }

            if inFunc {
                for ch in trimmed {
                    if ch == "{" { braceDepth += 1 }
                    if ch == "}" { braceDepth -= 1 }
                }
                if braceDepth <= 0 && trimmed.contains("}") {
                    let length = i - funcStartLine + 1
                    if let name = currentFunc, length > (best?.lineCount ?? 0) {
                        best = FunctionInfo(name: name, lineCount: length, filePath: filePath)
                    }
                    inFunc = false
                    currentFunc = nil
                }
            }
        }
        return best
    }

    // MARK: - Module/Package Detection

    /// Detects module name and build system.
    private func detectModule(for file: URL, pathComponents: [String]) -> (String, BuildSystem) {
        // Fast path: Packages/ directory → SPM
        if let pkgIdx = pathComponents.firstIndex(of: "Packages"),
           pkgIdx + 1 < pathComponents.count {
            return (pathComponents[pkgIdx + 1], .spm)
        }

        guard let sourcesIdx = pathComponents.lastIndex(of: "Sources"), sourcesIdx > 1 else {
            return ("", .unknown)
        }

        let moduleRootComponents = Array(pathComponents[0..<sourcesIdx])
        let moduleRootPath = moduleRootComponents.joined(separator: "/")
        let moduleDirName = moduleRootComponents.last ?? ""

        // Check cache
        Self.moduleCacheLock.lock()
        if let cached = Self.moduleCache[moduleRootPath] {
            Self.moduleCacheLock.unlock()
            return cached
        }
        Self.moduleCacheLock.unlock()

        let fm = FileManager.default
        let result: (String, BuildSystem)

        if fm.fileExists(atPath: moduleRootPath + "/Package.swift") {
            result = (moduleDirName, .spm)
        } else if fm.fileExists(atPath: moduleRootPath + "/BUILD") || fm.fileExists(atPath: moduleRootPath + "/BUILD.bazel") {
            result = (moduleDirName, .bazel)
        } else if fm.fileExists(atPath: moduleRootPath + "/Project.swift") {
            result = (moduleDirName, .tuist)
        } else {
            result = ("", .unknown)
        }

        Self.moduleCacheLock.lock()
        Self.moduleCache[moduleRootPath] = result
        Self.moduleCacheLock.unlock()

        return result
    }
}
