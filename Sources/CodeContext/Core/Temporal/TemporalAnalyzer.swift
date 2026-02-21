// Exey Panteleev
import Foundation

// MARK: - Codebase Snapshot

struct CodebaseSnapshot: Codable {
    let timestamp: Date
    let commitHash: String
    let totalFiles: Int
    let totalLines: Int
}

// MARK: - Temporal Analyzer

/// Analyzes how the codebase evolved over time using git history snapshots.
/// Uses native `git` commands — no JGit dependency.
struct TemporalAnalyzer {
    let repoPath: String
    let fileExtensions: Set<String>

    init(repoPath: String, fileExtensions: [String] = ["swift"]) {
        self.repoPath = repoPath
        self.fileExtensions = Set(fileExtensions)
    }

    func analyzeEvolution(monthsBack: Int = 6, intervalDays: Int = 30) -> [CodebaseSnapshot] {
        // Get commits at regular intervals
        let commits = sampleCommits(monthsBack: monthsBack, intervalDays: intervalDays)

        guard !commits.isEmpty else {
            print("⚠️  No commits found in history.")
            return []
        }

        print("⏳ Analyzing evolution across \(commits.count) snapshots...")

        return commits.enumerated().compactMap { index, commit in
            print("   [\(index + 1)/\(commits.count)] Snapshot at \(commit.hash.prefix(7))")
            return analyzeSnapshot(commit: commit)
        }
    }

    // MARK: - Private

    private struct CommitRef {
        let hash: String
        let timestamp: Date
    }

    private func sampleCommits(monthsBack: Int, intervalDays: Int) -> [CommitRef] {
        // Get all commit hashes and timestamps
        let output = git(["log", "--pretty=format:%H %at", "--reverse"])
        guard let output = output else { return [] }

        let allCommits: [CommitRef] = output.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count == 2,
                  let ts = TimeInterval(parts[1]) else { return nil }
            return CommitRef(hash: String(parts[0]), timestamp: Date(timeIntervalSince1970: ts))
        }

        guard !allCommits.isEmpty else { return [] }

        let now = allCommits.last!.timestamp
        let cutoff = now.addingTimeInterval(-Double(monthsBack * 30 * 86400))

        // Sample at intervals
        var sampled: [CommitRef] = []
        var target = now

        while target > cutoff {
            if let closest = allCommits.min(by: {
                abs($0.timestamp.timeIntervalSince(target)) < abs($1.timestamp.timeIntervalSince(target))
            }), !sampled.contains(where: { $0.hash == closest.hash }) {
                sampled.append(closest)
            }
            target = target.addingTimeInterval(-Double(intervalDays * 86400))
        }

        return sampled.sorted { $0.timestamp < $1.timestamp }
    }

    private func analyzeSnapshot(commit: CommitRef) -> CodebaseSnapshot? {
        // Use git ls-tree to count files at this commit without checkout
        let output = git(["ls-tree", "-r", "--name-only", commit.hash])
        guard let output = output else { return nil }

        let files = output.components(separatedBy: "\n").filter { line in
            let ext = URL(fileURLWithPath: line).pathExtension.lowercased()
            return fileExtensions.contains(ext)
        }

        return CodebaseSnapshot(
            timestamp: commit.timestamp,
            commitHash: commit.hash,
            totalFiles: files.count,
            totalLines: files.count * 50  // Estimate; could use git show for accuracy
        )
    }

    private func git(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            // Read BEFORE wait to avoid pipe buffer deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
