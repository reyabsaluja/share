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

    @Flag(name: .long, help: "Exclude .git, node_modules, .DS_Store, build caches.")
    var smart = false

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

        let useSmart = (smart || ShareConfig.load().defaultSmart == true) && !noZip
        let effectiveItems: [ShareItem]
        if useSmart {
            effectiveItems = try resolved.map { item -> ShareItem in
                if case .directory(let url) = item {
                    let cleaned = try SmartExclude.stage(directory: url, verbose: verbose)
                    return .directory(cleaned)
                }
                return item
            }
        } else {
            effectiveItems = resolved
        }

        let prepared: [PreparedShareItem]
        if noZip {
            prepared = effectiveItems.map { $0.toPrepared() }
        } else {
            prepared = try Packager.packageIfNeeded(items: effectiveItems, archiveName: name, keepTemp: false, verbose: verbose)
        }

        if dryRun {
            if json {
                print(JSONOutput.success(destination: "airdrop", backend: "NSSharingService.sendViaAirDrop", items: prepared, openedNativeUI: false))
            } else {
                for item in prepared {
                    if item.packaged, case .file(let url) = item.value {
                        let size = HumanReadable.fileSizeAt(url.path) ?? ""
                        print("Would package → \(url.lastPathComponent) (\(size))")
                    } else {
                        print("Would AirDrop: \(item.displayName)")
                    }
                }
            }
            return
        }

        if !quiet {
            for item in prepared where item.packaged {
                if case .file(let url) = item.value {
                    let size = HumanReadable.fileSizeAt(url.path) ?? ""
                    Log.info("Packaged → \(url.lastPathComponent) " + Color.dim("(\(size))"))
                }
            }
            Log.info("Opening AirDrop…")
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let backend = AirDropBackend()
        try backend.share(prepared)

        History.record(destination: "airdrop", recipient: nil, items: items.isEmpty ? ["."] : items, archivePath: prepared.first(where: \.packaged).flatMap { if case .file(let u) = $0.value { return u.path }; return nil })

        if json {
            print(JSONOutput.success(destination: "airdrop", backend: backend.name, items: prepared, openedNativeUI: true))
        }
    }
}
