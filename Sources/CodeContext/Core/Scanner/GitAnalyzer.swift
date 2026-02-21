// Exey Panteleev
import Foundation

// MARK: - Author Stats (global, repo-wide)

struct AuthorStats {
    var filesModified: Int = 0
    var totalCommits: Int = 0
    var firstCommitDate: TimeInterval = 0
    var lastCommitDate: TimeInterval = 0
}

// MARK: - Git Analyzer

/// Analyzes git history using the native `git` command line tool.
struct GitAnalyzer {

    let repoPath: String
    let commitLimit: Int

    init(repoPath: String, commitLimit: Int = 500) {
        self.repoPath = repoPath
        self.commitLimit = commitLimit
    }

    // MARK: - Public

    /// Get current branch name
    func currentBranch() -> String {
        let output = git(["rev-parse", "--abbrev-ref", "HEAD"])
        return output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    /// Get global author statistics (first commit, last commit, total commits)
    /// Uses a single `git log` call — very fast.
    func authorStats() -> [String: AuthorStats] {
        let output = git([
            "log",
            "--pretty=format:%an\t%at",
            "-\(commitLimit)"
        ])
        guard let output = output else { return [:] }

        var stats: [String: AuthorStats] = [:]

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            let author = parts[0]
            let timestamp = TimeInterval(parts[1]) ?? 0
            guard timestamp > 0 else { continue }

            var s = stats[author, default: AuthorStats()]
            s.totalCommits += 1
            if s.firstCommitDate == 0 || timestamp < s.firstCommitDate {
                s.firstCommitDate = timestamp
            }
            if timestamp > s.lastCommitDate {
                s.lastCommitDate = timestamp
            }
            stats[author] = s
        }
        return stats
    }

    /// Enrich parsed files with per-file git metadata
    func analyze(files: [ParsedFile]) -> [ParsedFile] {
        let gitDir = URL(fileURLWithPath: repoPath).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            print("⚠️  No .git directory found. Skipping Git analysis.")
            return files
        }

        let total = files.count
        print("🔍 Analyzing git history for \(total) files...")

        var results: [ParsedFile] = []
        let startTime = CFAbsoluteTimeGetCurrent()

        for (index, parsed) in files.enumerated() {
            if (index + 1) % 50 == 0 || index == total - 1 {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                print("   Progress: \(index + 1)/\(total) files (\(String(format: "%.1f", elapsed))s)")
            }

            let relativePath = self.relativePath(for: parsed.filePath)
            let stats = fileStats(for: relativePath)

            if let stats = stats {
                var enriched = parsed
                enriched.gitMetadata = stats
                results.append(enriched)
            } else {
                results.append(parsed)
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("   Git analysis complete in \(String(format: "%.1f", elapsed))s")

        return results
    }

    // MARK: - Per-File Git Log

    private func fileStats(for relativePath: String) -> GitMetadata? {
        let output = git([
            "log",
            "--pretty=format:%an\t%at\t%s",
            "--follow",
            "-\(min(commitLimit, 50))",
            "--", relativePath
        ])

        guard let output = output, !output.isEmpty else { return nil }

        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var authorCounts: [String: Int] = [:]
        var lastModified: TimeInterval = 0
        var firstCommitDate: TimeInterval = .greatestFiniteMagnitude
        var messages: [String] = []

        for line in lines {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }

            let author = parts[0]
            let timestamp = TimeInterval(parts[1]) ?? 0
            let message = parts[2]

            authorCounts[author, default: 0] += 1
            lastModified = max(lastModified, timestamp)
            firstCommitDate = min(firstCommitDate, timestamp)
            if messages.count < 3 {
                messages.append(message)
            }
        }

        let topAuthors = authorCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)

        return GitMetadata(
            lastModified: lastModified,
            changeFrequency: lines.count,
            topAuthors: Array(topAuthors),
            recentMessages: messages,
            firstCommitDate: firstCommitDate == .greatestFiniteMagnitude ? 0 : firstCommitDate
        )
    }

    // MARK: - Helpers

    private func relativePath(for absolutePath: String) -> String {
        let base = URL(fileURLWithPath: repoPath).standardizedFileURL.path
        if absolutePath.hasPrefix(base) {
            var result = String(absolutePath.dropFirst(base.count))
            if result.hasPrefix("/") { result = String(result.dropFirst()) }
            return result
        }
        return absolutePath
    }

    /// Run a git command. Reads stdout BEFORE waitUntilExit to prevent pipe deadlock.
    @discardableResult
    func git(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
