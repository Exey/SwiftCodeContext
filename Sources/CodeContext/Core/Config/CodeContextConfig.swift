// Exey Panteleev
import Foundation

// MARK: - Configuration Models

struct CodeContextConfig: Codable {
    var excludePaths: [String] = [
        ".git", ".build", ".swiftpm", "DerivedData", "Pods",
        "Carthage", "node_modules", ".xcode", "build", ".idea"
    ]
    var maxFilesAnalyze: Int = 10000
    var gitCommitLimit: Int = 1000
    var enableCache: Bool = true
    var enableParallel: Bool = true
    var hotspotCount: Int = 15
    var learningPathLength: Int = 20
    var ai: AIConfig = AIConfig()
    var rateLimit: RateLimitConfig = RateLimitConfig()
    /// File extensions to analyze (Swift-first, but extensible)
    var fileExtensions: [String] = ["swift"]
}

struct AIConfig: Codable {
    var enabled: Bool = false
    var provider: String = "anthropic"  // "anthropic" or "gemini"
    var apiKey: String = ""
    var model: String = "claude-sonnet-4-20250514"
}

struct RateLimitConfig: Codable {
    var enabled: Bool = true
    var requestsPerMinute: Int = 60
    var requestsPerHour: Int = 1000
}

// MARK: - Config Loader

enum ConfigLoader {
    static let defaultPath = ".codecontext.json"

    static func load(from path: String = defaultPath) -> CodeContextConfig {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return CodeContextConfig()
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(CodeContextConfig.self, from: data)
        } catch {
            fputs("⚠️  Failed to parse config, using defaults: \(error.localizedDescription)\n", stderr)
            return CodeContextConfig()
        }
    }

    static func createDefault(at path: String = defaultPath) throws {
        let config = CodeContextConfig()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: URL(fileURLWithPath: path))
        print("✅ Created default config at \(path)")
    }
}
