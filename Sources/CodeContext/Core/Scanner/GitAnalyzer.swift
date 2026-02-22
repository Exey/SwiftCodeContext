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
/// Uses a batch approach for large repos: one `git log --name-only` call
/// to gather per-file stats instead of N individual calls.
struct GitAnalyzer {

    let repoPath: String
    let commitLimit: Int

    init(repoPath: String, commitLimit: Int = 500) {
        self.repoPath = repoPath
        self.commitLimit = commitLimit
    }

    // MARK: - Public

    func currentBranch() -> String {
        let output = git(["rev-parse", "--abbrev-ref", "HEAD"])
        return output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    /// Global author stats from a single git log call.
    func authorStats() -> [String: AuthorStats] {
        let output = git([
            "log", "--pretty=format:%an\t%at", "-\(commitLimit)"
        ])
        guard let output = output else { return [:] }
        var stats: [String: AuthorStats] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count >= 2 else { continue }
            let author = String(parts[0])
            let ts = TimeInterval(parts[1]) ?? 0
            guard ts > 0 else { continue }
            var s = stats[author, default: AuthorStats()]
            s.totalCommits += 1
            if s.firstCommitDate == 0 || ts < s.firstCommitDate { s.firstCommitDate = ts }
            if ts > s.lastCommitDate { s.lastCommitDate = ts }
            stats[author] = s
        }
        return stats
    }

    /// Batch-enrich files with git metadata using ONE git log call.
    func analyze(files: [ParsedFile]) -> [ParsedFile] {
        let gitDir = URL(fileURLWithPath: repoPath).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            print("⚠️  No .git directory found. Skipping Git analysis.")
            return files
        }

        let total = files.count
        print("🔍 Analyzing git history (\(total) files, batch mode)...")
        let startTime = CFAbsoluteTimeGetCurrent()

        // Build file stats from single batch git log
        let batchStats = batchCollectFileStats()

        let elapsed1 = CFAbsoluteTimeGetCurrent() - startTime
        print("   Batch git log parsed in \(String(format: "%.1f", elapsed1))s (\(batchStats.count) file entries)")

        // Enrich files
        var results: [ParsedFile] = []
        for file in files {
            let rel = relativePath(for: file.filePath)
            if let fs = batchStats[rel] {
                let topAuthors = fs.authorCounts
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map(\.key)
                var enriched = file
                enriched.gitMetadata = GitMetadata(
                    lastModified: fs.lastModified,
                    changeFrequency: fs.changeCount,
                    topAuthors: Array(topAuthors),
                    recentMessages: Array(fs.messages.prefix(3)),
                    firstCommitDate: fs.firstCommitDate
                )
                results.append(enriched)
            } else {
                results.append(file)
            }
        }

        let elapsed2 = CFAbsoluteTimeGetCurrent() - startTime
        print("   Git analysis complete in \(String(format: "%.1f", elapsed2))s")
        return results
    }

    // MARK: - Batch Collection

    /// Single `git log --name-only` call. Streams output via pipe.
    /// For a 5000-file repo with 500 commits, this takes ~2-5s instead of ~50 min.
    private func batchCollectFileStats() -> [String: FileStats] {
        // We use streaming read to handle arbitrarily large output
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "log",
            "--pretty=format:__COMMIT__%n%an%n%at%n%s",
            "--name-only",
            "-\(commitLimit)"
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return [:]
        }

        // Read ALL data first (before waitUntilExit) to avoid pipe deadlock
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return [:]
        }

        // Parse
        var stats: [String: FileStats] = [:]
        let blocks = output.components(separatedBy: "__COMMIT__\n")

        for block in blocks where !block.isEmpty {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.count >= 3 else { continue }

            let author = String(lines[0])
            let timestamp = TimeInterval(lines[1]) ?? 0
            let message = String(lines[2])
            let changedFiles = lines.dropFirst(3)

            for fileLine in changedFiles {
                let trimmed = fileLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                var entry = stats[trimmed, default: FileStats()]
                entry.changeCount += 1
                entry.lastModified = max(entry.lastModified, timestamp)
                if entry.firstCommitDate == 0 || (timestamp > 0 && timestamp < entry.firstCommitDate) {
                    entry.firstCommitDate = timestamp
                }
                entry.authorCounts[author, default: 0] += 1
                if entry.messages.count < 5 {
                    entry.messages.append(message)
                }
                stats[trimmed] = entry
            }
        }
        return stats
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
        } catch { return nil }
    }
}

// MARK: - File Stats

private struct FileStats {
    var changeCount: Int = 0
    var lastModified: TimeInterval = 0
    var firstCommitDate: TimeInterval = 0
    var authorCounts: [String: Int] = [:]
    var messages: [String] = []
}
