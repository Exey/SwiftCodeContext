// Exey Panteleev
import Foundation

// MARK: - Analysis Pipeline

/// Detected project metadata (Swift version, deployment targets)
struct ProjectMetadata {
    var swiftVersion: String = ""          // e.g. "5.9", "6.0", "5.5+"
    var swiftVersionSource: String = ""    // e.g. "Package.swift", "code analysis"
    var deploymentTargets: [String] = []   // e.g. ["iOS 16", "macOS 13"]
    var deploymentSource: String = ""      // e.g. "Package.swift", "Telegram-iOS.xcodeproj"
}

enum AnalysisPipeline {

    struct Result {
        let graph: DependencyGraph
        let parsedFiles: [ParsedFile]
        let enrichedFiles: [ParsedFile]
        let branchName: String
        let authorStats: [String: AuthorStats]
        let metadata: ProjectMetadata
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

        // Detect project metadata
        let metadata = detectProjectMetadata(rootPath: path)
        if !metadata.swiftVersion.isEmpty {
            print("   🔧 Swift \(metadata.swiftVersion) (from \(metadata.swiftVersionSource))")
        } else {
            print("   🔧 Swift version: not detected")
        }
        if !metadata.deploymentTargets.isEmpty {
            print("   📱 Deployment: \(metadata.deploymentTargets.joined(separator: ", ")) (from \(metadata.deploymentSource))")
        } else {
            print("   📱 Deployment target: not detected")
        }

        let cache: CacheManager? = (config.enableCache && useCache) ? CacheManager() : nil
        let parser = ParallelParser(cache: cache)
        let parsedFiles = await parser.parseFiles(files)
        print("   Parsed \(parsedFiles.count) files")

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
            branchName: branchName, authorStats: mergedStats, metadata: metadata
        )
    }

    // MARK: - Project Metadata Detection

    /// Detect Swift version and deployment targets from Package.swift, .pbxproj, or code analysis
    private static func detectProjectMetadata(rootPath: String) -> ProjectMetadata {
        var meta = ProjectMetadata()
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL

        // 1. Try Package.swift (root level)
        let packageSwiftPath = rootURL.appendingPathComponent("Package.swift").path
        if let content = try? String(contentsOfFile: packageSwiftPath, encoding: .utf8) {
            if let range = content.range(of: "swift-tools-version:\\s*([\\d.]+)", options: .regularExpression) {
                let match = content[range]
                if let verRange = match.range(of: "[\\d.]+", options: .regularExpression) {
                    meta.swiftVersion = String(match[verRange])
                    meta.swiftVersionSource = "Package.swift"
                }
            }
            if let platRange = content.range(of: "platforms:\\s*\\[([^\\]]+)\\]", options: .regularExpression) {
                let platStr = String(content[platRange])
                let platPattern = try! NSRegularExpression(pattern: "\\.(iOS|macOS|tvOS|watchOS|visionOS)\\(\\.v([\\w._]+)\\)")
                let nsRange = NSRange(platStr.startIndex..., in: platStr)
                for match in platPattern.matches(in: platStr, range: nsRange) {
                    if let osRange = Range(match.range(at: 1), in: platStr),
                       let verRange = Range(match.range(at: 2), in: platStr) {
                        let os = String(platStr[osRange])
                        let ver = String(platStr[verRange]).replacingOccurrences(of: "_", with: ".")
                        meta.deploymentTargets.append("\(os) \(ver)")
                    }
                }
                meta.deploymentSource = "Package.swift"
            }
        }

        // 2. Try .pbxproj (Xcode project)
        if meta.swiftVersion.isEmpty || meta.deploymentTargets.isEmpty {
            if let items = try? fm.contentsOfDirectory(atPath: rootURL.path) {
                for item in items where item.hasSuffix(".xcodeproj") {
                    let pbxPath = rootURL.appendingPathComponent(item).appendingPathComponent("project.pbxproj").path
                    if let content = try? String(contentsOfFile: pbxPath, encoding: .utf8) {
                        if meta.swiftVersion.isEmpty {
                            let pat = try! NSRegularExpression(pattern: "SWIFT_VERSION\\s*=\\s*([\\d.]+)")
                            let r = NSRange(content.startIndex..., in: content)
                            if let m = pat.firstMatch(in: content, range: r), let vr = Range(m.range(at: 1), in: content) {
                                meta.swiftVersion = String(content[vr])
                                meta.swiftVersionSource = item
                            }
                        }
                        if meta.deploymentTargets.isEmpty {
                            let targets: [(String, String)] = [
                                ("IPHONEOS_DEPLOYMENT_TARGET", "iOS"),
                                ("MACOSX_DEPLOYMENT_TARGET", "macOS"),
                                ("TVOS_DEPLOYMENT_TARGET", "tvOS"),
                                ("WATCHOS_DEPLOYMENT_TARGET", "watchOS"),
                            ]
                            for (key, label) in targets {
                                let pat = try! NSRegularExpression(pattern: "\(key)\\s*=\\s*([\\d.]+)")
                                let r = NSRange(content.startIndex..., in: content)
                                if let m = pat.firstMatch(in: content, range: r), let vr = Range(m.range(at: 1), in: content) {
                                    meta.deploymentTargets.append("\(label) \(content[vr])")
                                }
                            }
                            if !meta.deploymentTargets.isEmpty { meta.deploymentSource = item }
                        }
                        break
                    }
                }
            }
        }

        // 3. If still no Swift version, infer from code features by scanning a sample of files
        if meta.swiftVersion.isEmpty {
            meta.swiftVersion = inferSwiftVersionFromCode(rootPath: rootPath)
            if !meta.swiftVersion.isEmpty { meta.swiftVersionSource = "code analysis" }
        }

        return meta
    }

    /// Infer minimum Swift version by scanning source files for version-specific features.
    /// Scans up to 200 .swift files to keep it fast.
    private static func inferSwiftVersionFromCode(rootPath: String) -> String {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL

        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return ""
        }

        var detected = "5.0"
        var filesScanned = 0
        let maxFiles = 200


        // Regex patterns for more precise detection
        let actorPattern = try! NSRegularExpression(pattern: "(?<![a-zA-Z0-9_])actor\\s+[A-Z]")
        let asyncPattern = try! NSRegularExpression(pattern: "\\basync\\b")
        let awaitPattern = try! NSRegularExpression(pattern: "\\bawait\\b")
        let shorthandIfLet = try! NSRegularExpression(pattern: "if\\s+let\\s+(\\w+)\\s*\\{") // if let name {
        let typedThrows = try! NSRegularExpression(pattern: "throws\\s*\\(\\s*\\w+")

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift",
                  let res = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  res.isRegularFile == true else { continue }

            // Skip tests, generated, build dirs
            let path = fileURL.path
            if path.contains("/Tests/") || path.contains("/.build/") || path.contains("/DerivedData/") { continue }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            filesScanned += 1

            let nsRange = NSRange(content.startIndex..., in: content)

            // Check from highest version down
            if detected < "6.0" {
                if typedThrows.firstMatch(in: content, range: nsRange) != nil ||
                    content.contains("@Test") || content.contains("nonisolated(unsafe)") {
                    detected = "6.0"
                }
            }
            if detected < "5.9" {
                if content.contains("@Observable") || content.contains("#Predicate") || content.contains("#Preview") {
                    detected = "5.9"
                }
            }
            if detected < "5.7" {
                if shorthandIfLet.firstMatch(in: content, range: nsRange) != nil ||
                    content.contains("ContinuousClock") || content.contains("SuspendingClock") {
                    detected = "5.7"
                }
            }
            if detected < "5.5" {
                if asyncPattern.firstMatch(in: content, range: nsRange) != nil ||
                    awaitPattern.firstMatch(in: content, range: nsRange) != nil ||
                    actorPattern.firstMatch(in: content, range: nsRange) != nil ||
                    content.contains("@MainActor") {
                    detected = "5.5"
                }
            }
            if detected < "5.3" {
                if content.contains("@main") {
                    detected = "5.3"
                }
            }
            if detected < "5.1" {
                if content.contains("some ") || content.contains("@State") ||
                    content.contains("@Published") || content.contains("@Binding") {
                    detected = "5.1"
                }
            }

            // Early exit if we already found the highest version
            if detected >= "6.0" { break }
            if filesScanned >= maxFiles { break }
        }

        return detected == "5.0" ? "" : detected + "+"
    }
}
