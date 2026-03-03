// Exey Panteleev
import Foundation

// MARK: - Dependency Graph

/// Directed dependency graph with PageRank scoring.
final class DependencyGraph: @unchecked Sendable {

    private(set) var vertices: Set<String> = []
    private(set) var edges: [(source: String, target: String)] = []
    private var adjacency: [String: Set<String>] = [:]
    private var reverseAdj: [String: Set<String>] = [:]
    private(set) var pageRankScores: [String: Double] = [:]
    private(set) var hasCycles: Bool = false

    // MARK: - Build

    func build(from parsedFiles: [ParsedFile], bridgingHeaderPath: String = "") {
        let startTime = CFAbsoluteTimeGetCurrent()
        var nameToPath: [String: String] = [:]

        print("   Registering \(parsedFiles.count) vertices...")
        for file in parsedFiles {
            addVertex(file.filePath)
            nameToPath[file.fileNameWithoutExtension] = file.filePath
            if !file.moduleName.isEmpty {
                nameToPath[file.moduleName] = file.filePath
            }
        }

        // Import-based edges (cross-module)
        print("   Building import-based edges...")
        for source in parsedFiles {
            for importName in source.imports {
                let baseName = importName.components(separatedBy: ".").last ?? importName
                if let targetPath = nameToPath[importName] ?? nameToPath[baseName] {
                    addEdge(from: source.filePath, to: targetPath)
                }
            }
        }
        let importEdges = edges.count
        let t1 = CFAbsoluteTimeGetCurrent() - startTime
        print("   Import edges: \(importEdges) (\(String(format: "%.1f", t1))s)")

        // Type-reference edges (intra-module) — capped for performance
        print("   Building type-reference edges...")
        buildTypeReferenceEdges(from: parsedFiles)
        let typeRefEdges = edges.count - importEdges
        let t2 = CFAbsoluteTimeGetCurrent() - startTime
        print("   Type-reference edges: \(typeRefEdges) (\(String(format: "%.1f", t2))s)")

        // ObjC/Swift interop edges via bridging header
        if !bridgingHeaderPath.isEmpty {
            let preInterop = edges.count
            buildInteropEdges(from: parsedFiles, bridgingHeaderPath: bridgingHeaderPath)
            let interopEdges = edges.count - preInterop
            if interopEdges > 0 {
                print("   Interop edges: \(interopEdges) (bridging header hub)")
            }
        }

        detectCycles()

        let t3 = CFAbsoluteTimeGetCurrent() - startTime
        print("   Graph complete: \(vertices.count) nodes, \(edges.count) edges (\(String(format: "%.1f", t3))s)")
    }

    /// Build edges based on type references within each package.
    /// Optimized: reads each file once, uses String.contains + word boundary check.
    private func buildTypeReferenceEdges(from parsedFiles: [ParsedFile]) {
        var byPackage: [String: [ParsedFile]] = [:]
        for file in parsedFiles {
            let key = file.packageName.isEmpty ? "__app__" : file.packageName
            byPackage[key, default: []].append(file)
        }

        let totalPackages = byPackage.count
        print("   Scanning type references across \(totalPackages) modules...")

        // Pre-read all file contents in one pass
        var contentCache: [String: String] = [:]
        for file in parsedFiles {
            if let c = try? String(contentsOfFile: file.filePath, encoding: .utf8) {
                contentCache[file.filePath] = c
            }
        }
        print("   Cached \(contentCache.count) file contents")

        for (pkgIdx, (pkgName, packageFiles)) in byPackage.enumerated() {
            let displayName = pkgName == "__app__" ? "App" : pkgName
            let cappedFiles: [ParsedFile]
            if packageFiles.count > 200 {
                cappedFiles = Array(packageFiles.sorted { $0.lineCount > $1.lineCount }.prefix(200))
            } else {
                cappedFiles = packageFiles
            }
            print("   [\(pkgIdx+1)/\(totalPackages)] \(displayName): \(packageFiles.count) files")

            var typeToFile: [(name: String, path: String)] = []
            for file in cappedFiles {
                for decl in file.declarations where decl.kind != .extension && decl.name.count >= 4 && !Declaration.invalidNames.contains(decl.name) {
                    typeToFile.append((name: decl.name, path: file.filePath))
                }
            }
            guard !typeToFile.isEmpty else { continue }

            if typeToFile.count > 500 {
                let topPaths = Set(cappedFiles.prefix(100).map(\.filePath))
                typeToFile = typeToFile.filter { topPaths.contains($0.path) }
            }

            for file in cappedFiles {
                guard let content = contentCache[file.filePath] else { continue }
                for (typeName, declPath) in typeToFile {
                    guard declPath != file.filePath else { continue }
                    if fastContainsType(content, typeName: typeName) {
                        addEdge(from: file.filePath, to: declPath)
                    }
                }
            }
        }

        // Release cache
        contentCache.removeAll()
    }

    /// Build edges for Swift↔ObjC interop via bridging header and -Swift.h imports.
    private func buildInteropEdges(from parsedFiles: [ParsedFile], bridgingHeaderPath: String) {
        // Find the bridging header in parsed files
        let bridgingFile = parsedFiles.first { file in
            file.filePath.hasSuffix(bridgingHeaderPath) ||
            file.fileName == (bridgingHeaderPath.components(separatedBy: "/").last ?? bridgingHeaderPath)
        }

        guard let bridgingFile = bridgingFile else {
            print("   ⚠️  Bridging header not found in scanned files: \(bridgingHeaderPath)")
            return
        }

        // Build lookup from file name → path
        let nameToPath: [String: String] = Dictionary(
            parsedFiles.map { ($0.fileName, $0.filePath) },
            uniquingKeysWith: { first, _ in first }
        )
        let nameNoExtToPath: [String: String] = Dictionary(
            parsedFiles.map { ($0.fileNameWithoutExtension, $0.filePath) },
            uniquingKeysWith: { first, _ in first }
        )

        // 1. Bridging header → ObjC headers it imports
        for importName in bridgingFile.imports {
            let baseName = importName.components(separatedBy: "/").last ?? importName
            let nameOnly = baseName.replacingOccurrences(of: ".h", with: "")
            if let targetPath = nameToPath[baseName] ?? nameNoExtToPath[nameOnly] {
                addEdge(from: bridgingFile.filePath, to: targetPath)
            }
        }

        // 2. All Swift files → bridging header (implicit dependency)
        for file in parsedFiles where file.filePath.hasSuffix(".swift") {
            addEdge(from: file.filePath, to: bridgingFile.filePath)
        }

        // 3. ObjC .m/.mm files importing *-Swift.h → bridging header as proxy hub
        for file in parsedFiles {
            let ext = URL(fileURLWithPath: file.filePath).pathExtension.lowercased()
            guard ext == "m" || ext == "mm" else { continue }
            if file.imports.contains(where: { $0.hasSuffix("-Swift.h") }) {
                addEdge(from: file.filePath, to: bridgingFile.filePath)
            }
        }
    }

    /// Fast type-name check using String.range (no regex compilation overhead).
    private func fastContainsType(_ content: String, typeName: String) -> Bool {
        guard content.contains(typeName) else { return false }
        // Search for typeName with word boundaries
        var searchRange = content.startIndex..<content.endIndex
        while let range = content.range(of: typeName, range: searchRange) {
            let before = range.lowerBound > content.startIndex ? content[content.index(before: range.lowerBound)] : Character(" ")
            let after = range.upperBound < content.endIndex ? content[range.upperBound] : Character(" ")
            if !before.isLetterOrDigit && before != "_" && !after.isLetterOrDigit && after != "_" {
                return true
            }
            searchRange = range.upperBound..<content.endIndex
        }
        return false
    }

    // MARK: - Graph Operations

    func addVertex(_ v: String) {
        vertices.insert(v)
        if adjacency[v] == nil { adjacency[v] = [] }
        if reverseAdj[v] == nil { reverseAdj[v] = [] }
    }

    func addEdge(from source: String, to target: String) {
        guard source != target, vertices.contains(source), vertices.contains(target),
              !(adjacency[source]?.contains(target) ?? false) else { return }
        edges.append((source: source, target: target))
        adjacency[source]?.insert(target)
        reverseAdj[target]?.insert(source)
    }

    func outDegree(of vertex: String) -> Int { adjacency[vertex]?.count ?? 0 }
    func inDegree(of vertex: String) -> Int { reverseAdj[vertex]?.count ?? 0 }

    // MARK: - Analysis

    func analyze() { computePageRank() }

    func computePageRank(damping: Double = 0.85, iterations: Int = 20) {
        let n = Double(vertices.count)
        guard n > 0 else { return }
        var scores = Dictionary(uniqueKeysWithValues: vertices.map { ($0, 1.0 / n) })

        for _ in 0..<iterations {
            var newScores = Dictionary(uniqueKeysWithValues: vertices.map { ($0, (1.0 - damping) / n) })
            for v in vertices {
                let outNeighbors = adjacency[v] ?? []
                if outNeighbors.isEmpty { continue }
                let share = (scores[v] ?? 0) / Double(outNeighbors.count)
                for neighbor in outNeighbors {
                    newScores[neighbor, default: 0] += damping * share
                }
            }
            scores = newScores
        }
        pageRankScores = scores
    }

    // MARK: - Hotspots

    struct HotspotEntry {
        let path: String
        let score: Double
    }

    func getTopHotspots(limit: Int = 15) -> [HotspotEntry] {
        pageRankScores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { HotspotEntry(path: $0.key, score: $0.value) }
    }

    // MARK: - Cycle Detection

    private func detectCycles() {
        var visited: Set<String> = []
        var onStack: Set<String> = []
        func dfs(_ v: String) -> Bool {
            visited.insert(v)
            onStack.insert(v)
            for neighbor in adjacency[v] ?? [] {
                if onStack.contains(neighbor) { return true }
                if !visited.contains(neighbor) && dfs(neighbor) { return true }
            }
            onStack.remove(v)
            return false
        }
        hasCycles = vertices.contains { !visited.contains($0) && dfs($0) }
        if hasCycles { print("⚠️  Circular dependencies detected in the codebase.") }
    }

    // MARK: - Topological Sort

    func topologicalSort() -> [String]? {
        guard !hasCycles else { return nil }
        var inDegrees = Dictionary(uniqueKeysWithValues: vertices.map { ($0, 0) })
        for (_, neighbors) in adjacency {
            for n in neighbors { inDegrees[n, default: 0] += 1 }
        }
        var queue: [String] = vertices.filter { inDegrees[$0] == 0 }.sorted()
        var result: [String] = []
        while !queue.isEmpty {
            let v = queue.removeFirst()
            result.append(v)
            for neighbor in adjacency[v] ?? [] {
                inDegrees[neighbor]! -= 1
                if inDegrees[neighbor] == 0 { queue.append(neighbor) }
            }
        }
        return result.count == vertices.count ? result : nil
    }
}

// MARK: - Character Extension

private extension Character {
    var isLetterOrDigit: Bool { isLetter || isNumber }
}
