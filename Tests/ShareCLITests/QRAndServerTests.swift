import Foundation
import Testing
@testable import share

extension ShareTests {
    @Suite struct QRTests {
        @Test func generatesSquareModulesAndPNG() throws {
            let code = try QRRenderer.code("https://example.com")
            #expect(code.size >= 21)
            #expect(code.modules.allSatisfy { $0.count == code.size })
            // Finder pattern: top-left corner module is dark (after the generator's own quiet zone).
            #expect(code.modules.flatMap { $0 }.contains(true))

            let terminal = QRRenderer.terminal(code, color: false, quietZone: 1)
            let lines = terminal.split(separator: "\n")
            #expect(lines.count == (code.size + 2 + 1) / 2)
            #expect(lines.allSatisfy { $0.count == code.size + 2 })

            let png = try QRRenderer.png("hi", scale: 4)
            #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        }

        @Test func rejectsOversizedInput() {
            #expect(throws: ShareError.self) { _ = try QRRenderer.code(String(repeating: "x", count: 4000)) }
        }
    }

    @Suite struct LocalHTTPServerTests {
        private func fetch(_ url: URL, method: String = "GET", headers: [String: String] = [:]) throws -> (Int, [String: String], Data) {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 5
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            let semaphore = DispatchSemaphore(value: 0)
            var output: (Int, [String: String], Data) = (0, [:], Data())
            var failure: Error?
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let http = response as? HTTPURLResponse {
                    var h: [String: String] = [:]
                    for (k, v) in http.allHeaderFields { h[String(describing: k).lowercased()] = String(describing: v) }
                    output = (http.statusCode, h, data ?? Data())
                }
                failure = error
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 10)
            if let failure = failure { throw failure }
            return output
        }

        @Test func servesExactlyOneFileWithRanges() throws {
            let sandbox = try Sandbox()
            let payload = String(repeating: "0123456789", count: 100)
            let file = try sandbox.file("data.txt", payload)
            let server = try LocalHTTPServer(file: file, token: "tok3n")
            try server.start(port: nil)
            defer { server.stop() }
            #expect(server.port > 0)

            var downloads: [LocalHTTPServer.Download] = []
            server.onDownload = { downloads.append($0) }

            let base = URL(string: "http://127.0.0.1:\(server.port)")!
            let good = base.appendingPathComponent(server.path)

            let (status, headers, body) = try fetch(good)
            #expect(status == 200)
            #expect(body == Data(payload.utf8))
            #expect(headers["content-disposition"]?.contains("data.txt") == true)
            #expect(headers["content-type"]?.hasPrefix("text/plain") == true)

            let (headStatus, headHeaders, headBody) = try fetch(good, method: "HEAD")
            #expect(headStatus == 200 && headBody.isEmpty)
            #expect(headHeaders["content-length"] == "\(payload.utf8.count)")

            let (rangeStatus, rangeHeaders, rangeBody) = try fetch(good, headers: ["Range": "bytes=0-9"])
            #expect(rangeStatus == 206)
            #expect(rangeBody == Data("0123456789".utf8))
            #expect(rangeHeaders["content-range"] == "bytes 0-9/1000")

            #expect(try fetch(base.appendingPathComponent("/tok3n/other.txt")).0 == 404)
            #expect(try fetch(base.appendingPathComponent("/wrong/data.txt")).0 == 404)
            #expect(try fetch(good, method: "POST").0 == 405)
            #expect(try fetch(good, headers: ["Range": "bytes=5000-"]).0 == 416)

            // One full download plus a partial one: only the full one counts.
            #expect(server.downloadCount == 1)
            #expect(downloads.filter(\.complete).count == 1)
        }

        @Test func mimeTypesAndHelpers() {
            #expect(LocalHTTPServer.mimeType(for: "ZIP") == "application/zip")
            #expect(LocalHTTPServer.mimeType(for: "weird") == "application/octet-stream")
            #expect(LocalHTTPServer.asciiFileName("ré\"port.pdf") == "r__port.pdf")
            #expect(LocalHTTPServer.rfc5987("my file.pdf") == "my%20file.pdf")
            #expect(LocalHTTPServer.randomToken().count == 12)
            #expect(LocalHTTPServer.randomToken() != LocalHTTPServer.randomToken())
        }
    }
}
