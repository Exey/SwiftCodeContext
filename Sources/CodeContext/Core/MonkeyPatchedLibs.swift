// Exey Panteleev
import Foundation

// MARK: - Monkey-Patched Libraries Detection

/// Detects vendored/monkey-patched C/C++/ObjC third-party libraries embedded in the project.
enum MonkeyPatchedLibs {

    /// Known library directory names (lowercase for matching).
    static let knownLibs: Set<String> = [
        // ─── C/C++ Libraries ───
        // Media / Codecs
        "ffmpeg", "libavcodec", "libavformat", "libavutil", "libswscale", "libswresample", "libavfilter",
        "opus", "libopus", "ogg", "libogg", "vorbis", "libvorbis", "speex", "libspeex",
        "lame", "libmp3lame", "webrtc", "libwebrtc",
        "libvpx", "vpx", "x264", "x265", "openh264", "dav1d", "aom", "libaom",
        "libtheora", "flac", "libflac",
        // Graphics / Rendering
        "thorvg", "rlottie", "lottie-c",
        "skia", "cairo", "harfbuzz", "freetype", "libpng", "libjpeg", "libjpeg-turbo",
        "libwebp", "libtiff", "giflib", "libgif",
        "metal-cpp", "stb", "stb_image", "nanovg", "imgui",
        "mozjpeg", "libavif", "libheif", "libjxl",
        // Compression
        "zlib", "libz", "lz4", "lzo", "zstd", "libzstd", "brotli", "snappy", "lzma",
        "minizip", "libarchive", "bzip2",
        // Crypto / Security
        "openssl", "libressl", "boringssl",
        "libsodium", "sodium", "mbedtls", "wolfssl",
        "ed25519", "curve25519", "libsignal",
        // Networking
        "curl", "libcurl", "nghttp2", "libnghttp2",
        "libuv", "c-ares", "lwip", "libssh2",
        "grpc-core", "nanopb",
        "protobuf", "protobuf-c",
        "pjsip", "opal", "ortp",
        // JSON / Serialization
        "rapidjson", "cjson", "yyjson",
        "simdjson", "flatbuffers", "msgpack", "msgpack-c", "jansson",
        // Database
        "sqlite3", "sqlite", "sqlcipher", "libsqlite3",
        // Math / ML
        "eigen", "onnxruntime", "tflite", "tensorflow-lite",
        "opencv", "dlib", "libtorch",
        "whisper.cpp", "llama.cpp", "ggml",
        // Text / Unicode
        "icu", "libicu", "pcre", "pcre2", "oniguruma", "hunspell",
        // Storage
        "leveldb", "rocksdb", "lmdb", "realm-core",
        // Scripting / Embedding
        "lua", "luajit", "duktape", "quickjs", "hermes",
        "mruby", "wasm3", "wasmtime", "wasmer",
        // System / Platform
        "libevent", "libffi", "libunwind",
        "jemalloc", "tcmalloc", "mimalloc",
        "abseil-cpp", "abseil",
        "sentry-native", "breakpad", "crashpad",
        // Audio / Speech
        "portaudio", "openal-soft",
        "conversational_speech", "porcupine", "vosk",
        "soundtouch", "aubio",
        // XML / HTML
        "libxml2", "libxml", "expat", "libexpat",
        "gumbo", "gumbo-parser",
        // Image / PDF
        "poppler", "mupdf", "pdfium",
        "tesseract", "leptonica",
        // Misc C/C++
        "boost", "fmt", "spdlog",
        "capnproto", "thrift", "usrsctp",
        "libyuv", "libde265", "backward-cpp", "libbacktrace",
        "murmurhash", "murmurhash2", "murmurhash3", "xxhash", "cityhash", "farmhash", "spookyhash",
        "crc32c", "md5", "sha1", "sha256",
        "nlohmann", "nlohmann-json",
        "tgcalls", "td", "tdlib",
        "tonlib",

        // ─── iOS / Swift Libraries (commonly vendored / monkey-patched) ───
        // UI / Layout
        "asyncdisplaykit", "texture", "componentkit",
        "snapkit", "masonry", "purelayout", "cartography",
        "flexlayout", "pinlayout", "layoutkit",
        "iglistkit",
        // Networking
        "alamofire", "moya", "afnetworking",
        "starscream", "socketrocket", "grpc-swift",
        // Rx / Async
        "rxswift", "rxcocoa", "rxdatasources",
        "reactiveswift", "reactivecocoa",
        "combineext", "opencombine",
        "promisekit", "hydra",
        // Image Loading
        "sdwebimage", "kingfisher", "nuke", "haneke",
        "fllanimatedimage", "gifu",
        // Database / Storage
        "realm", "fmdb", "grdb", "corestore", "magicalrecord",
        "yydisk", "yycache", "mmkv",
        // JSON / Model
        "swiftyjson", "objectmapper", "mantle", "argo",
        "handyjson", "codextended",
        // UI Components
        "snapchatkit", "charts", "dscharts",
        "lottie-ios", "lottie-swift",
        "svprogresshud", "mbprogresshud", "jgprogresshud",
        "hero", "spring", "pop",
        "cocoalumberjack", "swiftybeaver",
        "tttrattributedlabel", "yytext",
        // Navigation / Routing
        "coordinatorkit", "deeplink",
        // Build Systems / Tooling (vendored)
        "tuist", "xcodeproj", "pathkit", "spectre",
        "swiftlint", "swiftformat",
        // Dependency Injection
        "swinject", "needle", "cleanse", "resolver",
        // Testing (vendored)
        "quick", "nimble", "ohhttpstubs",
        // Crypto
        "cryptoswift",
        // Logging / Analytics
        "firebase", "firebaseanalytics",
        "amplitude", "mixpanel",
        // Auth
        "appauth", "oauthswift",
        // Keyboard / Input
        "iqkeyboardmanager", "iqkeyboardmanagerswift",
        // Other popular iOS libs
        "reachability", "reachabilityswift",
        "devicekit", "keychain-swift", "keychainaccess",
        "swiftkeychainwrapper",
        "zipfoundation", "ssziparchive",
        "marquiskit",
        "r.swift", "swiftgen",
        "yyjson", "yymodel", "yykit", "yyimage", "yycategories",
    ]

    struct DetectedLib {
        let name: String       // directory name as found
        let path: String       // relative path from project root
        let fileCount: Int
        let lineCount: Int
    }

    /// Detect monkey-patched libraries by scanning directory names.
    static func detect(rootPath: String, excludePaths: Set<String>) -> [DetectedLib] {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL

        var detected: [String: (path: String, files: Int, lines: Int)] = [:]
        let cExts: Set<String> = ["c", "cc", "cpp", "cxx", "h", "hpp", "hxx", "m", "mm"]

        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        for case let url as URL in enumerator {
            guard let res = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  res.isDirectory == true else { continue }

            let name = url.lastPathComponent
            if excludePaths.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            let lowerName = name.lowercased()
            guard knownLibs.contains(lowerName), detected[lowerName] == nil else { continue }

            let relPath = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")

            // Count source files (fast: just stat, don't read content for speed)
            var fileCount = 0
            var lineCount = 0
            if let subEnum = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in subEnum {
                    let ext = fileURL.pathExtension.lowercased()
                    if cExts.contains(ext) || ext == "swift" {
                        fileCount += 1
                        // Estimate lines from file size (avg ~40 bytes/line for C/C++)
                        if let r = try? fileURL.resourceValues(forKeys: [.fileSizeKey]) {
                            lineCount += (r.fileSize ?? 0) / 40
                        }
                    }
                }
            }
            if fileCount >= 2 {
                detected[lowerName] = (path: relPath, files: fileCount, lines: lineCount)
            }

            enumerator.skipDescendants() // don't recurse into the lib
        }

        return detected.map { DetectedLib(name: $0.value.path.components(separatedBy: "/").last ?? $0.key, path: $0.value.path, fileCount: $0.value.files, lineCount: $0.value.lines) }
            .sorted { $0.lineCount > $1.lineCount }
    }
}
