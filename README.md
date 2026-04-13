# 🔬 SwiftCodeContext

**Native macOS CLI tool for Swift codebase intelligence** — find critical files, generate dependency graphs, learning paths, and detailed reports.

Built 100% in Swift using Apple-native technologies. **Fully offline. No network required. No telemetry. No accounts.**

> AI-powered features (natural-language Q&A) are available as a separate opt-in — see [AI Integration (Opt-In)](#-ai-integration-opt-in).

---

## ⚡ Generate a Report in 10 Seconds

```bash
cd SwiftCodeContext

# Projects under 200K lines — just run directly
swift run codecontext analyze ~/path/to/your/project --open

# Large projects (200K+ lines) — release build is 5–10× faster
swift build -c release
.build/release/codecontext analyze ~/path/to/your/project --open
```

`--open` opens the HTML report in Safari.

![Based on https://github.com/TelegramMessenger/Telegram-iOS](https://i.postimg.cc/BqgK0jPr/tg.png)

---

## 🔒 Offline by Design

Every core feature runs **entirely on your machine**:

- **Source parsing** — Apple's native SwiftSyntax, no external services
- **Dependency graphs & PageRank** — computed locally
- **Git history analysis** — reads your local `.git` directory
- **HTML report generation** — self-contained, no CDN links, no external assets
- **Caching** — actor-based file cache stored on disk

Your code never leaves your machine unless you explicitly enable the optional AI integration and send a query.

---

## 🚀 Quick Start

```bash
cd SwiftCodeContext

# Build
swift build

# Analyze a Swift project
swift run codecontext analyze /path/to/your/swift/project

# See all commands
swift run codecontext --help
```

---

## 🏗️ Build & Install

### Option 1: Swift CLI (Recommended)

```bash
cd SwiftCodeContext

# Debug build (fast compilation)
swift build

# Run directly
swift run codecontext analyze ~/Projects/MyApp

# Release build (optimized, ~3× faster runtime)
swift build -c release

# The binary is at:
.build/release/codecontext
```

### Option 2: Install System-Wide

```bash
swift build -c release
sudo cp .build/release/codecontext /usr/local/bin/

# Now use from anywhere:
codecontext analyze ~/Projects/MyApp
codecontext evolution --months 12
```

### Option 3: One-Line Install

```bash
swift build -c release && sudo cp .build/release/codecontext /usr/local/bin/ && echo "✅ installed"
```

### Option 4: Xcode (for Development / Debugging)

```bash
open Package.swift
```

In Xcode:
1. Select the `codecontext` scheme
2. Edit Scheme → Run → Arguments → add: `analyze /path/to/your/project`
3. ⌘R to build and run

---

## 📖 Usage

### Analyze a Codebase

```bash
# Analyze current directory
codecontext analyze

# Analyze specific path
codecontext analyze ~/Projects/MyApp

# With options
codecontext analyze ~/Projects/MyApp --no-cache --verbose --open
```

### View Codebase Evolution

```bash
# Default: 6 months back, 30-day intervals
codecontext evolution

# Custom range
codecontext evolution --months 12 --interval 7
```

### Initialize Config

```bash
codecontext init
# Creates .codecontext.json with sensible defaults
```

---

## 📊 What the Report Contains

The generated HTML report is a single self-contained file — open it anywhere, share it, archive it. No internet connection needed to view it.

1. **Summary** — total files, lines of code, declarations by type (structs, classes, enums, protocols, actors), and package count

2. **Team Contribution Map** — developer activity tracking with files modified, commit counts, and first/last change dates

3. **Dependencies & Imports** — comprehensive classification into Apple frameworks, external dependencies, and local Swift packages with interactive tag clouds

4. **Assets** — media resource analysis showing total size, file count by type, and top 3 heaviest files with their individual sizes

5. **Hot Zones** — files with the highest PageRank scores, identifying the most connected and architecturally significant code. Each entry includes clickable module badges and inline documentation previews

6. **Module Insights** — package penetration analysis showing which modules are imported by the most other packages (foundational dependencies), plus quality metrics including TODO/FIXME density and technical debt indicators

7. **Longest Functions** — ranked list of functions by line count, with clickable module badges and quick navigation to potential refactoring candidates

8. **Packages & Modules** — detailed breakdown of each local Swift package:
   - Complete file inventory sorted by lines of code
   - Declaration statistics by type (classes, structs, enums, protocols, actors, extensions)
   - Interactive force-directed dependency graph per package, colored by declaration type (🔵 classes, 🟢 structs, 🟡 enums, 🔴 actors)
   - File-level annotations with inline documentation previews
   - Precise line counts and declaration tags for every file
   - Package-level metrics including total files, lines, and declaration distribution

---

## ⚙️ Configuration

Create `.codecontext.json` in your project root (or run `codecontext init`):

```json
{
    "excludePaths": [".git", ".build", "DerivedData", "Pods", "Carthage"],
    "maxFilesAnalyze": 5000,
    "gitCommitLimit": 1000,
    "enableCache": true,
    "enableParallel": true,
    "hotspotCount": 15,
    "fileExtensions": ["swift"]
}
```

All options above are offline. No network configuration needed.

---

## 🤖 AI Integration (Opt-In)

> **This is entirely optional.** Every feature described above works without it.

If you want to ask natural-language questions about your codebase, you can enable the AI module. This sends a context summary to an external LLM provider, so **review your provider's data policies before enabling**.

### Enable AI

Add an `ai` block to your `.codecontext.json`:

```json
{
    "ai": {
        "enabled": false,
        "provider": "anthropic",
        "apiKey": "",
        "model": "claude-sonnet-4-20250514"
    }
}
```

### Supported AI Providers

| Provider | `provider` | Model examples |
|----------|-----------|----------------|
| Anthropic Claude | `"anthropic"` | `claude-sonnet-4-20250514` |
| Google Gemini | `"gemini"` | `gemini-2.5-flash` |

### Ask Questions

```bash
codecontext ask "Where is the authentication logic?"
codecontext ask "What would break if I refactored UserService?"
```

### What Gets Sent

When you run `ask`, a summary of your project structure and relevant code context is sent to the configured provider. Raw source files are not uploaded in full — the tool assembles a focused context window. No data is sent for any other command (`analyze`, `evolution`, `init`).

---

## 📁 Project Structure

```
SwiftCodeContext/
├── Package.swift
├── Sources/CodeContext/
│   ├── CLI/
│   │   ├── CodeContextCLI.swift           # @main entry point
│   │   ├── AnalyzeCommand.swift           # Main analysis command
│   │   ├── AskCommand.swift               # AI Q&A command (opt-in)
│   │   ├── EvolutionCommand.swift         # Temporal analysis
│   │   └── InitCommand.swift              # Config initialization
│   ├── Core/
│   │   ├── AnalysisPipeline.swift         # Shared pipeline logic
│   │   ├── Config/
│   │   │   └── CodeContextConfig.swift    # Config models + loader
│   │   ├── Cache/
│   │   │   └── CacheManager.swift         # Actor-based file cache
│   │   ├── Parser/
│   │   │   ├── ParsedFile.swift           # Models + protocol
│   │   │   ├── SwiftParser.swift          # Swift source parser
│   │   │   ├── ObjCParser.swift           # ObjC header parser
│   │   │   ├── ParserFactory.swift        # Parser dispatch
│   │   │   └── ParallelParser.swift       # Concurrent parsing
│   │   ├── Scanner/
│   │   │   ├── RepositoryScanner.swift    # Directory walker
│   │   │   └── GitAnalyzer.swift          # Git history via Process
│   │   ├── Graph/
│   │   │   └── DependencyGraph.swift      # Graph + PageRank
│   │   ├── Generator/
│   │   │   └── LearningPathGenerator.swift
│   │   ├── Temporal/
│   │   │   └── TemporalAnalyzer.swift     # Evolution tracking
│   │   ├── AI/
│   │   │   └── AICodeAnalyzer.swift       # URLSession-based AI (opt-in)
│   │   └── Exceptions/
│   │       └── CodeContextError.swift
│   └── Output/
│       └── ReportGenerator.swift          # HTML report
└── Tests/CodeContextTests/
    └── CodeContextTests.swift
```

---

## 🧪 Run Tests

```bash
swift test
```

---

## Requirements

- **macOS 13+** (Ventura or later)
- **Xcode 15+** / Swift 5.9+
- **git** (comes with Xcode Command Line Tools)
- **No internet connection required** for core features
