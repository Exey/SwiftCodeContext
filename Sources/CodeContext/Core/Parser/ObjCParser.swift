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
        let hasPackagesDir = pathComponents.firstIndex(of: "Packages") != nil
        let hasSourcesDir = pathComponents.lastIndex(of: "Sources") != nil
        if hasPackagesDir || hasSourcesDir {
            print("   🔎 [ObjC] SPM path hit for \(file.lastPathComponent): Packages=\(hasPackagesDir) Sources=\(hasSourcesDir)")
        }
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

        // Fallback: ObjC umbrella header detection (FolderName/FolderName.h)
        if packageName.isEmpty {
            print("   🔎 [ObjC] umbrella search for: \(file.lastPathComponent)")
            let fm = FileManager.default
            var dir = file.deletingLastPathComponent()
            for i in 0..<10 {
                let dirName = dir.lastPathComponent
                guard dirName != "/" && !dirName.isEmpty else {
                    print("   🔎 [ObjC]   iter \(i): hit root (\(dirName)), stopping")
                    break
                }
                let dirPath = dir.path
                let hasGit = fm.fileExists(atPath: dirPath + "/.git")
                let hasPkgSwift = fm.fileExists(atPath: dirPath + "/Package.swift")
                let hasXcodeproj = (try? fm.contentsOfDirectory(atPath: dirPath))?.contains(where: { $0.hasSuffix(".xcodeproj") }) == true
                if hasGit || hasPkgSwift || hasXcodeproj {
                    print("   🔎 [ObjC]   iter \(i): '\(dirName)' → STOP (git=\(hasGit) pkg=\(hasPkgSwift) xcodeproj=\(hasXcodeproj))")
                    break
                }
                let headerPath = dirPath + "/\(dirName).h"
                let headerExists = fm.fileExists(atPath: headerPath)
                print("   🔎 [ObjC]   iter \(i): '\(dirName)' → \(dirName).h exists=\(headerExists)")
                if headerExists {
                    packageName = dirName
                    break
                }
                dir = dir.deletingLastPathComponent()
            }
            print("   🔎 [ObjC]   result: packageName='\(packageName)'")
        }

        var moduleName = ""
        if let sourcesIdx = pathComponents.lastIndex(of: "Sources"),
           sourcesIdx + 1 < pathComponents.count {
            moduleName = pathComponents[sourcesIdx + 1]
        }
        if moduleName.isEmpty && !packageName.isEmpty {
            moduleName = packageName
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
