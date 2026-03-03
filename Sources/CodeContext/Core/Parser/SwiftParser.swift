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
        let data = try Data(contentsOf: file)
        guard let content = String(data: data, encoding: .utf8) else {
            return ParsedFile(filePath: file.path, moduleName: "", imports: [], description: "", lineCount: 0, declarations: [], packageName: "", buildSystem: .unknown, todoCount: 0, fixmeCount: 0, longestFunction: nil)
        }

        var imports: [String] = []
        var declarations: [Declaration] = []
        var lineCount = 0
        var todoCount = 0
        var fixmeCount = 0
        var description = ""
        var docLines: [String] = []

        // Longest function tracking
        var bestFunc: FunctionInfo?
        var curFuncName: String?
        var funcStartLine = 0
        var braceDepth = 0
        var inFunc = false

        // Scope depth for filtering nested declarations (enum CodingKeys inside extensions, etc.)
        var scopeDepth = 0

        // Single-pass line scan (like Go version — no regex on hot path)
        content.enumerateLines { line, _ in
            lineCount += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Imports: "import X" or "import struct X.Y"
            if trimmed.hasPrefix("import ") {
                let rest = trimmed.dropFirst(7)
                let token: Substring
                // Skip kind keywords: import struct/class/enum/protocol/func/var/let/typealias
                let parts = rest.split(separator: " ", maxSplits: 1)
                if parts.count == 2 {
                    let kw = parts[0]
                    if kw == "struct" || kw == "class" || kw == "enum" || kw == "protocol" || kw == "func" || kw == "var" || kw == "let" || kw == "typealias" {
                        token = parts[1]
                    } else {
                        token = parts[0]
                    }
                } else {
                    token = rest[...]
                }
                let moduleName = token.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." })
                if !moduleName.isEmpty {
                    imports.append(String(moduleName))
                }
                docLines = []
                return
            }

            // Declarations: class/struct/enum/protocol/actor/extension
            // Strip access modifiers first
            var declLine = trimmed[...]
            for prefix in ["public ", "internal ", "private ", "fileprivate ", "open "] {
                if declLine.hasPrefix(prefix) { declLine = declLine.dropFirst(prefix.count); break }
            }
            if declLine.hasPrefix("final ") { declLine = declLine.dropFirst(6) }
            if declLine.hasPrefix("nonisolated ") { declLine = declLine.dropFirst(12) }

            let declKeywords: [(String, Declaration.Kind)] = [
                ("class ", .class), ("struct ", .struct), ("enum ", .enum),
                ("protocol ", .protocol), ("actor ", .actor), ("extension ", .extension),
            ]
            for (kw, kind) in declKeywords {
                if declLine.hasPrefix(kw) {
                    let rest = declLine.dropFirst(kw.count)
                    let name = String(rest.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }))
                    // Only register top-level declarations (scopeDepth == 0)
                    // Skips nested types like enum CodingKeys inside extensions
                    if !name.isEmpty && !Declaration.invalidNames.contains(name) && scopeDepth == 0 {
                        declarations.append(Declaration(name: name, kind: kind))
                        if description.isEmpty && !docLines.isEmpty {
                            description = docLines.joined(separator: " ")
                        }
                    }
                    break
                }
            }

            // Update scope depth (track braces for nested declaration filtering)
            if !trimmed.hasPrefix("//") {
                for ch in trimmed {
                    if ch == "{" { scopeDepth += 1 }
                    else if ch == "}" { scopeDepth -= 1 }
                }
                if scopeDepth < 0 { scopeDepth = 0 }
            }

            // Function tracking (for longest function detection)
            if !inFunc {
                let hasFuncDecl = trimmed.contains("func ") && !trimmed.hasPrefix("//")
                if hasFuncDecl {
                    // Extract func name
                    if let funcIdx = trimmed.range(of: "func ") {
                        let after = trimmed[funcIdx.upperBound...]
                        let name = String(after.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" }))
                        if !name.isEmpty {
                            curFuncName = name
                            funcStartLine = lineCount
                            inFunc = true
                            braceDepth = 0
                        }
                    }
                }
            }

            if inFunc {
                for ch in trimmed {
                    if ch == "{" { braceDepth += 1 }
                    if ch == "}" { braceDepth -= 1 }
                }
                if braceDepth <= 0 && trimmed.contains("}") {
                    let length = lineCount - funcStartLine + 1
                    if let name = curFuncName, length > (bestFunc?.lineCount ?? 0) {
                        bestFunc = FunctionInfo(name: name, lineCount: length, filePath: file.path)
                    }
                    inFunc = false
                    curFuncName = nil
                }
            }

            // Doc comments
            if trimmed.hasPrefix("///") {
                let doc = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                docLines.append(doc)
            } else if !trimmed.isEmpty {
                docLines = []
            }

            // TODO / FIXME
            if trimmed.contains("// TODO") || trimmed.contains("// MARK: TODO") { todoCount += 1 }
            if trimmed.contains("// FIXME") { fixmeCount += 1 }
        }

        let pathComponents = file.pathComponents
        var moduleName = ""
        if let sourcesIdx = pathComponents.lastIndex(of: "Sources"),
           sourcesIdx + 1 < pathComponents.count {
            moduleName = pathComponents[sourcesIdx + 1]
        }
        let (packageName, buildSystem) = detectModule(for: file, pathComponents: pathComponents)
        // Use packageName as moduleName fallback (e.g. ObjC umbrella header packages)
        if moduleName.isEmpty && !packageName.isEmpty {
            moduleName = packageName
        }

        return ParsedFile(
            filePath: file.path, moduleName: moduleName, imports: imports,
            description: description, lineCount: lineCount,
            declarations: declarations, packageName: packageName,
            buildSystem: buildSystem,
            todoCount: todoCount, fixmeCount: fixmeCount,
            longestFunction: bestFunc
        )
    }

    // MARK: - Module/Package Detection

    /// Detects module name and build system.
    private func detectModule(for file: URL, pathComponents: [String]) -> (String, BuildSystem) {
        // Binary framework detection: .xcframework or .framework in path
        if let fwComp = pathComponents.first(where: { $0.hasSuffix(".xcframework") }) {
            return (String(fwComp.dropLast(".xcframework".count)), .unknown)
        }
        if let fwComp = pathComponents.first(where: { $0.hasSuffix(".framework") }) {
            return (String(fwComp.dropLast(".framework".count)), .unknown)
        }

        // Fast path: Packages/ directory → SPM
        if let pkgIdx = pathComponents.firstIndex(of: "Packages"),
           pkgIdx + 1 < pathComponents.count {
            return (pathComponents[pkgIdx + 1], .spm)
        }

        guard let sourcesIdx = pathComponents.lastIndex(of: "Sources"), sourcesIdx > 1 else {
            return detectUmbrellaHeaderPackage(for: file)
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

        if !result.0.isEmpty {
            return result
        }

        // Fallback: ObjC-style umbrella header detection
        // e.g. root/BlahBlahSDK/BlahBlahSDK.h → packageName = "BlahBlahSDK"
        return detectUmbrellaHeaderPackage(for: file)
    }

    /// Detect ObjC-style packages by umbrella header (FolderName/FolderName.h).
    private func detectUmbrellaHeaderPackage(for file: URL) -> (String, BuildSystem) {
        print("   🔎 [Swift] umbrella search for: \(file.lastPathComponent)")
        let fm = FileManager.default
        var dir = file.deletingLastPathComponent()

        for i in 0..<10 {
            let dirName = dir.lastPathComponent
            guard dirName != "/" && !dirName.isEmpty else {
                print("   🔎 [Swift]   iter \(i): hit root (\(dirName)), stopping")
                break
            }

            let cacheKey = dir.path
            Self.moduleCacheLock.lock()
            if let cached = Self.moduleCache[cacheKey] {
                Self.moduleCacheLock.unlock()
                print("   🔎 [Swift]   iter \(i): '\(dirName)' → CACHED: '\(cached.0)'")
                return cached
            }
            Self.moduleCacheLock.unlock()

            // Stop at project root markers
            let dirPath = dir.path
            let hasGit = fm.fileExists(atPath: dirPath + "/.git")
            let hasPkgSwift = fm.fileExists(atPath: dirPath + "/Package.swift")
            let hasXcodeproj = (try? fm.contentsOfDirectory(atPath: dirPath))?.contains(where: { $0.hasSuffix(".xcodeproj") }) == true
            if hasGit || hasPkgSwift || hasXcodeproj {
                print("   🔎 [Swift]   iter \(i): '\(dirName)' → STOP (git=\(hasGit) pkg=\(hasPkgSwift) xcodeproj=\(hasXcodeproj))")
                break
            }

            let umbrellaHeader = dirPath + "/\(dirName).h"
            let headerExists = fm.fileExists(atPath: umbrellaHeader)
            print("   🔎 [Swift]   iter \(i): '\(dirName)' → \(dirName).h exists=\(headerExists)")
            if headerExists {
                let result = (dirName, BuildSystem.unknown)
                Self.moduleCacheLock.lock()
                Self.moduleCache[cacheKey] = result
                Self.moduleCacheLock.unlock()
                return result
            }

            dir = dir.deletingLastPathComponent()
        }

        return ("", .unknown)
    }
}
