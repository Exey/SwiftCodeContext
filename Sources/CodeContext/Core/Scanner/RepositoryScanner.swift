// Exey Panteleev
import Foundation

// MARK: - Repository Scanner

/// Scans a directory recursively for source files, respecting exclude paths from config.
struct RepositoryScanner {
    let config: CodeContextConfig

    init(config: CodeContextConfig = ConfigLoader.load()) {
        self.config = config
    }

    func scan(rootPath: String) throws -> [URL] {
        let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
        let fm = FileManager.default

        guard fm.fileExists(atPath: rootURL.path) else {
            throw CodeContextError.analysis("Path does not exist: \(rootPath)")
        }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw CodeContextError.analysis("Path is not a directory: \(rootPath)")
        }

        let allowedExtensions = Set(config.fileExtensions)
        let excludeSet = Set(config.excludePaths)

        var results: [URL] = []

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            let components = relativePath.components(separatedBy: "/")

            // Check if any path component is in the exclude list
            if components.contains(where: { excludeSet.contains($0) }) {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                   resourceValues.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
               resourceValues.isRegularFile == true,
               allowedExtensions.contains(fileURL.pathExtension.lowercased()) {
                results.append(fileURL)
            }
        }

        return results
    }
}
