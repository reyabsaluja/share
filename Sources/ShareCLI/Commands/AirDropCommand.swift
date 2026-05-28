import AppKit
import ArgumentParser
import Foundation

struct AirDropCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "airdrop",
        abstract: "Share via native AirDrop.",
        aliases: ["ad", "drop"]
    )

    @Argument(help: "Files, directories, or URLs to share. Defaults to current directory.")
    var items: [String] = []

    @Option(name: [.short, .long], help: "Custom archive name.")
    var name: String?

    @Flag(name: .long, help: "Do not zip directories.")
    var noZip = false

    @Flag(name: .long, help: "Show what would happen.")
    var dryRun = false

    @Flag(name: .long, help: "Print verbose output.")
    var verbose = false

    @Flag(name: .long, help: "Suppress non-error output.")
    var quiet = false

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() throws {
        Log.verbose = verbose
        Log.quiet = quiet

        let resolved = try InputResolver.resolve(items)

        let prepared: [PreparedShareItem]
        if noZip {
            prepared = resolved.map { $0.toPrepared() }
        } else {
            prepared = try Packager.packageIfNeeded(items: resolved, archiveName: name, keepTemp: false, verbose: verbose)
        }

        if dryRun {
            if json {
                print(JSONOutput.success(destination: "airdrop", backend: "NSSharingService.sendViaAirDrop", items: prepared, openedNativeUI: false))
            } else {
                for item in prepared {
                    if item.packaged, case .file(let url) = item.value {
                        print("Would package → \(url.lastPathComponent)")
                    }
                    print("Would AirDrop: \(item.displayName)")
                }
            }
            return
        }

        if !quiet {
            for item in prepared where item.packaged {
                Log.info("Zipped → \(item.displayName)")
            }
            Log.info("Opening AirDrop…")
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let backend = AirDropBackend()
        try backend.share(prepared)

        if json {
            print(JSONOutput.success(destination: "airdrop", backend: backend.name, items: prepared, openedNativeUI: true))
        }
    }
}
