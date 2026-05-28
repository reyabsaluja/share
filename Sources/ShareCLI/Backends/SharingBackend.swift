import Foundation

protocol SharingBackend {
    var name: String { get }
    func share(_ items: [PreparedShareItem]) throws
}
