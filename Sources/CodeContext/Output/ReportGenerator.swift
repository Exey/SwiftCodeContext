// Exey Panteleev
import Foundation

// MARK: - Report Graph Models

struct GraphNode: Codable {
    let id: String
    let label: String
    let sublabel: String
    let kind: String
    let score: Double
    let group: String
}

struct GraphLink: Codable {
    let source: String
    let target: String
}

struct GraphData: Codable {
    let nodes: [GraphNode]
    let links: [GraphLink]
}

// MARK: - Import Classification

enum ImportKind: Comparable {
    case apple, external, local
    var label: String {
        switch self { case .apple: return "Apple Frameworks"; case .external: return "External Dependencies"; case .local: return "Local Packages" }
    }
    var icon: String {
        switch self { case .apple: return "🍎"; case .external: return "📦"; case .local: return "🏠" }
    }
}

// MARK: - Package Summary

struct PackageSummary {
    let name: String
    let files: [ParsedFile]
    var totalLines: Int { files.reduce(0) { $0 + $1.lineCount } }
    var declarations: [Declaration] { files.flatMap(\.declarations) }
    var realDeclarations: [Declaration] { declarations.filter { $0.kind != .extension } }
    var protocolCount: Int { declarations.filter { $0.kind == .protocol }.count }
    var classCount: Int { declarations.filter { $0.kind == .class }.count }
    var structCount: Int { declarations.filter { $0.kind == .struct }.count }
    var enumCount: Int { declarations.filter { $0.kind == .enum }.count }
    var actorCount: Int { declarations.filter { $0.kind == .actor }.count }
    var extensionCount: Int { declarations.filter { $0.kind == .extension }.count }
}

// MARK: - Report Generator

struct ReportGenerator {

    // Complete Apple public frameworks list (from developer.apple.com)
    private let appleFrameworks: Set<String> = [
        // A
        "Accelerate", "Accessibility", "AccessoryNotifications", "AccessorySetupKit",
        "AccessoryTransportExtension", "AccountDataTransfer", "AccountOrganizationalDataSharing",
        "Accounts", "ActivityKit", "AdAttributionKit", "AddressBook", "AddressBookUI",
        "AdServices", "AdSupport", "AlarmKit", "AppClips", "AppDataTransfer", "AppIntents",
        "AppKit", "AppleArchive", "ApplePencil", "ApplicationServices", "AppMigrationKit",
        "AppTrackingTransparency", "ARKit", "AssetsLibrary", "AudioToolbox", "AudioUnit",
        "AuthenticationServices", "AutomaticAssessmentConfiguration", "Automator",
        // AV
        "AVFAudio", "AVFoundation", "AVKit", "AVRouting",
        // B
        "BackgroundAssets", "BackgroundTasks", "BrowserEngineCore", "BrowserEngineKit",
        "BundleResources", "BusinessChat",
        // C
        "CallKit", "CareKit", "CarKey", "CarPlay", "CFNetwork", "Cinematic", "ClassKit",
        "ClockKit", "CloudKit", "Collaboration", "ColorSync", "Combine", "Compression",
        "CompositorServices", "ContactProvider", "Contacts", "ContactsUI",
        "CoreAnimation", "CoreAudio", "CoreAudioKit", "CoreAudioTypes", "CoreBluetooth",
        "CoreData", "CoreFoundation", "CoreGraphics", "CoreHaptics", "CoreHID", "CoreImage",
        "CoreLocation", "CoreLocationUI", "CoreMedia", "CoreMediaIO", "CoreMIDI", "CoreML",
        "CoreMotion", "CoreNFC", "CoreServices", "CoreSpotlight", "CoreTelephony", "CoreText",
        "CoreTransferable", "CoreVideo", "CoreWLAN", "CreateML", "CreateMLComponents",
        "CryptoKit", "CryptoTokenKit",
        // D
        "Darwin", "DarwinNotify", "DataDetection", "DeveloperToolsSupport", "DeviceActivity",
        "DeviceCheck", "DeviceDiscoveryExtension", "DeviceDiscoveryUI", "DeviceManagement",
        "DiskArbitration", "Dispatch", "Distributed", "dnssd", "DockKit", "DriverKit",
        // E
        "EndpointSecurity", "EnergyKit", "EventKit", "EventKitUI", "ExceptionHandling",
        "ExecutionPolicy", "ExposureNotification", "ExtensionFoundation", "ExtensionKit",
        "ExternalAccessory",
        // F
        "FamilyControls", "FileProvider", "FileProviderUI", "FinanceKit", "FinanceKitUI",
        "FinderSync", "FindMyDevice", "ForceFeedback", "Foundation", "FoundationModels",
        "FSKit",
        // G
        "GameController", "GameKit", "GameplayKit", "GameSave", "GLKit", "GroupActivities", "GSS",
        // H
        "HealthKit", "HealthKitUI", "HomeKit", "Hypervisor",
        // I
        "iAd", "ImageIO", "ImagePlayground", "ImageCaptureCore", "InputMethodKit",
        "Intents", "IntentsUI", "IOBluetooth", "IOBluetoothUI", "IOKit", "IOSurface",
        "IOUSBHost", "iTunesLibrary",
        // J
        "JavaScriptCore", "JournalingSuggestions",
        // K
        "Kernel",
        // L
        "LatentSemanticMapping", "LinkPresentation", "LiveCommunicationKit",
        "LocalAuthentication", "LocalAuthenticationEmbeddedUI", "LockedCameraCapture",
        // M
        "MailKit", "ManagedApp", "ManagedAppDistribution", "ManagedSettings", "ManagedSettingsUI",
        "MapKit", "Matter", "MatterSupport", "MediaAccessibility", "MediaExtension",
        "MediaLibrary", "MediaPlayer", "MediaSetup", "MediaToolbox", "MessageUI", "Messages",
        "Metal", "MetalFX", "MetalKit", "MetalPerformanceShaders", "MetalPerformanceShadersGraph",
        "MetricKit", "MLCompute", "ModelIO", "MultipeerConnectivity", "MusicKit",
        // N
        "NaturalLanguage", "NearbyInteraction", "Network", "NetworkExtension",
        "NotificationCenter",
        // O
        "ObjectiveCRuntime", "Observation", "OpenDirectory", "OpenGLES", "os", "OSLog",
        // P
        "PackageDescription", "PaperKit", "ParavirtualizedGraphics", "PassKit", "PDFKit",
        "PencilKit", "PHASE", "Photos", "PhotosUI",
        "PlaygroundBluetooth", "PlaygroundSupport", "PreferencePanes",
        "ProximityReader", "PushKit", "PushToTalk",
        // Q
        "Quartz", "QuartzCore", "QuickLook", "QuickLookThumbnailing", "QuickLookUI",
        // R
        "RealityKit", "RegexBuilder", "ReplayKit", "ResearchKit", "RoomPlan",
        // S
        "SafariServices", "SafetyKit", "SceneKit", "ScreenCaptureKit", "ScreenSaver",
        "ScreenTime", "ScriptingBridge", "Security", "SecurityFoundation", "SecurityInterface",
        "SensorKit", "SensitiveContentAnalysis", "ServiceManagement", "ShazamKit",
        "SharedWithYou", "simd", "SiriKit", "Social", "SoundAnalysis", "Spatial", "Speech",
        "SpriteKit", "StoreKit", "StoreKitTest",
        "Swift", "SwiftData", "SwiftUI", "SwiftTesting", "Symbols", "Synchronization",
        "System", "SystemConfiguration", "SystemExtensions",
        // T
        "TabletopKit", "TabularData", "ThreadNetwork", "TipKit", "Translation",
        "TVMLKit", "TVServices", "TVUIKit",
        // U
        "UIKit", "UniformTypeIdentifiers", "UserNotifications", "UserNotificationsUI",
        // V
        "VideoSubscriberAccount", "VideoToolbox", "Virtualization", "Vision", "VisionKit",
        // W
        "WalletOrders", "WalletPasses", "WatchConnectivity", "WatchKit", "WeatherKit",
        "WebKit", "WidgetKit", "WorkoutKit",
        // X
        "XCTest", "XPC",
        // Misc/lowercase
        "zlib", "sqlite3", "notify", "ObjectiveC", "Cocoa", "Glibc", "ucrt",
        "MobileCoreServices",
        // Submodule imports
        "os.signpost", "os.OSAllocatedUnfairLock",
        "CoreImage.CIFilterBuiltins", "UIKit.UIGestureRecognizerSubclass",
        "Accelerate.vImage"
    ]

    /// Known Apple private frameworks (from iOS-Private-Frameworks repo).
    /// We match by exact name; this is a representative set of commonly encountered ones.
    private let privateFrameworks: Set<String> = [
        "ACTFramework", "AMPCoreUI", "AOPHaptics", "AOSKit", "APTransport",
        "AccessibilityPlatformTranslation", "AccessibilitySharedSupport", "AccessibilityUtilities",
        "AccountNotification", "AccountSettings", "AccountsDaemon", "AccountsUI",
        "ActionPredictionHeuristics", "ActivityAchievements", "ActivitySharing",
        "AdAnalytics", "AdCore", "AdID", "AdPlatforms", "AdPlatformsInternal",
        "AirPlayReceiver", "AirPlaySender", "AirPlaySupport", "AirTraffic",
        "AnnotationKit", "AppConduit", "AppLaunchStats", "AppPredictionClient",
        "AppPredictionInternal", "AppStoreDaemon", "AppStoreUI",
        "AssertionServices", "AssetCacheServices", "BackBoardServices",
        "BaseBoard", "BiometricKit", "BluetoothManager", "BulletinBoard",
        "CacheDelete", "CalendarUIKit", "CameraKit", "CelestialUI",
        "ChatKit", "ChronoKit", "CloudDocs", "CloudPhotoLibrary",
        "CommonUtilities", "CommunicationsFilter", "ContentKit",
        "ControlCenterUI", "ControlCenterUIKit", "CoreBrightness", "CoreCDP",
        "CoreDuet", "CoreFollowUp", "CoreHandwriting", "CoreMediaStream",
        "CorePDF", "CorePhoneNumbers", "CorePrediction", "CoreRecents",
        "CoreSDB", "CoreSpeech", "CoreSuggestions", "CoreSymbolication",
        "CoverSheet", "DataDetectorsCore", "DeviceIdentity",
        "DiagnosticExtensions", "DiagnosticLogCollection",
        "DuetActivityScheduler", "DuetExpertCenter",
        "FMClient", "FMCore", "FMCoreLite", "FMF", "FMFSupport",
        "FMIPClient", "FTServices", "FrontBoard", "FrontBoardServices",
        "GeoServices", "GraphicsServices",
        "HMFoundation", "HomeSharing",
        "IMCore", "IMDPersistence", "IMFoundation", "IMSharedUtilities",
        "IMAVCore", "IDSFoundation",
        "MailServices", "ManagedConfiguration", "MapsSupport",
        "MediaRemote", "MediaServices", "MobileBackup", "MobileBluetooth",
        "MobileCoreServices", "MobileIcons", "MobileInstallation",
        "MobileKeyBag", "MobileTimer", "MobileWiFi",
        "NanoPreferencesSync", "NanoRegistry", "NavigationKit",
        "NewsCore", "NotesShared", "NotesUI",
        "OfficeImport", "PBBridgeSupport", "Pegasus", "PersistentConnection",
        "PhotoFoundation", "PhotoLibrary", "PhotosGraph", "PhotosPlayer",
        "PowerLog", "Preferences", "PreferencesUI",
        "ProactiveSupport", "ProtectedCloudStorage", "PrototypeTools",
        "RemoteManagement", "RemoteUI",
        "ScreenReading", "SearchFoundation", "Sharing",
        "SlideshowKit", "SoftwareUpdateServices", "SpringBoardFoundation",
        "SpringBoardServices", "SpringBoardUI", "SpringBoardUIServices",
        "StoreServices", "Symbolication",
        "TCC", "TelephonyUI", "TextInput", "TextInputUI",
        "TouchRemote", "TrustedPeers",
        "UIAccessibility", "UIFoundation", "UIKitCore", "UIKitServices",
        "UsageTracking", "VoiceServices", "VoiceTrigger",
        "WeatherFoundation", "WebBookmarks", "WebCore",
        "WiFiKit", "WorkflowKit"
    ]

    /// Max declarations to show in one package graph (performance + readability)
    private let maxGraphDeclarations = 80

    func generate(
        graph: DependencyGraph,
        outputPath: String,
        parsedFiles: [ParsedFile],
        branchName: String,
        authorStats: [String: AuthorStats],
        projectName: String = "",
        metadata: ProjectMetadata = ProjectMetadata()
    ) throws {
        let hotspots = graph.getTopHotspots(limit: 15)
        let fileMap = Dictionary(uniqueKeysWithValues: parsedFiles.map { ($0.filePath, $0) })
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        print("   Generating HTML sections...")

        // ─── 1. Team ───
        let topTeam = authorStats.sorted { $0.value.filesModified > $1.value.filesModified }.prefix(15)
        let teamRows = topTeam.map { (author, info) -> String in
            let first = info.firstCommitDate > 0 ? dateFmt.string(from: Date(timeIntervalSince1970: info.firstCommitDate)) : "—"
            let last = info.lastCommitDate > 0 ? dateFmt.string(from: Date(timeIntervalSince1970: info.lastCommitDate)) : "—"
            return "<tr><td>\(esc(author))</td><td>\(info.filesModified)</td><td>\(info.totalCommits)</td><td>\(first)</td><td>\(last)</td></tr>"
        }.joined(separator: "\n")

        // ─── 2. Imports ───
        let allImports = Set(parsedFiles.flatMap(\.imports))
        let localPackageNames = Set(parsedFiles.compactMap { $0.packageName.isEmpty ? nil : $0.packageName })
        let localModuleNames = Set(parsedFiles.filter { !$0.packageName.isEmpty }.map(\.moduleName)).union(localPackageNames)
        var classifiedImports: [ImportKind: Set<String>] = [.apple: [], .external: [], .local: []]
        var detectedPrivateFrameworks: Set<String> = []
        for imp in allImports {
            let baseName = imp.components(separatedBy: ".").first ?? imp
            if appleFrameworks.contains(imp) || appleFrameworks.contains(baseName) {
                classifiedImports[.apple, default: []].insert(imp)
            } else if localModuleNames.contains(imp) || localPackageNames.contains(imp) {
                classifiedImports[.local, default: []].insert(imp)
            } else {
                // Check if it's a known private framework
                if privateFrameworks.contains(baseName) {
                    detectedPrivateFrameworks.insert(imp)
                }
                classifiedImports[.external, default: []].insert(imp)
            }
        }
        // Collect build system per package for display
        var packageBuildSystem: [String: BuildSystem] = [:]
        for file in parsedFiles where !file.packageName.isEmpty {
            if packageBuildSystem[file.packageName] == nil || file.buildSystem != .unknown {
                packageBuildSystem[file.packageName] = file.buildSystem
            }
        }

        // Metal files per package (needed in importsHTML closure)
        let metalPackages = Set(metadata.metalFiles.compactMap { $0.packageName.isEmpty ? nil : $0.packageName })

        let importsHTML: String = {
            var sections: [String] = []

            // Compute package line/decl percentages for highlighting
            let totalLinesAll = parsedFiles.reduce(0) { $0 + $1.lineCount }
            var pkgLines: [String: Int] = [:]
            var pkgDecls: [String: Int] = [:]
            for file in parsedFiles {
                let key = file.packageName.isEmpty ? "App" : file.packageName
                pkgLines[key, default: 0] += file.lineCount
                pkgDecls[key, default: 0] += file.declarations.filter { $0.kind != .extension }.count
            }
            let lineThreshold = Double(totalLinesAll) * 0.015

            // 1. Local Packages — column grid with clickable links to package sections
            if let localNames = classifiedImports[.local], !localNames.isEmpty {
                let allNames = localNames.sorted()
                let hasApp = pkgLines["App", default: 0] > 0

                var tags: [String] = []

                if hasApp {
                    let appLines = pkgLines["App", default: 0]
                    let appTag = "<a href='#pkg-App' class='tag tag-local pkg-link pkg-major'><span class='pkg-name'>📱 App</span><span class='bs-badge-right'>\(appLines.formatted()) loc</span></a>"
                    tags.append(appTag)
                }

                for name in allNames {
                    let bs = packageBuildSystem[name]
                    let bsLabel = bs != nil && bs != .unknown ? "<span class='bs-badge-right'>\(bs!.rawValue)</span>" : ""
                    let anchor = name.replacingOccurrences(of: " ", with: "-")
                    let lines = pkgLines[name, default: 0]
                    let decls = pkgDecls[name, default: 0]
                    let isMajor = Double(lines) >= lineThreshold && lines >= 10_000 && decls >= 80
                    let metalIcon = metalPackages.contains(name) ? "🔘 " : ""
                    let majorClass = isMajor ? " pkg-major" : ""
                    tags.append("<a href='#pkg-\(anchor)' class='tag tag-local pkg-link\(majorClass)'><span class='pkg-name'>\(metalIcon)\(name)</span>\(bsLabel)</a>")
                }

                let totalWithApp = localNames.count + (hasApp ? 1 : 0)
                sections.append("<div class='import-group'><h3>🏠 Local Packages <span class='count'>(\(totalWithApp))</span></h3><div class='pkg-grid'>\(tags.joined(separator: "\n"))</div></div>")
            }

            // 2. External Dependencies
            if let extNames = classifiedImports[.external], !extNames.isEmpty {
                let tags = extNames.sorted().map { "<span class='tag tag-external'>\($0)</span>" }.joined(separator: " ")
                sections.append("<div class='import-group'><h3>📦 External Dependencies <span class='count'>(\(extNames.count))</span></h3><div class='tag-cloud'>\(tags)</div></div>")
            }

            // 3. Apple Frameworks
            if let appleNames = classifiedImports[.apple], !appleNames.isEmpty {
                let tags = appleNames.sorted().map { "<span class='tag tag-apple'>\($0)</span>" }.joined(separator: " ")
                sections.append("<div class='import-group'><h3>🍎 Apple Frameworks <span class='count'>(\(appleNames.count))</span></h3><div class='tag-cloud'>\(tags)</div></div>")
            }

            // 4. Private Frameworks
            if !detectedPrivateFrameworks.isEmpty {
                let tags = detectedPrivateFrameworks.sorted().map { "<span class='tag tag-private'>\($0)</span>" }.joined(separator: " ")
                sections.append("<div class='import-group'><h3>🔒 Possible Private Frameworks Usage <span class='count'>(\(detectedPrivateFrameworks.count))</span></h3><p class='private-warn'>These imports match known Apple private frameworks. Using private APIs may cause App Store rejection.</p><div class='tag-cloud'>\(tags)</div></div>")
            }

            return sections.joined(separator: "\n")
        }()

        // ─── 3. Packages ───
        let appTargetName = "App"
        var packageFiles: [String: [ParsedFile]] = [:]
        for file in parsedFiles {
            let key = file.packageName.isEmpty ? appTargetName : file.packageName
            packageFiles[key, default: []].append(file)
        }
        let packages = packageFiles.map { PackageSummary(name: $0.key, files: $0.value) }
            .sorted { $0.totalLines > $1.totalLines }

        print("   Building \(packages.count) package sections...")

        var packageSections = ""
        var graphCounter = 0
        var packageGraphScripts = ""

        for (pkgIdx, pkg) in packages.enumerated() {
            if (pkgIdx + 1) % 20 == 0 {
                print("   Package \(pkgIdx + 1)/\(packages.count)...")
            }

            let sortedFiles = pkg.files.sorted { $0.lineCount > $1.lineCount }
            let isApp = pkg.name == appTargetName
            let icon = isApp ? "📱" : "📦"
            let bsTag: String = {
                guard !isApp else { return "" }
                let bs = pkg.files.first(where: { $0.buildSystem != .unknown })?.buildSystem
                guard let bs = bs else { return "" }
                return " <span class='bs-badge'>\(bs.rawValue)</span>"
            }()

            let fileRows = sortedFiles.map { file -> String in
                let decls = file.declarations.filter { $0.kind != .extension }
                let exts = file.declarations.filter { $0.kind == .extension }
                var parts: [String] = decls.map { "\(kindIcon($0.kind))&thinsp;\(esc($0.name))" }
                parts += exts.map { "🔹&thinsp;\(esc($0.name))" }
                let declStr = parts.isEmpty ? "—" : parts.joined(separator: "&ensp;")
                let desc = file.description.isEmpty ? "" : "<div class='file-desc'>💡 \(esc(String(file.description.prefix(120))))</div>"
                return "<tr><td><strong>\(esc(file.fileName))</strong>\(desc)</td><td class='mono'>\(file.lineCount)</td><td>\(decls.count)</td><td class='decl-tags'>\(declStr)</td></tr>"
            }.joined(separator: "\n")

            // Declaration graph
            let graphId = "pkg-graph-\(graphCounter)"
            graphCounter += 1
            let declGraphData = buildDeclarationGraph(for: pkg, pageRankScores: graph.pageRankScores)
            let pkgGraphJSON = (try? String(data: JSONEncoder().encode(declGraphData), encoding: .utf8)) ?? "{\"nodes\":[],\"links\":[]}"
            let showGraph = declGraphData.nodes.count >= 2

            var statsParts: [String] = []
            if pkg.structCount > 0 { statsParts.append("🟢 \(pkg.structCount) structs") }
            if pkg.classCount > 0 { statsParts.append("🔵 \(pkg.classCount) classes") }
            if pkg.enumCount > 0 { statsParts.append("🟡 \(pkg.enumCount) enums") }
            if pkg.protocolCount > 0 { statsParts.append("🟣 \(pkg.protocolCount) protocols") }
            if pkg.actorCount > 0 { statsParts.append("🔴 \(pkg.actorCount) actors") }
            if pkg.extensionCount > 0 { statsParts.append("🔹 \(pkg.extensionCount) extensions") }

            let pkgAnchor = pkg.name.replacingOccurrences(of: " ", with: "-")

            packageSections += """
            <div class="package-section" id="pkg-\(pkgAnchor)">
                <h3>\(icon) \(esc(pkg.name))\(bsTag)
                    <span class="pkg-stats">\(sortedFiles.count) files · \(pkg.totalLines.formatted()) lines · \(pkg.realDeclarations.count) declarations</span>
                </h3>
                <p class="stats-detail">\(statsParts.joined(separator: " · "))</p>
                \(showGraph ? "<div id='\(graphId)' class='pkg-graph-container'></div>" : "")
                <table class="file-table">
                    <thead><tr><th>File</th><th>Lines</th><th>Decl</th><th>Declarations</th></tr></thead>
                    <tbody>\(fileRows)</tbody>
                </table>
            </div>
            """

            if showGraph {
                packageGraphScripts += """
                {
                    const d = \(pkgGraphJSON);
                    const el = document.getElementById('\(graphId)');
                    if (d.nodes.length > 0 && el) {
                        const kc = {'class':'#007aff','struct':'#34c759','enum':'#ff9500','actor':'#ff3b30'};
                        const g = ForceGraph()(el)
                            .graphData(d)
                            .nodeLabel(n => n.label + ' (' + n.sublabel + ')\\n' + n.kind)
                            .nodeVal(n => Math.max(n.score * 3000, 5))
                            .nodeColor(n => kc[n.kind] || '#999')
                            .nodeCanvasObject((node, ctx, gs) => {
                                const r = Math.max(Math.sqrt(Math.max(node.score * 3000, 5)) * 0.8, 3);
                                ctx.beginPath();
                                ctx.arc(node.x, node.y, r, 0, 2 * Math.PI);
                                ctx.fillStyle = kc[node.kind] || '#999';
                                ctx.fill();
                                if (gs > 0.5) {
                                    ctx.font = `${Math.max(10/gs, 3)}px -apple-system, sans-serif`;
                                    ctx.textAlign = 'center';
                                    ctx.fillStyle = '#333';
                                    ctx.fillText(node.label, node.x, node.y + r + 10/gs);
                                }
                            })
                            .linkDirectionalArrowLength(8)
                            .linkDirectionalArrowRelPos(1)
                            .linkColor(() => 'rgba(0,0,0,0.12)')
                            .width(el.offsetWidth)
                            .height(420);
                        g.d3Force('charge').strength(-250);
                        g.d3Force('link').distance(80);
                    }
                }

                """
            }
        }

        // ─── 4. Hotspots ───
        let hotspotRows = hotspots.map { item -> String in
            let file = fileMap[item.path]
            let fileName = URL(fileURLWithPath: item.path).lastPathComponent
            let pkg = file?.packageName.isEmpty == false ? file!.packageName : "App"
            let pkgAnchor = pkg.replacingOccurrences(of: " ", with: "-")
            let desc = file?.description ?? ""
            let descHtml = desc.isEmpty ? "" : "<span class='description'>💡 \(esc(String(desc.prefix(100))))</span>"
            return "<li class='hotspot-item'><div><span>\(esc(fileName))</span> <a href='#pkg-\(pkgAnchor)' class='tag tag-local pkg-link-inline'>\(esc(pkg))</a>\(descHtml)</div><span class='hotspot-score'>\(String(format: "%.4f", item.score))</span></li>"
        }.joined(separator: "\n")

        // ─── 5. Summary ───
        let totalLines = parsedFiles.reduce(0) { $0 + $1.lineCount }
        let allDecls = parsedFiles.flatMap(\.declarations)
        let totalDecls = allDecls.filter { $0.kind != .extension }.count
        let totalExts = allDecls.filter { $0.kind == .extension }.count
        let totalStructs = allDecls.filter { $0.kind == .struct }.count
        let totalClasses = allDecls.filter { $0.kind == .class }.count
        let totalEnums = allDecls.filter { $0.kind == .enum }.count
        let totalProtocols = allDecls.filter { $0.kind == .protocol }.count
        let totalActors = allDecls.filter { $0.kind == .actor }.count

        // TODO/FIXME
        let totalTodos = parsedFiles.reduce(0) { $0 + $1.todoCount }
        let totalFixmes = parsedFiles.reduce(0) { $0 + $1.fixmeCount }

        // Module TODO/FIXME stats
        var moduleTodos: [String: Int] = [:]
        var moduleFixmes: [String: Int] = [:]
        for file in parsedFiles {
            let key = file.packageName.isEmpty ? "App" : file.packageName
            moduleTodos[key, default: 0] += file.todoCount
            moduleFixmes[key, default: 0] += file.fixmeCount
        }
        let topTodoModules = moduleTodos
            .filter { $0.value + (moduleFixmes[$0.key] ?? 0) > 0 }
            .sorted { $0.value + (moduleFixmes[$0.key] ?? 0) > $1.value + (moduleFixmes[$1.key] ?? 0) }
            .prefix(50)

        // Longest functions across all files
        let allFunctions = parsedFiles.compactMap(\.longestFunction)
        let topLongestFuncs = allFunctions.sorted { $0.lineCount > $1.lineCount }.prefix(20)

        print("   Writing HTML...")

        // ─── HTML ───
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📊</text></svg>">
            <title>📊 SwiftCodeContext — \(esc(projectName))</title>
            <style>
                :root { --bg: #f5f5f7; --card: #fff; --border: #e5e5ea; --text: #1d1d1f; --text2: #424245; --text3: #86868b; --accent: #0071e3; --red: #ff3b30; }
                * { box-sizing: border-box; }
                body { font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', sans-serif; margin: 0; padding: 20px; background: var(--bg); color: var(--text); line-height: 1.5; }
                .container { max-width: 1280px; margin: 0 auto; }
                .card { background: var(--card); padding: 28px; border-radius: 16px; box-shadow: 0 1px 12px rgba(0,0,0,0.06); margin-bottom: 20px; }
                h1 { font-size: 28px; font-weight: 700; margin: 0 0 4px 0; }
                h2 { color: var(--text2); font-size: 20px; border-bottom: 2px solid var(--border); padding-bottom: 10px; margin: 28px 0 16px 0; }
                h3 { color: var(--text2); font-size: 16px; margin: 20px 0 8px 0; }
                .subtitle { color: var(--text3); font-size: 14px; margin-bottom: 20px; }
                .branch-badge { display: inline-block; background: #e3f2fd; color: #1565c0; padding: 2px 10px; border-radius: 8px; font-size: 13px; font-weight: 500; font-family: 'SF Mono', Menlo, monospace; }
                .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 10px; margin-bottom: 24px; }
                .summary-card { background: var(--bg); border-radius: 12px; padding: 14px 8px; text-align: center; }
                .summary-card .num { font-size: 26px; font-weight: 700; color: var(--accent); }
                .summary-card .label { font-size: 11px; color: var(--text3); text-transform: uppercase; letter-spacing: 0.04em; margin-top: 2px; }
                .team-table, .file-table { width: 100%; border-collapse: collapse; font-size: 14px; }
                .team-table th, .file-table th { color: var(--text3); font-weight: 500; text-transform: uppercase; font-size: 11px; letter-spacing: 0.05em; text-align: left; padding: 8px 10px; border-bottom: 2px solid var(--border); }
                .team-table td, .file-table td { padding: 8px 10px; border-bottom: 1px solid var(--border); vertical-align: top; }
                .mono { font-family: 'SF Mono', Menlo, monospace; font-size: 13px; }
                .tag { display: inline-block; padding: 2px 8px; border-radius: 6px; font-size: 12px; font-weight: 500; margin: 2px; }
                .tag-apple { background: #e8f5e9; color: #2e7d32; }
                .tag-external { background: #fff3e0; color: #e65100; }
                .tag-local { background: #e3f2fd; color: #1565c0; }
                .tag-cloud { line-height: 2.2; }
                .pkg-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 4px 8px; }
                .pkg-link { display: flex; align-items: center; justify-content: space-between; text-decoration: none; cursor: pointer; transition: background 0.15s; }
                .pkg-link:hover { background: #bbdefb; }
                .pkg-major { border: 2px solid var(--accent); font-weight: 600; }
                .pkg-link-inline { text-decoration: none; cursor: pointer; }
                .pkg-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
                .bs-badge-right { background: rgba(0,0,0,0.07); color: var(--text3); font-size: 9px; padding: 1px 5px; border-radius: 4px; margin-left: auto; padding-left: 6px; flex-shrink: 0; font-weight: 400; letter-spacing: 0.02em; }
                .bs-badge { background: rgba(0,0,0,0.08); color: var(--text3); font-size: 10px; padding: 1px 5px; border-radius: 4px; margin-left: 2px; font-weight: 400; }
                .tag-private { background: #fce4ec; color: #c62828; }
                .private-warn { color: #c62828; font-size: 12px; margin: 4px 0 8px 0; }
                .count { font-weight: 400; color: var(--text3); }
                .import-group { margin-bottom: 16px; }
                .import-group h3 { margin-bottom: 8px; }
                .hotspot-list { list-style: none; padding: 0; margin: 0; }
                .hotspot-item { padding: 10px 0; border-bottom: 1px solid var(--border); display: flex; justify-content: space-between; align-items: flex-start; }
                .hotspot-score { font-weight: 600; color: var(--red); font-family: 'SF Mono', monospace; font-size: 13px; white-space: nowrap; }
                .description { color: var(--text3); font-style: italic; display: block; margin-top: 2px; font-size: 13px; }
                .package-section { margin-bottom: 32px; padding-bottom: 24px; border-bottom: 1px solid var(--border); }
                .package-section:last-child { border-bottom: none; }
                .pkg-stats { font-weight: 400; color: var(--text3); font-size: 13px; margin-left: 8px; }
                .stats-detail { color: var(--text3); font-size: 13px; margin: 4px 0 12px 0; }
                .file-desc { color: var(--text3); font-size: 12px; font-style: italic; margin-top: 2px; }
                .decl-tags { font-size: 12px; line-height: 1.8; }
                .pkg-graph-container { width: 100%; height: 420px; border: 1px solid var(--border); border-radius: 10px; margin-bottom: 16px; overflow: hidden; background: #fafafa; }
                @media (max-width: 768px) { body { padding: 10px; } .card { padding: 16px; } .summary-grid { grid-template-columns: repeat(2, 1fr); } }
            </style>
            <script src="https://unpkg.com/force-graph"></script>
        </head>
        <body>
        <div class="container">
            <div class="card">
                <h1>📊 SwiftCodeContext Report — \(esc(projectName.isEmpty ? "Project" : projectName))</h1>
                <p class="subtitle">Generated \(Date().formatted()) · <span class="branch-badge">\(esc(branchName))</span> branch</p>
                <div class="summary-grid">
                    \(!metadata.swiftVersion.isEmpty ? "<div class=\"summary-card\"><div class=\"num\" style=\"font-size:20px\">Swift \(esc(metadata.swiftVersion))</div><div class=\"label\">Language</div></div>" : "")
                    \(!metadata.deploymentTargets.isEmpty ? "<div class=\"summary-card\"><div class=\"num\" style=\"font-size:16px\">\(esc(metadata.deploymentTargets.joined(separator: ", ")))</div><div class=\"label\">Min Deployment</div></div>" : "")
                    \(!metadata.appVersion.isEmpty ? "<div class=\"summary-card\"><div class=\"num\" style=\"font-size:20px\">\(esc(metadata.appVersion))</div><div class=\"label\">App Version</div></div>" : "")
                    <div class="summary-card"><div class="num">\(parsedFiles.count)</div><div class="label">Swift Files</div></div>
                    \(metadata.metalFiles.count > 0 ? "<div class=\"summary-card\"><div class=\"num\">\(metadata.metalFiles.count)</div><div class=\"label\">🔘 Metal Files</div></div>" : "")
                    <div class="summary-card"><div class="num">\(totalLines.formatted())</div><div class="label">Lines of Code</div></div>
                    <div class="summary-card"><div class="num">\(totalDecls)</div><div class="label">Declarations</div></div>
                    <div class="summary-card"><div class="num">\(totalExts)</div><div class="label">Extensions</div></div>
                    <div class="summary-card"><div class="num">\(packages.count)</div><div class="label">Packages</div></div>
                    \(totalTodos + totalFixmes > 0 ? "<div class=\"summary-card\"><div class=\"num\">\(totalTodos + totalFixmes)</div><div class=\"label\">TODO/FIXME</div></div>" : "")
                    <div class="summary-card"><div class="num">\(totalStructs)</div><div class="label">🟢 Structs</div></div>
                    <div class="summary-card"><div class="num">\(totalLines.formatted())</div><div class="label">Lines of Code</div></div>
                    <div class="summary-card"><div class="num">\(totalDecls)</div><div class="label">Declarations</div></div>
                    <div class="summary-card"><div class="num">\(totalExts)</div><div class="label">Extensions</div></div>
                    <div class="summary-card"><div class="num">\(packages.count)</div><div class="label">Packages</div></div>
                    <div class="summary-card"><div class="num">\(totalStructs)</div><div class="label">🟢 Structs</div></div>
                    <div class="summary-card"><div class="num">\(totalClasses)</div><div class="label">🔵 Classes</div></div>
                    <div class="summary-card"><div class="num">\(totalEnums)</div><div class="label">🟡 Enums</div></div>
                    <div class="summary-card"><div class="num">\(totalProtocols)</div><div class="label">🟣 Protocols</div></div>
                    <div class="summary-card"><div class="num">\(totalActors)</div><div class="label">🔴 Actors</div></div>
                </div>
            </div>
            <div class="card">
                <h2>👥 Team Contribution Map</h2>
                <table class="team-table">
                    <thead><tr><th>Developer</th><th>Files Modified</th><th>Commits</th><th>First Change</th><th>Last Change</th></tr></thead>
                    <tbody>\(teamRows)</tbody>
                </table>
            </div>
            <div class="card">
                <h2>📚 Dependencies & Imports</h2>
                \(importsHTML)
            </div>
            <div class="card">
                <h2>🔥 Knowledge Hotspots</h2>
                <p class="subtitle">Files with highest <strong>PageRank</strong> score — the most connected and structurally impactful nodes in the dependency graph. High-scoring files are referenced by many other files and sit at critical junctions in the codebase architecture.</p>
                <ul class="hotspot-list">\(hotspotRows)</ul>
            </div>
            <div class="card">
                <h2>📋 Module Insights</h2>
                <p class="subtitle">Modules by TODO / FIXME comment density.</p>
                \(topTodoModules.isEmpty ? "<p style=\"color: var(--text3)\">No TODO or FIXME comments found across the codebase.</p>" : """
                <table class="file-table">
                    <thead><tr><th>Module</th><th>TODO</th><th>FIXME</th><th>Total</th></tr></thead>
                    <tbody>\(topTodoModules.map { (name, todos) -> String in
                        let fixmes = moduleFixmes[name] ?? 0
                        let anchor = name.replacingOccurrences(of: " ", with: "-")
                        return "<tr><td><a href='#pkg-\(anchor)' class='pkg-link-inline'>\(esc(name))</a></td><td>\(todos)</td><td>\(fixmes)</td><td><strong>\(todos + fixmes)</strong></td></tr>"
                    }.joined(separator: "\n"))</tbody>
                </table>
                """)
            </div>
            \(!topLongestFuncs.isEmpty ? """
            <div class="card">
                <h2>📏 Longest Functions</h2>
                <table class="file-table">
                    <thead><tr><th>Function</th><th>Lines</th><th>File</th><th>Module</th></tr></thead>
                    <tbody>\(topLongestFuncs.map { fn -> String in
                        let fileName = URL(fileURLWithPath: fn.filePath).lastPathComponent
                        let pkg = fileMap[fn.filePath]?.packageName.isEmpty == false ? fileMap[fn.filePath]!.packageName : "App"
                        let anchor = pkg.replacingOccurrences(of: " ", with: "-")
                        return "<tr><td><code>\(esc(fn.name))()</code></td><td class='mono'>\(fn.lineCount)</td><td>\(esc(fileName))</td><td><a href='#pkg-\(anchor)' class='pkg-link-inline'>\(esc(pkg))</a></td></tr>"
                    }.joined(separator: "\n"))</tbody>
                </table>
            </div>
            """ : "")
            <div class="card">
                <h2>📦 Packages & Modules</h2>
                <p class="subtitle">Graphs: type references between declarations. <span style="color:#007aff">●</span> class <span style="color:#34c759">●</span> struct <span style="color:#ff9500">●</span> enum <span style="color:#ff3b30">●</span> actor. Arrows from class/actor only.</p>
                \(packageSections)
            </div>
            <footer style="text-align:center; padding: 20px 0 10px; color: var(--text3); font-size: 12px;">
                Generator: <a href="https://github.com/Exey/SwiftCodeContext" style="color: var(--accent); text-decoration: none;">SwiftCodeContext</a> · MIT License · Exey Panteleev
            </footer>
        </div>
        <script>
        \(packageGraphScripts)
        </script>
        </body>
        </html>
        """

        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try html.write(to: outputURL, atomically: true, encoding: .utf8)
        print("   HTML written (\((html.utf8.count / 1024))KB)")
    }

    // MARK: - Declaration-Level Graph Builder

    private func buildDeclarationGraph(for pkg: PackageSummary, pageRankScores: [String: Double]) -> GraphData {
        let eligibleFiles = pkg.files.filter {
            !$0.filePath.contains("/Tests/") && !$0.filePath.contains("/Test/") &&
            $0.fileName != "Package.swift" && $0.fileName != "Project.swift"
        }

        struct DeclInfo {
            let name: String; let kind: Declaration.Kind; let filePath: String; let fileName: String
        }

        let graphKinds: Set<Declaration.Kind> = [.class, .struct, .enum, .actor]
        var allDecls: [DeclInfo] = []

        for file in eligibleFiles {
            for decl in file.declarations where graphKinds.contains(decl.kind) && decl.name.count >= 4 {
                allDecls.append(DeclInfo(name: decl.name, kind: decl.kind, filePath: file.filePath, fileName: file.fileName))
            }
        }

        // Cap: for large modules, keep top declarations by file PageRank
        if allDecls.count > maxGraphDeclarations {
            allDecls.sort { (pageRankScores[$0.filePath] ?? 0) > (pageRankScores[$1.filePath] ?? 0) }
            allDecls = Array(allDecls.prefix(maxGraphDeclarations))
        }

        let nodes: [GraphNode] = allDecls.map { d in
            GraphNode(id: "\(d.filePath)::\(d.name)", label: d.name, sublabel: d.fileName,
                      kind: d.kind.rawValue, score: pageRankScores[d.filePath] ?? 0.001, group: pkg.name)
        }

        // Build edges — only class/actor emit outgoing
        let outgoingKinds: Set<Declaration.Kind> = [.class, .actor]
        var links: [GraphLink] = []
        var seenEdges: Set<String> = []

        // Read file contents for source declarations only
        let outgoingDecls = allDecls.filter { outgoingKinds.contains($0.kind) }
        let uniqueFilePaths = Set(outgoingDecls.map(\.filePath))
        var contentCache: [String: String] = [:]
        for path in uniqueFilePaths {
            contentCache[path] = try? String(contentsOfFile: path, encoding: .utf8)
        }

        for source in outgoingDecls {
            guard let content = contentCache[source.filePath] else { continue }
            for target in allDecls where target.name != source.name {
                let ek = "\(source.name)->\(target.name)"
                guard !seenEdges.contains(ek) else { continue }
                if fastContainsType(content, typeName: target.name) {
                    links.append(GraphLink(source: "\(source.filePath)::\(source.name)", target: "\(target.filePath)::\(target.name)"))
                    seenEdges.insert(ek)
                }
            }
        }

        return GraphData(nodes: nodes, links: links)
    }

    private func fastContainsType(_ content: String, typeName: String) -> Bool {
        guard content.contains(typeName) else { return false }
        var searchRange = content.startIndex..<content.endIndex
        while let range = content.range(of: typeName, range: searchRange) {
            let before = range.lowerBound > content.startIndex ? content[content.index(before: range.lowerBound)] : Character(" ")
            let after = range.upperBound < content.endIndex ? content[range.upperBound] : Character(" ")
            if !before.isWordChar && !after.isWordChar { return true }
            searchRange = range.upperBound..<content.endIndex
        }
        return false
    }

    private func kindIcon(_ kind: Declaration.Kind) -> String {
        switch kind { case .class: return "🔵"; case .struct: return "🟢"; case .enum: return "🟡"; case .protocol: return "🟣"; case .actor: return "🔴"; case .extension: return "🔹" }
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private extension Character {
    var isWordChar: Bool { isLetter || isNumber || self == "_" }
}
