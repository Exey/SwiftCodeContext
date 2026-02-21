// Exey Panteleev
import Foundation

// MARK: - Dependency Graph

/// Directed dependency graph with PageRank scoring.
/// Pure Swift implementation — no JGraphT needed.
final class DependencyGraph: @unchecked Sendable {

    // Adjacency lists
    private(set) var vertices: Set<String> = []
    private(set) var edges: [(source: String, target: String)] = []
    private var adjacency: [String: Set<String>] = [:]      // outgoing
    private var reverseAdj: [String: Set<String>] = [:]      // incoming

    private(set) var pageRankScores: [String: Double] = [:]
    private(set) var hasCycles: Bool = false

    // MARK: - Build

    func build(from parsedFiles: [ParsedFile]) {
        // Build import → file mapping
        var nameToPath: [String: String] = [:]

        for file in parsedFiles {
            let path = file.filePath
            addVertex(path)

            let name = file.fileNameWithoutExtension
            nameToPath[name] = path

            if !file.moduleName.isEmpty {
                nameToPath[file.moduleName] = path
            }
        }

        // 1. Import-based edges (cross-module)
        for source in parsedFiles {
            for importName in source.imports {
                let components = importName.components(separatedBy: ".")
                let baseName = components.last ?? importName
                if let targetPath = nameToPath[importName] ?? nameToPath[baseName] {
                    addEdge(from: source.filePath, to: targetPath)
                }
            }
        }

        // 2. Type-reference edges (intra-module)
        // If FileA declares `class Foo` and FileB mentions `Foo`, draw edge B→A
        // This captures real dependencies within the same Swift module.
        buildTypeReferenceEdges(from: parsedFiles)

        // Detect cycles
        detectCycles()
    }

    /// Build edges based on type name references across files.
    /// Groups files by package and checks if declared type names appear in other files' source.
    private func buildTypeReferenceEdges(from parsedFiles: [ParsedFile]) {
        // Group by package (empty = App)
        var byPackage: [String: [ParsedFile]] = [:]
        for file in parsedFiles {
            let key = file.packageName.isEmpty ? "__app__" : file.packageName
            byPackage[key, default: []].append(file)
        }

        for (_, packageFiles) in byPackage {
            // Collect all declared type names → file path
            // Only real declarations (not extensions), 3+ chars to avoid false positives
            var typeToFile: [(name: String, path: String)] = []
            for file in packageFiles {
                for decl in file.declarations where decl.kind != .extension && decl.name.count >= 3 {
                    typeToFile.append((name: decl.name, path: file.filePath))
                }
            }

            guard !typeToFile.isEmpty else { continue }

            // For each file, read its source and check for type references from other files
            for file in packageFiles {
                guard let content = try? String(contentsOfFile: file.filePath, encoding: .utf8) else { continue }

                for (typeName, declPath) in typeToFile {
                    guard declPath != file.filePath else { continue }

                    // Check if this type name is used in the file content
                    // Use word boundary check to avoid substring matches
                    if contentContainsType(content, typeName: typeName) {
                        addEdge(from: file.filePath, to: declPath)
                    }
                }
            }
        }
    }

    /// Checks if content contains a type name as a whole word (not as a substring).
    private func contentContainsType(_ content: String, typeName: String) -> Bool {
        // Quick check first
        guard content.contains(typeName) else { return false }

        // Word boundary check: type name surrounded by non-alphanumeric chars
        // Patterns: `: TypeName`, `TypeName.`, `TypeName(`, `<TypeName>`, etc.
        let pattern = "(?<![a-zA-Z0-9_])\(NSRegularExpression.escapedPattern(for: typeName))(?![a-zA-Z0-9_])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(content.startIndex..., in: content)
        return regex.firstMatch(in: content, range: range) != nil
    }

    // MARK: - Graph Operations

    func addVertex(_ v: String) {
        vertices.insert(v)
        if adjacency[v] == nil { adjacency[v] = [] }
        if reverseAdj[v] == nil { reverseAdj[v] = [] }
    }

    func addEdge(from source: String, to target: String) {
        guard source != target,
              vertices.contains(source),
              vertices.contains(target),
              !(adjacency[source]?.contains(target) ?? false) else { return }

        adjacency[source]?.insert(target)
        reverseAdj[target]?.insert(source)
        edges.append((source: source, target: target))
    }

    func outDegree(of vertex: String) -> Int {
        adjacency[vertex]?.count ?? 0
    }

    func inDegree(of vertex: String) -> Int {
        reverseAdj[vertex]?.count ?? 0
    }

    func neighbors(of vertex: String) -> Set<String> {
        adjacency[vertex] ?? []
    }

    // MARK: - PageRank

    /// Compute PageRank with damping factor and iteration limit.
    func computePageRank(damping: Double = 0.85, iterations: Int = 100) {
        guard !vertices.isEmpty else { return }

        let n = Double(vertices.count)
        var scores: [String: Double] = [:]

        // Initialize uniformly
        for v in vertices {
            scores[v] = 1.0 / n
        }

        for _ in 0..<iterations {
            var newScores: [String: Double] = [:]

            for v in vertices {
                var rank = (1.0 - damping) / n

                // Sum contributions from all vertices pointing to v
                if let incoming = reverseAdj[v] {
                    for u in incoming {
                        let outDeg = adjacency[u]?.count ?? 1
                        rank += damping * (scores[u] ?? 0) / Double(max(outDeg, 1))
                    }
                }

                newScores[v] = rank
            }

            scores = newScores
        }

        pageRankScores = scores
    }

    /// Analyze the graph: compute PageRank.
    func analyze() {
        computePageRank()
    }

    func getTopHotspots(limit: Int = 10) -> [(path: String, score: Double)] {
        pageRankScores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (path: $0.key, score: $0.value) }
    }

    // MARK: - Cycle Detection (DFS)

    private func detectCycles() {
        enum Color { case white, gray, black }
        var color: [String: Color] = [:]
        for v in vertices { color[v] = .white }

        func dfs(_ u: String) -> Bool {
            color[u] = .gray
            for v in adjacency[u] ?? [] {
                if color[v] == .gray { return true }       // back edge → cycle
                if color[v] == .white, dfs(v) { return true }
            }
            color[u] = .black
            return false
        }

        for v in vertices {
            if color[v] == .white, dfs(v) {
                hasCycles = true
                print("⚠️  Circular dependencies detected in the codebase.")
                return
            }
        }
    }

    // MARK: - Topological Sort (Kahn's Algorithm)

    /// Returns topological order, or nil if cycles exist.
    func topologicalSort() -> [String]? {
        var inDegrees: [String: Int] = [:]
        for v in vertices { inDegrees[v] = 0 }
        for (_, targets) in adjacency {
            for t in targets {
                inDegrees[t, default: 0] += 1
            }
        }

        var queue: [String] = vertices.filter { inDegrees[$0] == 0 }.sorted()
        var result: [String] = []

        while !queue.isEmpty {
            let v = queue.removeFirst()
            result.append(v)

            for neighbor in adjacency[v] ?? [] {
                inDegrees[neighbor]! -= 1
                if inDegrees[neighbor] == 0 {
                    queue.append(neighbor)
                }
            }
        }

        return result.count == vertices.count ? result : nil
    }
}
