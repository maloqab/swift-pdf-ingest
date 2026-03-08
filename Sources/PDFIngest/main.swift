import Foundation
import IngestRuntime

do {
    let config = try RuntimeConfig.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    let exitCode = PipelineRunner.run(config: config)
    exit(exitCode.rawValue)
} catch let error as CLIError {
    fputs("pdf-ingest error: \(error)\n", stderr)
    exit(RuntimeExitCode.invalidArguments.rawValue)
} catch {
    fputs("pdf-ingest error: \(error)\n", stderr)
    exit(RuntimeExitCode.runtimeFailure.rawValue)
}
