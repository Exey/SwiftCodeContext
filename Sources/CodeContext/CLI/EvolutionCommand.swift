// Exey Panteleev
import ArgumentParser
import Foundation

// MARK: - Evolution Command

struct EvolutionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "evolution",
        abstract: "Analyze codebase evolution over time"
    )

    @Option(name: .long, help: "Months back to analyze")
    var months: Int = 6

    @Option(name: .long, help: "Days between snapshots")
    var interval: Int = 30

    @Option(name: .long, help: "Path to the repository")
    var path: String = "."

    func run() async throws {
        print("⏳ Starting Temporal Analysis (Time Machine)...")
        print("   Looking back \(months) months, every \(interval) days.")

        let repoPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let config = ConfigLoader.load()
        let analyzer = TemporalAnalyzer(repoPath: repoPath, fileExtensions: config.fileExtensions)

        let snapshots = analyzer.analyzeEvolution(monthsBack: months, intervalDays: interval)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        print("\n📈 Evolution Report:")
        print("------------------------------------------------")

        for s in snapshots {
            let dateStr = formatter.string(from: s.timestamp)
            let hash = String(s.commitHash.prefix(7))
            print("\(dateStr) | \(hash) | Files: \(s.totalFiles) | Lines: \(s.totalLines)")
        }

        if snapshots.isEmpty {
            print("⚠️  No history found. Is this a git repository?")
        } else if let first = snapshots.first, let last = snapshots.last, first.totalFiles > 0 {
            let growth = Double(last.totalFiles - first.totalFiles) / Double(first.totalFiles) * 100
            print("\n📊 Net Growth: \(String(format: "%.1f", growth))%")
        }
    }
}
