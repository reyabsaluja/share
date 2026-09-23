import AppKit
import Foundation

/// Opens the native AirDrop picker for the given items and waits for the transfer to finish.
///
/// Adapted from airdrop-cli (MIT, see THIRD_PARTY_NOTICES.md). Files and URLs cannot be mixed
/// in one AirDrop payload, so mixed sets are sent one item at a time.
final class AirDropBackend: NSObject, SharingBackend, NSSharingServiceDelegate {
    let name = "NSSharingService.sendViaAirDrop"

    /// Seconds to wait for the user to pick a device and for the transfer to complete.
    var timeout: TimeInterval

    private var sharingComplete = false
    private var sharingError: Error?
    private var queue: [Any] = []
    private var successCount = 0
    private var failCount = 0
    private var cancelled = false
    private var isIndividualSharing = false
    private var window: NSWindow?

    init(timeout: TimeInterval? = nil) {
        self.timeout = timeout ?? TimeInterval(ShareConfig.current.airdropTimeout ?? 300)
        super.init()
    }

    static var isAvailable: Bool {
        return NSSharingService(named: .sendViaAirDrop) != nil
    }

    func share(_ items: [PreparedShareItem]) throws {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            throw ShareError.backendUnavailable("AirDrop is unavailable on this Mac", hint: "AirDrop needs Wi-Fi and Bluetooth turned on")
        }

        let payload: [Any] = items.map { item -> Any in
            switch item.value {
            case .file(let url): return url as NSURL
            case .url(let url): return url as NSURL
            case .text(let text): return text as NSString
            }
        }
        guard !payload.isEmpty else { throw ShareError.usage("nothing to share") }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let hasURLs = items.contains { $0.kind == .url }
        let hasFiles = items.contains { $0.kind == .file }

        if (hasURLs && hasFiles) || !service.canPerform(withItems: payload) {
            shareIndividually(payload)
        } else {
            service.delegate = self
            service.perform(withItems: payload)
        }

        let deadline = Date(timeIntervalSinceNow: timeout)
        while !sharingComplete && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.25))
        }
        window?.orderOut(nil)

        if !sharingComplete {
            throw ShareError.timeout("AirDrop did not complete within \(Int(timeout)) seconds")
        }
        if cancelled && successCount == 0 {
            throw ShareError.userCancelled
        }
        if let error = sharingError {
            throw ShareError.sharingFailed("AirDrop failed: \(error.localizedDescription)")
        }
        if isIndividualSharing && successCount == 0 && failCount > 0 {
            throw ShareError.sharingFailed("AirDrop failed for all \(failCount) items")
        }
    }

    private func shareIndividually(_ items: [Any]) {
        isIndividualSharing = true
        queue = items
        shareNext()
    }

    private func shareNext() {
        guard !queue.isEmpty, !cancelled else {
            sharingComplete = true
            return
        }
        let item = queue.removeFirst()
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: [item]) else {
            failCount += 1
            shareNext()
            return
        }
        service.delegate = self
        service.perform(withItems: [item])
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    // MARK: - NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        successCount += 1
        if isIndividualSharing {
            shareNext()
        } else {
            sharingComplete = true
        }
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        if Self.isCancellation(error) {
            cancelled = true
            sharingComplete = true
            return
        }
        failCount += 1
        if isIndividualSharing {
            shareNext()
        } else {
            sharingError = error
            sharingComplete = true
        }
    }

    func sharingService(_ sharingService: NSSharingService, sourceFrameOnScreenForShareItem item: Any) -> NSRect {
        return NSRect(x: 0, y: 0, width: 400, height: 100)
    }

    func sharingService(
        _ sharingService: NSSharingService,
        sourceWindowForShareItems items: [Any],
        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>
    ) -> NSWindow? {
        let window = NSWindow(
            contentRect: .init(origin: .zero, size: .init(width: 1, height: 1)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.level = .popUpMenu
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        self.window = window
        return window
    }
}
