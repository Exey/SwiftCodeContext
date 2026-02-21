// Exey Panteleev
import Foundation

// MARK: - Parallel Parser

/// Parses source files concurrently using Swift structured concurrency (TaskGroup).
/// Optionally backed by CacheManager for incremental builds.
struct ParallelParser {
    let cache: CacheManager?

    init(cache: CacheManager? = nil) {
        self.cache = cache
    }

    func parseFiles(_ files: [URL]) async -> [ParsedFile] {
        let total = files.count
        let counter = Counter()

        // Dynamic chunk size based on file count
        let chunkSize: Int = {
            switch total {
            case ..<100: return total
            case ..<500: return 50
            default: return 100
            }
        }()

        print("📦 Parsing \(total) files (chunk size: \(chunkSize))...")

        var results: [ParsedFile] = []

        for chunk in files.chunked(into: chunkSize) {
            let chunkResults = await withTaskGroup(of: ParsedFile?.self, returning: [ParsedFile].self) { group in
                for fileURL in chunk {
                    group.addTask {
                        // Check cache first
                        if let cache = self.cache,
                           let cached = await cache.getCachedParse(for: fileURL) {
                            await counter.increment()
                            let count = await counter.value
                            if count % 100 == 0 {
                                print("   Progress: \(count)/\(total) files")
                            }
                            return cached
                        }

                        // Parse
                        guard let parser = ParserFactory.parser(for: fileURL) else { return nil }

                        do {
                            let parsed = try parser.parse(file: fileURL)
                            // Save to cache
                            if let cache = self.cache {
                                await cache.saveParse(for: fileURL, parsed: parsed)
                            }

                            await counter.increment()
                            let count = await counter.value
                            if count % 100 == 0 {
                                print("   Progress: \(count)/\(total) files")
                            }
                            return parsed
                        } catch {
                            print("⚠️  Failed to parse \(fileURL.lastPathComponent): \(error.localizedDescription)")
                            return nil
                        }
                    }
                }

                var collected: [ParsedFile] = []
                for await result in group {
                    if let parsed = result {
                        collected.append(parsed)
                    }
                }
                return collected
            }
            results.append(contentsOf: chunkResults)
        }

        return results
    }
}

// MARK: - Thread-safe Counter (Actor)

private actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

// MARK: - Array Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
