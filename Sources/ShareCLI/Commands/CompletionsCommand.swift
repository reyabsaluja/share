import ArgumentParser
import Foundation

struct CompletionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completions",
        abstract: "Print or install shell completions (zsh, bash, fish)."
    )

    @Argument(help: "Shell: zsh, bash, or fish. Defaults to $SHELL.")
    var shell: String?

    @Flag(name: .long, help: "Install into the shell's completion directory.")
    var install = false

    func run() throws {
        let name = (shell ?? Self.detectShell()).lowercased()
        guard let completionShell = CompletionShell(rawValue: name) else {
            throw ShareError.usage("unsupported shell '\(name)'", hint: "use zsh, bash, or fish")
        }
        let script = ShareCommand.completionScript(for: completionShell)

        guard install else {
            print(script)
            return
        }

        let home = Paths.home
        let file: URL
        var instructions: [String] = []
        switch name {
        case "zsh":
            let dir = home.appendingPathComponent(".zsh/completions")
            file = dir.appendingPathComponent("_share")
            instructions = [
                "Add to ~/.zshrc if it is not there already:",
                "  fpath=(~/.zsh/completions $fpath)",
                "  autoload -Uz compinit && compinit",
            ]
        case "bash":
            let dir = home.appendingPathComponent(".local/share/bash-completion/completions")
            file = dir.appendingPathComponent("share")
            instructions = ["Requires the bash-completion package (brew install bash-completion@2)."]
        default:
            file = home.appendingPathComponent(".config/fish/completions/share.fish")
        }

        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: file, atomically: true, encoding: .utf8)
        print("Installed \(name) completions → \(file.path)")
        instructions.forEach { print($0) }
        print("Restart your shell to activate them.")
    }

    static func detectShell() -> String {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return URL(fileURLWithPath: shellPath).lastPathComponent
    }
}
