import Foundation
import WebKit
import UniformTypeIdentifiers

/// Serves the bundled Meow web build (`web/` folder in the app bundle) at `meow://app/…`.
///
/// A custom scheme gives the page a stable origin, so localStorage / IndexedDB (where Meow keeps
/// all notes) persist across launches, without running a local HTTP server.
/// There is no backend: `/api/*` answers 404, which the web app treats as "local-only mode".
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "meow"
    static let host = "app"
    static var homeURL: URL { URL(string: "\(scheme)://\(host)/")! }

    private let root: URL = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            return task.didFailWithError(URLError(.badURL))
        }

        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }

        if path.hasPrefix("/api/") || path == "/api" {
            let body = Data(#"{"error":"offline","message":"Meow iOS runs locally without a server"}"#.utf8)
            return respond(task, url: url, status: 404, mime: "application/json", body: body)
        }

        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        var isDir: ObjCBool = false
        guard file.path.hasPrefix(root.standardizedFileURL.path),
              FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue,
              let data = try? Data(contentsOf: file, options: .mappedIfSafe)
        else {
            return respond(task, url: url, status: 404, mime: "text/plain", body: Data("Not Found".utf8))
        }

        let mime = Self.mimeType(for: file)

        // Byte ranges, needed for <video>/<audio> playback from bundled assets.
        if let range = task.request.value(forHTTPHeaderField: "Range"),
           let (start, end) = Self.parseRange(range, length: data.count) {
            let slice = data.subdata(in: start..<(end + 1))
            return respond(task, url: url, status: 206, mime: mime, body: slice, extra: [
                "Content-Range": "bytes \(start)-\(end)/\(data.count)",
            ])
        }
        respond(task, url: url, status: 200, mime: mime, body: data)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        // All responses are delivered synchronously in `start`, so there is nothing to cancel.
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, status: Int, mime: String, body: Data,
                         extra: [String: String] = [:]) {
        var headers = [
            "Content-Type": mime,
            "Content-Length": String(body.count),
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-cache",
            "Access-Control-Allow-Origin": "*",
        ]
        headers.merge(extra) { $1 }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }

    private static func parseRange(_ header: String, length: Int) -> (Int, Int)? {
        guard length > 0, header.hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }
        var start: Int, end: Int
        if parts[0].isEmpty {                      // bytes=-N (suffix)
            guard let n = Int(parts[1]), n > 0 else { return nil }
            start = max(0, length - n); end = length - 1
        } else {
            guard let s = Int(parts[0]) else { return nil }
            start = s
            end = parts[1].isEmpty ? length - 1 : min(Int(parts[1]) ?? (length - 1), length - 1)
        }
        guard start <= end, start < length else { return nil }
        return (start, end)
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "wasm": return "application/wasm"
        case "svg": return "image/svg+xml"
        default:
            return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
