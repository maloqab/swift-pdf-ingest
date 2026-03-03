import Foundation

struct RuntimeConfig {
    let inboxDir: URL
    let seenFile: URL
    let stateFile: URL
    let dbPath: URL
    let sourceManifestPath: URL?
    let embeddingDimension: Int
    let embeddingModelVersion: String
    let maxDocumentsPerRun: Int
    let timeoutSeconds: Int?
    let enableOCRFallback: Bool
    let languages: [String]

    static func parse(arguments: [String]) throws -> RuntimeConfig {
        var inboxDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("runtime/inbox")
        var seenFile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("runtime/state/worker-seen-pdfs.txt")
        var stateFile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("runtime/state/swift_ingest_state.json")
        var dbPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("runtime/data/pipeline.sqlite")
        var sourceManifestPath: URL?
        var embeddingDimension = 16
        var embeddingModelVersion = "deterministic-hash-v1"
        var maxDocumentsPerRun = 25
        var timeoutSeconds: Int?
        var enableOCRFallback = true
        var languages: [String] = ["en"]

        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--inbox":
                index += 1
                guard index < arguments.count else { throw CLIError("missing value for --inbox") }
                inboxDir = URL(fileURLWithPath: arguments[index])
            case "--seen-file":
                index += 1
                guard index < arguments.count else { throw CLIError("missing value for --seen-file") }
                seenFile = URL(fileURLWithPath: arguments[index])
            case "--state-file":
                index += 1
                guard index < arguments.count else { throw CLIError("missing value for --state-file") }
                stateFile = URL(fileURLWithPath: arguments[index])
            case "--db-path":
                index += 1
                guard index < arguments.count else { throw CLIError("missing value for --db-path") }
                dbPath = URL(fileURLWithPath: arguments[index])
            case "--source-manifest":
                index += 1
                guard index < arguments.count else { throw CLIError("missing value for --source-manifest") }
                sourceManifestPath = URL(fileURLWithPath: arguments[index])
            case "--embedding-dim":
                index += 1
                guard index < arguments.count else { throw CLIError("missing value for --embedding-dim") }
                guard let value = Int(arguments[index]), value > 0 else {
                    throw CLIError("--embedding-dim must be a positive integer")
                }
                embeddingDimension = value
            case "--embedding-model-version":
                index += 1
                guard index < arguments.count else { throw CLIError("missing value for --embedding-model-version") }
                embeddingModelVersion = arguments[index]
            case "--max-docs":
                index += 1
                guard index < arguments.count else { throw CLIError("missing value for --max-docs") }
                guard let value = Int(arguments[index]), value > 0 else {
                    throw CLIError("--max-docs must be a positive integer")
                }
                maxDocumentsPerRun = value
            case "--timeout-seconds":
                index += 1
                guard index < arguments.count else { throw CLIError("missing value for --timeout-seconds") }
                guard let value = Int(arguments[index]), value > 0 else {
                    throw CLIError("--timeout-seconds must be a positive integer")
                }
                timeoutSeconds = value
            case "--ocr-fallback":
                index += 1
                guard index < arguments.count else { throw CLIError("missing value for --ocr-fallback") }
                let value = arguments[index].lowercased()
                switch value {
                case "on", "true", "1":
                    enableOCRFallback = true
                case "off", "false", "0":
                    enableOCRFallback = false
                default:
                    throw CLIError("--ocr-fallback must be one of: on|off")
                }
            case "--languages":
                index += 1
                guard index < arguments.count else { throw CLIError("missing value for --languages") }
                languages = arguments[index].split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            case "--help", "-h":
                printHelp()
                Foundation.exit(0)
            default:
                throw CLIError("unknown argument: \(arg)")
            }
            index += 1
        }

        return RuntimeConfig(
            inboxDir: inboxDir,
            seenFile: seenFile,
            stateFile: stateFile,
            dbPath: dbPath,
            sourceManifestPath: sourceManifestPath,
            embeddingDimension: embeddingDimension,
            embeddingModelVersion: embeddingModelVersion,
            maxDocumentsPerRun: maxDocumentsPerRun,
            timeoutSeconds: timeoutSeconds,
            enableOCRFallback: enableOCRFallback,
            languages: languages
        )
    }

    private static func printHelp() {
        print(
            """
            Usage: SwiftIngestRuntime [options]
              --inbox <path>                     Runtime inbox directory (default: runtime/inbox)
              --seen-file <path>                 File tracking processed signatures (default: runtime/state/worker-seen-pdfs.txt)
              --state-file <path>                JSON state output path (default: runtime/state/swift_ingest_state.json)
              --db-path <path>                   SQLite target database path (default: runtime/data/pipeline.sqlite)
              --source-manifest <path>           JSON map: filename -> {source_url, source_label, document_title}
              --embedding-dim <n>                Embedding vector dimension (default: 16)
              --embedding-model-version <name>   Embedding model version label (default: deterministic-hash-v1)
              --max-docs <n>                     Max PDFs to process per invocation (default: 25)
              --timeout-seconds <n>              Optional processing deadline in seconds
              --ocr-fallback <on|off>            Enable Vision OCR fallback when text layer is weak (default: on)
              --languages <list>                 Comma-separated OCR language list (default: en)
            """
        )
    }
}

struct CLIError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

struct SourceManifestEntry: Codable {
    let sourceURL: String?
    let sourceLabel: String?
    let documentTitle: String?

    enum CodingKeys: String, CodingKey {
        case sourceURL = "source_url"
        case sourceLabel = "source_label"
        case documentTitle = "document_title"
    }
}

enum RuntimeExitCode: Int32 {
    case success = 0
    case invalidArguments = 2
    case runtimeFailure = 3
}
