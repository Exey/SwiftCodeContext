// Exey Panteleev
import Foundation

// MARK: - Parser Factory

enum ParserFactory {
    private static let swiftParser = SwiftParser()
    private static let objcParser = ObjCParser()

    static func parser(for file: URL) -> LanguageParser? {
        switch file.pathExtension.lowercased() {
        case "swift":
            return swiftParser
        case "h", "m", "mm":
            return objcParser
        default:
            return nil
        }
    }

    static var supportedExtensions: Set<String> {
        ["swift", "h", "m", "mm"]
    }
}
