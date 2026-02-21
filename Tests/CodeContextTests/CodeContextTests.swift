// Exey Panteleev
import XCTest
@testable import CodeContext

final class CodeContextTests: XCTestCase {

    // MARK: - Config Tests

    func testDefaultConfig() {
        let config = CodeContextConfig()
        XCTAssertEqual(config.maxFilesAnalyze, 5000)
        XCTAssertTrue(config.enableCache)
        XCTAssertTrue(config.fileExtensions.contains("swift"))
        XCTAssertFalse(config.ai.enabled)
    }

    // MARK: - Graph Tests

    func testGraphPageRank() {
        let graph = DependencyGraph()
        graph.addVertex("A")
        graph.addVertex("B")
        graph.addVertex("C")
        graph.addEdge(from: "A", to: "B")
        graph.addEdge(from: "A", to: "C")
        graph.addEdge(from: "B", to: "C")

        graph.computePageRank()
        let scores = graph.pageRankScores
        XCTAssertGreaterThan(scores["C"] ?? 0, scores["A"] ?? 0)
    }

    func testTopologicalSort() {
        let graph = DependencyGraph()
        graph.addVertex("A")
        graph.addVertex("B")
        graph.addEdge(from: "A", to: "B")

        let topo = graph.topologicalSort()
        XCTAssertNotNil(topo)
        XCTAssertEqual(topo?.first, "A")
    }

    func testSelfEdgeIgnored() {
        let graph = DependencyGraph()
        graph.addVertex("A")
        graph.addEdge(from: "A", to: "A")
        XCTAssertEqual(graph.edges.count, 0)
    }

    // MARK: - Parser Tests

    func testSwiftParserExtractsEverything() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let testFile = tmpDir.appendingPathComponent("TestFile.swift")

        let content = """
        /// A test file for parsing
        import Foundation
        import UIKit
        import MyModule

        class TestClass {
            func doSomething() {}
        }

        struct TestStruct: Codable {}

        protocol TestProtocol {}

        enum TestEnum { case a, b }
        """
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let parser = SwiftParser()
        let parsed = try parser.parse(file: testFile)

        XCTAssertEqual(parsed.imports, ["Foundation", "UIKit", "MyModule"])
        XCTAssertFalse(parsed.description.isEmpty)
        XCTAssertGreaterThan(parsed.lineCount, 10)

        // Declarations
        XCTAssertEqual(parsed.declarations.count, 4)
        XCTAssertTrue(parsed.declarations.contains { $0.name == "TestClass" && $0.kind == .class })
        XCTAssertTrue(parsed.declarations.contains { $0.name == "TestStruct" && $0.kind == .struct })
        XCTAssertTrue(parsed.declarations.contains { $0.name == "TestProtocol" && $0.kind == .protocol })
        XCTAssertTrue(parsed.declarations.contains { $0.name == "TestEnum" && $0.kind == .enum })

        try? FileManager.default.removeItem(at: testFile)
    }

    func testPackageNameInference() throws {
        // Create temp structure: .../Packages/MyPkg/Sources/MyPkg/File.swift
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let pkgDir = tmpDir
            .appendingPathComponent("Packages")
            .appendingPathComponent("MyPkg")
            .appendingPathComponent("Sources")
            .appendingPathComponent("MyPkg")

        try FileManager.default.createDirectory(at: pkgDir, withIntermediateDirectories: true)

        let testFile = pkgDir.appendingPathComponent("Hello.swift")
        try "import Foundation\nstruct Hello {}".write(to: testFile, atomically: true, encoding: .utf8)

        let parser = SwiftParser()
        let parsed = try parser.parse(file: testFile)

        XCTAssertEqual(parsed.packageName, "MyPkg")
        XCTAssertEqual(parsed.moduleName, "MyPkg")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Array Chunking Tests

    func testArrayChunking() {
        let arr = [1, 2, 3, 4, 5]
        let chunks = arr.chunked(into: 2)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], [1, 2])
        XCTAssertEqual(chunks[2], [5])
    }
}
