// Exey Panteleev
import Foundation

// MARK: - Learning Path

struct LearningStep: Codable {
    let file: String
    let category: String
    let reason: String

    var fileName: String {
        URL(fileURLWithPath: file).lastPathComponent
    }
}

// MARK: - Learning Path Generator

struct LearningPathGenerator {

    func generate(from graph: DependencyGraph) -> [LearningStep] {
        // Try topological sort
        if let topoOrder = graph.topologicalSort() {
            // Reverse: dependencies first (bottom-up reading order)
            let reversed = topoOrder.reversed()

            return reversed.map { filePath in
                let outDeg = graph.outDegree(of: filePath)
                let inDeg = graph.inDegree(of: filePath)

                let category: String
                let reason: String

                switch (outDeg, inDeg) {
                case (0, _):
                    category = "Fundamental"
                    reason = "This file stands alone. Start here to understand basic blocks."
                case (_, 0):
                    category = "Entry Point"
                    reason = "This is a high-level orchestrator. Read this last to see how everything fits."
                default:
                    category = "Core Logic"
                    reason = "Connects different parts of the system."
                }

                return LearningStep(file: filePath, category: category, reason: reason)
            }
        }

        // Fallback for cyclic graphs: sort by out-degree (fewest deps first)
        print("⚠️  Cyclic dependencies detected. Learning path is approximate.")
        return graph.vertices
            .sorted { graph.outDegree(of: $0) < graph.outDegree(of: $1) }
            .map { LearningStep(file: $0, category: "Cycle Context", reason: "Part of a circular dependency.") }
    }
}
