// Exey Panteleev
import ArgumentParser
import Foundation

// MARK: - CodeContext CLI

@main
struct CodeContextCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codecontext",
        abstract: "🔍 CodeContext — Swift Codebase Intelligence Tool",
        discussion: """
        Analyze Swift codebases to find critical files, generate dependency graphs,
        learning paths, and AI-powered insights.

        Built natively for Apple platforms using Swift concurrency.
        """,
        version: "1.0.0",
        subcommands: [
            AnalyzeCommand.self,
            AskCommand.self,
            EvolutionCommand.self,
            InitCommand.self,
        ],
        defaultSubcommand: AnalyzeCommand.self
    )
}
