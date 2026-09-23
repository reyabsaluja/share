import Foundation

/// Finds the address other devices on the local network can reach this Mac at.
enum NetworkInfo {
    struct Interface {
        let name: String
        let address: String
    }

    /// IPv4 addresses of active, non-loopback interfaces, Wi-Fi/Ethernet first.
    static func lanIPv4Interfaces() -> [Interface] {
        var result: [Interface] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }

            let name = String(cString: entry.pointee.ifa_name)
            guard !name.hasPrefix("utun"), !name.hasPrefix("awdl"), !name.hasPrefix("llw"), !name.hasPrefix("bridge"), !name.hasPrefix("vmnet") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(cString: host)
            guard !address.hasPrefix("169.254.") else { continue }
            result.append(Interface(name: name, address: address))
        }

        // en0/en1 (Wi-Fi, Ethernet) with private addresses are the ones phones and laptops can reach.
        return result.sorted { a, b in
            let aEn = a.name.hasPrefix("en"), bEn = b.name.hasPrefix("en")
            if aEn != bEn { return aEn }
            let aPrivate = isPrivate(a.address), bPrivate = isPrivate(b.address)
            if aPrivate != bPrivate { return aPrivate }
            return a.name < b.name
        }
    }

    /// RFC 1918 ranges: 10/8, 172.16/12, 192.168/16.
    static func isPrivate(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }

    static func primaryLanIPv4() -> String? {
        return lanIPv4Interfaces().first?.address
    }

    /// The Bonjour name (`MacBook.local`) when available.
    static func localHostname() -> String? {
        let result = Subprocess.run("/usr/sbin/scutil", arguments: ["--get", "LocalHostName"])
        let name = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.status == 0 && !name.isEmpty ? name + ".local" : nil
    }
}
