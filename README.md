# 🔬 SwiftCodeContext

**Native macOS CLI tool for Swift codebase intelligence** — find critical files, generate dependency graphs, learning paths.

Built 100% in Swift using Apple-native technologies

---

## ⚡ Generate Report in 10 Seconds

```bash
cd SwiftCodeContext

# Projects under 200K lines — just run directly
swift run codecontext analyze ~/path/to/your/project --open

# Large projects (200K+ lines) — release build is 5-10× faster
swift build -c release
.build/release/codecontext analyze ~/path/to/your/project --open
```

`--open` opens the HTML report in Safari.

![Based on https://github.com/TelegramMessenger/Telegram-iOS](https://i.postimg.cc/BqgK0jPr/tg.png)

### What the Report Contains

The generated HTML report includes:

1. **📊 Summary** — total files, lines of code, declarations by type (structs, classes, enums, protocols, actors), and package count

2. **👥 Team Contribution Map** — developer activity tracking with files modified, commit counts, and first/last change dates

3. **📚 Dependencies & Imports** — comprehensive classification into Apple frameworks, external dependencies, and local Swift packages with interactive tag clouds

4. **🎨 Assets** — media resource analysis showing total size, file count by type, and top 3 heaviest files with their individual sizes

5. **🔥 Hot Zones** — files with the highest PageRank scores, identifying the most connected and architecturally significant code. Each entry includes clickable module badges for quick navigation and inline documentation previews where available

6. **📋 Module Insights** — package penetration analysis showing which modules are imported by the most other packages (foundational dependencies), plus quality metrics including top modules by TODO/FIXME density and technical debt indicators

7. **📏 Longest Functions** — ranked list of functions with the highest line counts, featuring clickable module badges for context and quick navigation to potential refactoring candidates

8. **📦 Packages & Modules** — detailed breakdown of each local Swift package with:
   - Complete file inventory sorted by lines of code
   - Declaration statistics by type (classes, structs, enums, protocols, actors, extensions)
   - Interactive force-directed dependency graph per package, colored by declaration type (🔵 classes, 🟢 structs, 🟡 enums, 🔴 actors)
   - File-level annotations showing code intent through inline documentation previews
   - Precise line counts and declaration tags for every file
   - Package-level metrics including total files, lines of code, and declaration distribution

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

## 🏗️ How to Build & Install

### Option 1: Swift CLI (Recommended)

```bash
cd SwiftCodeContext

# Debug build (fast compilation)
swift build

# Run directly
swift run codecontext analyze ~/Projects/MyApp

# Release build (optimized, ~3x faster runtime)
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
codecontext ask "Where is the networking layer?"
```

### Option 3: One-Line Install Script

```bash
swift build -c release && sudo cp .build/release/codecontext /usr/local/bin/ && echo "✅ installed"
```

### Option 4: Xcode (for Development / Debugging)

```bash
# Open as Swift Package (Xcode 15+)
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

# --open automatically opens the HTML report in Safari
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
    "fileExtensions": ["swift"],
    "ai": {
        "enabled": false,
        "provider": "anthropic",
        "apiKey": "",
        "model": "claude-sonnet-4-20250514"
    }
}
```

---

## 📁 Project Structure

```
SwiftCodeContext/
├── Package.swift
├── Sources/CodeContext/
│   ├── CLI/
│   │   ├── CodeContextCLI.swift           # @main entry point
│   │   ├── AnalyzeCommand.swift           # Main analysis command
│   │   ├── AskCommand.swift               # AI Q&A command
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
│   │   │   └── AICodeAnalyzer.swift       # URLSession-based AI
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
