// Exey Panteleev
import ArgumentParser
import Foundation

// MARK: - Init Command

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize CodeContext configuration in current directory"
    )

    func run() async throws {
        let configPath = ".codecontext.json"

        if FileManager.default.fileExists(atPath: configPath) {
            print("⚠️  Config already exists at \(configPath)")
            print("   Delete it first if you want to re-initialize.")
            return
        }

        try ConfigLoader.createDefault(at: configPath)
        print("""

        📋 Next steps:
           1. Edit .codecontext.json to customize settings
           2. Set ai.enabled = true and ai.apiKey for AI features
           3. Run: codecontext analyze .
        """)
    }
}
