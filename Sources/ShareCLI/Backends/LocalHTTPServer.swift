import Foundation
import Network

/// A tiny single-file HTTP server for `share serve`.
///
/// Serves exactly one file at `/<token>/<filename>` (GET and HEAD, with single-range support so
/// iOS Safari can resume). Everything else is 404. The random token keeps the link unguessable
/// on a shared network; there is no directory listing and no upload.
final class LocalHTTPServer {
    struct Download {
        let remote: String
        let bytes: Int64
        let complete: Bool
    }

    let file: URL
    let fileName: String
    let token: String
    let fileSize: Int64
    let contentType: String

    /// Called on the server queue after each completed (or aborted) response.
    var onDownload: ((Download) -> Void)?
    /// Called when the listener fails after starting.
    var onFailure: ((Error) -> Void)?

    private(set) var port: UInt16 = 0
    private(set) var downloadCount = 0
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "share.serve")
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// Bytes served per client, so a download made of several range requests still counts once.
    private var servedByRemote: [String: Int64] = [:]
    private static let chunkSize = 256 * 1024

    init(file: URL, token: String) throws {
        self.file = file
        self.fileName = file.lastPathComponent
        self.token = token
        guard let size = Packager.fileSize(file) else { throw ShareError.inputNotFound(file.path) }
        self.fileSize = size
        self.contentType = Self.mimeType(for: file.pathExtension)
    }

    var path: String {
        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        return "/\(token)/\(encodedName)"
    }

    func start(port requestedPort: UInt16?) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        if let requested = requestedPort, requested > 0, let nwPort = NWEndpoint.Port(rawValue: requested) {
            listener = try NWListener(using: parameters, on: nwPort)
        } else {
            listener = try NWListener(using: parameters)
        }
        self.listener = listener

        let ready = DispatchSemaphore(value: 0)
        var startupError: Error?

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.port = listener.port?.rawValue ?? 0
                ready.signal()
            case .failed(let error):
                if self?.port == 0 {
                    startupError = error
                    ready.signal()
                } else {
                    self?.onFailure?(error)
                }
            case .cancelled:
                if self?.port == 0 { ready.signal() }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)

        if ready.wait(timeout: .now() + 5) == .timedOut {
            listener.cancel()
            throw ShareError.backendUnavailable("could not start the local server")
        }
        if let error = startupError {
            listener.cancel()
            if let port = requestedPort {
                throw ShareError.backendUnavailable("port \(port) is not available: \(error.localizedDescription)", hint: "pick another with --port, or omit it for a random free port")
            }
            throw ShareError.backendUnavailable("could not start the local server: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async {
            self.connections.values.forEach { $0.cancel() }
            self.connections.removeAll()
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .failed, .cancelled:
                self.connections.removeValue(forKey: ObjectIdentifier(connection))
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buffer = buffer
            if let data = data { buffer.append(data) }
            if let error = error {
                Log.debug("serve: receive error \(error)")
                connection.cancel()
                return
            }
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
                self.handle(request: String(decoding: headerData, as: UTF8.self), on: connection)
            } else if isComplete || buffer.count > 64 * 1024 {
                self.respond(connection, status: 400, reason: "Bad Request", headers: [:], body: Data("bad request\n".utf8))
            } else {
                self.receiveRequest(connection, buffer: buffer)
            }
        }
    }

    private func handle(request: String, on connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ").map(String.init) ?? []
        guard requestLine.count >= 2 else {
            respond(connection, status: 400, reason: "Bad Request", headers: [:], body: Data("bad request\n".utf8))
            return
        }
        let method = requestLine[0].uppercased()
        let target = requestLine[1].split(separator: "?").first.map(String.init) ?? requestLine[1]
        let remote = Self.describe(connection.endpoint)

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        guard method == "GET" || method == "HEAD" else {
            respond(connection, status: 405, reason: "Method Not Allowed", headers: ["Allow": "GET, HEAD"], body: Data("method not allowed\n".utf8))
            return
        }

        let decodedTarget = target.removingPercentEncoding ?? target
        let expected = "/\(token)/\(fileName)"
        if decodedTarget == "/\(token)" || decodedTarget == "/\(token)/" {
            respond(connection, status: 302, reason: "Found", headers: ["Location": path], body: Data())
            return
        }
        guard decodedTarget == expected else {
            Log.debug("serve: \(remote) requested \(target) → 404")
            respond(connection, status: 404, reason: "Not Found", headers: [:], body: Data("not found\n".utf8))
            return
        }

        var start: Int64 = 0
        var end: Int64 = fileSize - 1
        var partial = false
        if let range = headers["range"], range.hasPrefix("bytes=") {
            let spec = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            if spec.count == 2 {
                if let s = Int64(spec[0]) { start = s; end = Int64(spec[1]) ?? end; partial = true }
                else if let suffix = Int64(spec[1]) { start = max(0, fileSize - suffix); partial = true }
            }
            if start < 0 || start >= fileSize || end < start {
                respond(connection, status: 416, reason: "Range Not Satisfiable", headers: ["Content-Range": "bytes */\(fileSize)"], body: Data())
                return
            }
            end = min(end, fileSize - 1)
        }
        let length = end - start + 1

        var responseHeaders: [String: String] = [
            "Content-Type": contentType,
            "Content-Length": "\(length)",
            "Content-Disposition": "attachment; filename=\"\(Self.asciiFileName(fileName))\"; filename*=UTF-8''\(Self.rfc5987(fileName))",
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
        ]
        if partial { responseHeaders["Content-Range"] = "bytes \(start)-\(end)/\(fileSize)" }

        let status = partial ? 206 : 200
        let reason = partial ? "Partial Content" : "OK"
        Log.debug("serve: \(remote) \(method) \(target) → \(status)\(partial ? " [\(start)-\(end)]" : "")")

        if method == "HEAD" {
            let head = Self.headerBlock(status: status, reason: reason, headers: responseHeaders)
            connection.send(content: head, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: file) else {
            respond(connection, status: 500, reason: "Internal Server Error", headers: [:], body: Data("cannot read file\n".utf8))
            return
        }
        try? handle.seek(toOffset: UInt64(start))

        let head = Self.headerBlock(status: status, reason: reason, headers: responseHeaders)
        connection.send(content: head, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                Log.debug("serve: send error \(error)")
                try? handle.close()
                connection.cancel()
                return
            }
            self.stream(handle: handle, remaining: length, sent: 0, remote: remote, on: connection)
        })
    }

    private func stream(handle: FileHandle, remaining: Int64, sent: Int64, remote: String, on connection: NWConnection) {
        guard remaining > 0 else {
            try? handle.close()
            finish(connection, remote: remote, bytes: sent, complete: true)
            return
        }
        let chunk = handle.readData(ofLength: Int(min(Int64(Self.chunkSize), remaining)))
        guard !chunk.isEmpty else {
            try? handle.close()
            finish(connection, remote: remote, bytes: sent, complete: false)
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                Log.debug("serve: send error \(error)")
                try? handle.close()
                self.finish(connection, remote: remote, bytes: sent, complete: false)
                return
            }
            self.stream(handle: handle, remaining: remaining - Int64(chunk.count), sent: sent + Int64(chunk.count), remote: remote, on: connection)
        })
    }

    private func finish(_ connection: NWConnection, remote: String, bytes: Int64, complete: Bool) {
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
        guard complete else {
            onDownload?(Download(remote: remote, bytes: bytes, complete: false))
            return
        }
        let total = (servedByRemote[remote] ?? 0) + bytes
        if total >= fileSize {
            servedByRemote[remote] = 0
            downloadCount += 1
            onDownload?(Download(remote: remote, bytes: max(bytes, fileSize), complete: true))
        } else {
            servedByRemote[remote] = total
            Log.debug("serve: \(remote) has \(HumanReadable.fileSize(total)) of \(HumanReadable.fileSize(fileSize)) so far")
        }
    }

    private func respond(_ connection: NWConnection, status: Int, reason: String, headers: [String: String], body: Data) {
        var allHeaders = headers
        allHeaders["Content-Length"] = "\(body.count)"
        if allHeaders["Content-Type"] == nil { allHeaders["Content-Type"] = "text/plain; charset=utf-8" }
        var payload = Self.headerBlock(status: status, reason: reason, headers: allHeaders)
        payload.append(body)
        connection.send(content: payload, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Helpers

    static func headerBlock(status: Int, reason: String, headers: [String: String]) -> Data {
        var text = "HTTP/1.1 \(status) \(reason)\r\n"
        text += "Server: share/\(Version.current)\r\n"
        text += "Connection: close\r\n"
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            text += "\(key): \(value)\r\n"
        }
        text += "\r\n"
        return Data(text.utf8)
    }

    static func describe(_ endpoint: NWEndpoint) -> String {
        if case .hostPort(let host, _) = endpoint {
            return "\(host)".replacingOccurrences(of: "%en0", with: "")
        }
        return "\(endpoint)"
    }

    static func rfc5987(_ name: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }

    static func asciiFileName(_ name: String) -> String {
        let ascii = name.unicodeScalars.map { $0.isASCII && $0 != "\"" && $0.value >= 32 ? Character($0) : Character("_") }
        return String(ascii)
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "zip": return "application/zip"
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "wav": return "audio/wav"
        case "txt", "md", "log", "patch", "diff": return "text/plain; charset=utf-8"
        case "html", "htm": return "text/html; charset=utf-8"
        case "json": return "application/json"
        case "csv": return "text/csv"
        case "tar": return "application/x-tar"
        case "gz", "tgz": return "application/gzip"
        case "dmg": return "application/x-apple-diskimage"
        case "pkg": return "application/octet-stream"
        default: return "application/octet-stream"
        }
    }

    static func randomToken(length: Int = 12) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }
}
