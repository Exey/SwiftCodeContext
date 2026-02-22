// Exey Panteleev
import Foundation

// MARK: - Analysis Pipeline

enum AnalysisPipeline {

    struct Result {
        let graph: DependencyGraph
        let parsedFiles: [ParsedFile]
        let enrichedFiles: [ParsedFile]
        let branchName: String
        let authorStats: [String: AuthorStats]
    }

    static func run(
        path: String,
        config: CodeContextConfig = ConfigLoader.load(),
        useCache: Bool = true,
        verbose: Bool = false
    ) async throws -> Result {
        let scanner = RepositoryScanner(config: config)
        let files = try scanner.scan(rootPath: path)

        guard !files.isEmpty else {
            throw CodeContextError.analysis("No source files found.")
        }
        if files.count > config.maxFilesAnalyze {
            throw CodeContextError.analysis("Too many files (\(files.count)). Limit: \(config.maxFilesAnalyze)")
        }
        print("   Found \(files.count) files")

        let cache: CacheManager? = (config.enableCache && useCache) ? CacheManager() : nil
        let parser = ParallelParser(cache: cache)
        let parsedFiles = await parser.parseFiles(files)
        print("   Parsed \(parsedFiles.count) files")

        // Show detected modules
        let moduleNames = Set(parsedFiles.compactMap { $0.packageName.isEmpty ? nil : $0.packageName })
        if !moduleNames.isEmpty {
            print("   📦 Detected modules: \(moduleNames.sorted().joined(separator: ", "))")
        }

        print("📜 Analyzing Git history...")
        let repoAbsPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let gitAnalyzer = GitAnalyzer(repoPath: repoAbsPath, commitLimit: config.gitCommitLimit)
        let branchName = gitAnalyzer.currentBranch()
        let globalAuthorStats = gitAnalyzer.authorStats()
        let enrichedFiles = gitAnalyzer.analyze(files: parsedFiles)

        print("🕸️  Building dependency graph...")
        let graph = DependencyGraph()
        graph.build(from: enrichedFiles)
        graph.analyze()

        var mergedStats = globalAuthorStats
        for file in enrichedFiles {
            for author in file.gitMetadata.topAuthors {
                mergedStats[author, default: AuthorStats()].filesModified += 1
            }
        }

        return Result(
            graph: graph, parsedFiles: parsedFiles, enrichedFiles: enrichedFiles,
            branchName: branchName, authorStats: mergedStats
        )
    }
}
