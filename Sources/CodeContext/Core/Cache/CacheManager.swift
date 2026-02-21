// Exey Panteleev
import Foundation
import CryptoKit

// MARK: - Cache Manager

/// Thread-safe file parse cache using Swift actor isolation.
/// Stores parsed file JSON in .codecontext/cache/ directory.
actor CacheManager {
    private let cacheDir: URL

    init(cacheDir: URL = URL(fileURLWithPath: ".codecontext/cache")) {
        self.cacheDir = cacheDir
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func getCachedParse(for fileURL: URL) -> ParsedFile? {
        let key = cacheKey(for: fileURL)
        let cacheFile = cacheDir.appendingPathComponent("\(key).json")

        guard FileManager.default.fileExists(atPath: cacheFile.path) else { return nil }

        // Check freshness: source newer than cache → invalidate
        do {
            let sourceAttrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let cacheAttrs = try FileManager.default.attributesOfItem(atPath: cacheFile.path)

            if let sourceMod = sourceAttrs[.modificationDate] as? Date,
               let cacheMod = cacheAttrs[.modificationDate] as? Date,
               sourceMod > cacheMod {
                return nil
            }

            let data = try Data(contentsOf: cacheFile)
            return try JSONDecoder().decode(ParsedFile.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: cacheFile)
            return nil
        }
    }

    func saveParse(for fileURL: URL, parsed: ParsedFile) {
        let key = cacheKey(for: fileURL)
        let cacheFile = cacheDir.appendingPathComponent("\(key).json")
        let tempFile = cacheFile.appendingPathExtension("tmp")

        do {
            let data = try JSONEncoder().encode(parsed)
            try data.write(to: tempFile, options: .atomic)
            // Atomic rename
            _ = try FileManager.default.replaceItemAt(cacheFile, withItemAt: tempFile)
        } catch {
            try? FileManager.default.removeItem(at: tempFile)
            fputs("Failed to cache \(fileURL.lastPathComponent): \(error.localizedDescription)\n", stderr)
        }
    }

    func clear() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Private

    private func cacheKey(for fileURL: URL) -> String {
        let path = fileURL.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mod = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? UInt64) ?? 0

        let metadata = "\(path):\(mod):\(size)"
        let digest = Insecure.MD5.hash(data: Data(metadata.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
