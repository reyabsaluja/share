import ArgumentParser
import Foundation

struct CompletionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completions",
        abstract: "Generate or install shell completions."
    )

    @Argument(help: "Shell: zsh, bash, or fish.")
    var shell: String = "zsh"

    @Flag(name: .long, help: "Install completions to the appropriate directory.")
    var install = false

    func run() throws {
        switch shell.lowercased() {
        case "zsh":
            if install {
                try installZsh()
            } else {
                let completions = try generateCompletions(for: "zsh")
                print(completions)
            }
        case "bash":
            if install {
                try installBash()
            } else {
                let completions = try generateCompletions(for: "bash")
                print(completions)
            }
        case "fish":
            if install {
                try installFish()
            } else {
                let completions = try generateCompletions(for: "fish")
                print(completions)
            }
        default:
            throw ShareError.usage("Unsupported shell: \(shell). Use zsh, bash, or fish.")
        }
    }

    private func generateCompletions(for shell: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        process.arguments = ["--generate-completion-script", shell]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            throw ShareError.packagingFailed("Failed to generate completions")
        }
        return output
    }

    private func installZsh() throws {
        let completions = try generateCompletions(for: "zsh")
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zsh/completions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("_share")
        try completions.write(to: file, atomically: true, encoding: .utf8)
        print("Installed to \(file.path)")
        print("Add to your .zshrc if not already there:")
        print("  fpath=(~/.zsh/completions $fpath)")
        print("  autoload -Uz compinit && compinit")
    }

    private func installBash() throws {
        let completions = try generateCompletions(for: "bash")
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/bash-completion/completions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("share")
        try completions.write(to: file, atomically: true, encoding: .utf8)
        print("Installed to \(file.path)")
    }

    private func installFish() throws {
        let completions = try generateCompletions(for: "fish")
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/fish/completions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("share.fish")
        try completions.write(to: file, atomically: true, encoding: .utf8)
        print("Installed to \(file.path)")
    }
}
