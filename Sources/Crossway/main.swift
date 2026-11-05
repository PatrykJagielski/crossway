import Foundation

// Wine output passes through `--log-sink`, which caps the log size.
if let code = LogSink.handle(CommandLine.arguments) {
    exit(code)
}
// `.app` shortcuts call the binary with `--launch`; run headless in that case.
if let code = CommandLineLauncher.handle(CommandLine.arguments) {
    exit(code)
}
if let code = CLI.handle(CommandLine.arguments) {
    exit(code)
}
CrosswayApp.main()
