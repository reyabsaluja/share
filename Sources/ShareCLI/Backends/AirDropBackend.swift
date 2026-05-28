import AppKit
import Foundation

final class AirDropBackend: NSObject, SharingBackend, NSSharingServiceDelegate {
    let name = "NSSharingService.sendViaAirDrop"

    private var sharingComplete = false
    private var sharingError: Error?
    private var itemsToShareIndividually: [Any] = []
    private var individualSuccessCount = 0
    private var individualFailCount = 0
    private var isIndividualSharing = false

    func share(_ items: [PreparedShareItem]) throws {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            throw ShareError.backendUnavailable("AirDrop sharing service is unavailable on this Mac")
        }

        let appKitItems: [Any] = items.map { item -> Any in
            switch item.value {
            case .file(let url): return url as NSURL
            case .url(let url): return url as NSURL
            case .text(let text): return text as NSString
            }
        }

        NSApp.setActivationPolicy(.accessory)

        let hasURLs = items.contains { $0.kind == .url }
        let hasFiles = items.contains { $0.kind == .file }
        let isMixed = hasURLs && hasFiles

        if isMixed || !service.canPerform(withItems: appKitItems) {
            shareIndividually(items: appKitItems)
        } else {
            service.delegate = self
            service.perform(withItems: appKitItems)
        }

        let timeout = Date(timeIntervalSinceNow: 300)
        while !sharingComplete && RunLoop.main.run(mode: .default, before: timeout) {}

        if let error = sharingError {
            throw ShareError.packagingFailed(error.localizedDescription)
        }
    }

    private func shareIndividually(items: [Any]) {
        isIndividualSharing = true
        itemsToShareIndividually = items
        individualSuccessCount = 0
        individualFailCount = 0
        shareNextIndividualItem()
    }

    private func shareNextIndividualItem() {
        guard !itemsToShareIndividually.isEmpty else {
            sharingComplete = true
            return
        }

        let currentItem = itemsToShareIndividually.removeFirst()

        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            individualFailCount += 1
            shareNextIndividualItem()
            return
        }

        if service.canPerform(withItems: [currentItem]) {
            service.delegate = self
            service.perform(withItems: [currentItem])
        } else {
            individualFailCount += 1
            shareNextIndividualItem()
        }
    }

    // MARK: - NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        if isIndividualSharing {
            individualSuccessCount += 1
            shareNextIndividualItem()
        } else {
            sharingComplete = true
        }
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        if isIndividualSharing {
            individualFailCount += 1
            shareNextIndividualItem()
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
            styleMask: [.closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.level = .popUpMenu
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
