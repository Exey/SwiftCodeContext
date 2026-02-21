// Exey Panteleev
import Foundation

// MARK: - CodeContext Errors

enum CodeContextError: LocalizedError {
    case configuration(String)
    case aiProvider(String)
    case analysis(String)
    case gitError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .configuration(let msg): return "Configuration error: \(msg)"
        case .aiProvider(let msg): return "AI provider error: \(msg)"
        case .analysis(let msg): return "Analysis error: \(msg)"
        case .gitError(let msg): return "Git error: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}
