// Exey Panteleev
import Foundation

// MARK: - AI Models

struct AIInsight: Codable {
    let file: String
    let purpose: String
    let complexity: Int
    let keyComponents: [String]
    let refactoringTips: [String]
    let securityConcerns: [String]
    let businessImpact: String
    let readingTime: Int
}

struct AIConversationResponse: Codable {
    let answer: String
    let suggestedFiles: [String]
    let confidence: Double
}

struct AnalysisContext {
    let totalFiles: Int
    let dependencies: Int
    let dependents: Int
    let pageRank: Double
    let gitChurn: Int
}

struct CodebaseContext {
    let totalFiles: Int
    let languages: [String]
    let hotspots: [String]
}

// MARK: - AI Code Analyzer

/// AI-powered code analysis using URLSession (Apple-native networking).
/// Supports Anthropic Claude and Google Gemini.
final class AICodeAnalyzer: Sendable {
    let apiKey: String
    let model: String
    let provider: String

    var isConfigured: Bool {
        !apiKey.isEmpty && apiKey != "heuristic" && !apiKey.hasPrefix("demo")
    }

    init(apiKey: String, model: String = "claude-sonnet-4-20250514", provider: String = "anthropic") {
        self.apiKey = apiKey
        self.model = model
        self.provider = provider
    }

    // MARK: - Public API

    func analyzeFile(_ file: ParsedFile, context: AnalysisContext) async throws -> AIInsight {
        guard isConfigured else {
            throw CodeContextError.aiProvider("AI not configured. Set API key in .codecontext.json")
        }

        let prompt = buildFileAnalysisPrompt(file: file, context: context)
        let response = try await callAI(prompt: prompt)
        return parseInsight(response: response, filePath: file.filePath)
    }

    func batchAnalyze(
        files: [ParsedFile],
        graph: DependencyGraph,
        limit: Int = 50
    ) async -> [String: AIInsight] {
        let prioritized = files
            .sorted { (graph.pageRankScores[$0.filePath] ?? 0) > (graph.pageRankScores[$1.filePath] ?? 0) }
            .prefix(limit)

        print("🤖 AI analyzing top \(limit) files...")

        var results: [String: AIInsight] = [:]

        await withTaskGroup(of: (String, AIInsight)?.self) { group in
            for file in prioritized {
                group.addTask {
                    let context = AnalysisContext(
                        totalFiles: files.count,
                        dependencies: graph.outDegree(of: file.filePath),
                        dependents: graph.inDegree(of: file.filePath),
                        pageRank: graph.pageRankScores[file.filePath] ?? 0,
                        gitChurn: file.gitMetadata.changeFrequency
                    )
                    do {
                        let insight = try await self.analyzeFile(file, context: context)
                        return (file.filePath, insight)
                    } catch {
                        print("⚠️  AI analysis failed for \(file.fileName): \(error.localizedDescription)")
                        return nil
                    }
                }
            }

            for await result in group {
                if let (path, insight) = result {
                    results[path] = insight
                }
            }
        }

        return results
    }

    func askQuestion(_ question: String, context: CodebaseContext) async throws -> AIConversationResponse {
        let prompt = buildConversationPrompt(question: question, context: context)
        let response = try await callAI(prompt: prompt)
        return parseConversation(response: response)
    }

    // MARK: - AI Calls (URLSession — Apple native)

    private func callAI(prompt: String) async throws -> String {
        switch provider.lowercased() {
        case "anthropic", "claude":
            return try await callClaude(prompt: prompt)
        case "gemini":
            return try await callGemini(prompt: prompt)
        default:
            throw CodeContextError.aiProvider("Unsupported provider: \(provider)")
        }
    }

    private func callClaude(prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1000,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw CodeContextError.aiProvider("Claude API error: \(body)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = (json?["content"] as? [[String: Any]])?.first
        guard let text = content?["text"] as? String else {
            throw CodeContextError.aiProvider("Invalid Claude response format")
        }
        return text
    }

    private func callGemini(prompt: String) async throws -> String {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 2048
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw CodeContextError.aiProvider("Gemini API error: \(body)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        guard let text = parts?.first?["text"] as? String else {
            throw CodeContextError.aiProvider("Invalid Gemini response format")
        }
        return text
    }

    // MARK: - Prompt Builders

    private func buildFileAnalysisPrompt(file: ParsedFile, context: AnalysisContext) -> String {
        let fileContent = (try? String(contentsOfFile: file.filePath, encoding: .utf8).prefix(3000)) ?? "[unavailable]"
        return """
        Analyze this Swift codebase file and provide structured insights.

        FILE: \(file.fileName)
        MODULE: \(file.moduleName)
        IMPORTS: \(file.imports.prefix(10).joined(separator: ", "))

        CONTEXT:
        - Total codebase size: \(context.totalFiles) files
        - This file depends on: \(context.dependencies) files
        - This file is used by: \(context.dependents) files
        - PageRank (importance): \(String(format: "%.4f", context.pageRank))
        - Git churn: \(context.gitChurn) changes

        CODE PREVIEW:
        \(fileContent)

        Respond ONLY with JSON:
        {"purpose":"...","complexity":1-10,"keyComponents":[],"refactoringTips":[],"securityConcerns":[],"businessImpact":"...","readingTime":N}
        """
    }

    private func buildConversationPrompt(question: String, context: CodebaseContext) -> String {
        let hotspotNames = context.hotspots.prefix(5).map { URL(fileURLWithPath: $0).lastPathComponent }
        return """
        You're an expert guide for this Swift codebase.

        CODEBASE: \(context.totalFiles) files, Languages: \(context.languages.joined(separator: ", "))
        Top hotspots: \(hotspotNames.joined(separator: ", "))

        QUESTION: "\(question)"

        Respond with JSON:
        {"answer":"...","suggestedFiles":[],"confidence":0.0-1.0}
        """
    }

    // MARK: - Response Parsers

    private func parseInsight(response: String, filePath: String) -> AIInsight {
        guard let jsonStr = extractJSON(from: response),
              let data = jsonStr.data(using: .utf8),
              let insight = try? JSONDecoder().decode(AIInsight.self, from: data) else {
            return AIInsight(
                file: filePath, purpose: "Analysis unavailable", complexity: 5,
                keyComponents: [], refactoringTips: [], securityConcerns: [],
                businessImpact: "Unknown", readingTime: 10
            )
        }
        // Override file path
        return AIInsight(
            file: filePath, purpose: insight.purpose, complexity: insight.complexity,
            keyComponents: insight.keyComponents, refactoringTips: insight.refactoringTips,
            securityConcerns: insight.securityConcerns, businessImpact: insight.businessImpact,
            readingTime: insight.readingTime
        )
    }

    private func parseConversation(response: String) -> AIConversationResponse {
        guard let jsonStr = extractJSON(from: response),
              let data = jsonStr.data(using: .utf8),
              let result = try? JSONDecoder().decode(AIConversationResponse.self, from: data) else {
            return AIConversationResponse(
                answer: String(response.prefix(200)) + "...",
                suggestedFiles: [], confidence: 0.5
            )
        }
        return result
    }

    private func extractJSON(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        return String(text[start...end])
    }
}
