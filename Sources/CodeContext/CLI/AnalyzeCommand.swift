// Exey Panteleev
import ArgumentParser
import Foundation

// MARK: - Analyze Command

struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Analyze a Swift codebase and generate a report"
    )

    @Argument(help: "Path to the repository to analyze")
    var path: String = "."

    @Flag(name: .long, help: "Disable caching")
    var noCache: Bool = false

    @Flag(name: .long, help: "Clear cache before analyzing")
    var clearCache: Bool = false

    @Flag(name: [.short, .long], help: "Enable verbose logging")
    var verbose: Bool = false

    @Flag(name: .long, help: "Open report in browser after generation")
    var open: Bool = false

    @Flag(name: .long, help: "Log subproject/package detection details")
    var debugSubproject: Bool = false

    func run() async throws {
        print("🚀 Starting SwiftCodeContext analysis for: \(path)")

        let config = ConfigLoader.load()
        DebugFlags.debugSubproject = debugSubproject || config.debugSubproject

        if clearCache {
            await CacheManager().clear()
            print("🗑️  Cache cleared")
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Run pipeline
        print("📂 Scanning repository...")
        let result = try await AnalysisPipeline.run(
            path: path,
            config: config,
            useCache: !noCache,
            verbose: verbose
        )

        let graph = result.graph
        let enrichedFiles = result.enrichedFiles

        print("   Branch: \(result.branchName)")

        // Show hotspots
        let hotspots = graph.getTopHotspots(limit: config.hotspotCount)
        print("\n🗺️  Your Codebase Map")
        print("├─ 🔥 Hot Zones (Top \(min(5, hotspots.count))):")

        for (index, item) in hotspots.prefix(5).enumerated() {
            let fileName = URL(fileURLWithPath: item.path).lastPathComponent
            let prefix = (index == 4 || index == hotspots.count - 1) ? "│   └─" : "│   ├─"
            print("\(prefix) \(fileName) (\(String(format: "%.4f", item.score)))")
        }

        // Generate report
        print("\n📊 Generating report...")
        let outputDir = "output"
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let reportPath = "\(outputDir)/index.html"

        let generator = ReportGenerator()
        let projectName = URL(fileURLWithPath: path).lastPathComponent
        try generator.generate(
            graph: graph,
            outputPath: reportPath,
            parsedFiles: enrichedFiles,
            branchName: result.branchName,
            authorStats: result.authorStats,
            projectName: projectName,
            metadata: result.metadata,
            monkeyPatchedLibs: result.monkeyPatchedLibs
        )

        let reportURL = URL(fileURLWithPath: reportPath).standardizedFileURL
        print("✅ Report: \(reportURL.path)")

        // AI Analysis
        if config.ai.enabled, !config.ai.apiKey.isEmpty {
            print("\n🤖 Generating AI Insights...")
            let aiAnalyzer = AICodeAnalyzer(
                apiKey: config.ai.apiKey,
                model: config.ai.model,
                provider: config.ai.provider
            )

            if aiAnalyzer.isConfigured {
                let insights = await aiAnalyzer.batchAnalyze(
                    files: enrichedFiles, graph: graph, limit: 10
                )

                let aiReportPath = "\(outputDir)/ai-insights.md"
                var md = "# AI Code Insights\n\n"
                for (path, insight) in insights {
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    md += "## \(name)\n"
                    md += "**Purpose**: \(insight.purpose)\n\n"
                    md += "**Complexity**: \(insight.complexity)/10\n"
                    md += "**Refactoring Tips**: \(insight.refactoringTips.joined(separator: ", "))\n\n"
                }
                try md.write(toFile: aiReportPath, atomically: true, encoding: .utf8)
                print("✨ AI Insights saved to: \(aiReportPath)")
            } else {
                print("   ⚠️  AI enabled but not properly configured. Check API key.")
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let totalSeconds = Int(elapsed)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let timeStr: String
        if hours > 0 {
            timeStr = "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            timeStr = "\(minutes)m \(seconds)s"
        } else {
            timeStr = String(format: "%.1fs", elapsed)
        }
        print("\n✨ Complete in \(timeStr)")

        if open {
            #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [reportURL.path]
            try? process.run()
            #endif
        }
    }
}
