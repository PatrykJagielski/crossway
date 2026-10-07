import Foundation

// `.app` shortcuts call the binary with `--launch`; run headless in that case.
if let code = CommandLineLauncher.handle(CommandLine.arguments) {
    exit(code)
}
if let code = CLI.handle(CommandLine.arguments) {
    exit(code)
}
CrosswayApp.main()
