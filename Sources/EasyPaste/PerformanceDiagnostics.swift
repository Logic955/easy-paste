import Foundation

enum EasyPasteDiagnostics {
    nonisolated(unsafe) static var isEnabled = false
    private static let fileQueue = DispatchQueue(label: "com.easypaste.performance-diagnostics")

    static func now() -> CFAbsoluteTime {
        CFAbsoluteTimeGetCurrent()
    }

    static func elapsedMS(since start: CFAbsoluteTime) -> String {
        String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    static func log(_ event: String, _ fields: [String: String] = [:]) {
        guard isEnabled else { return }
        let body = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        if body.isEmpty {
            let line = "EasyPastePerf event=\(event)"
            NSLog(line)
            appendToFile(line)
        } else {
            let line = "EasyPastePerf event=\(event) \(body)"
            NSLog(line)
            appendToFile(line)
        }
    }

    private static func appendToFile(_ message: String) {
        fileQueue.async {
            do {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let timestamp = formatter.string(from: Date())
                let line = "\(timestamp) \(message)\n"
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("EasyPaste", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let fileURL = directory.appendingPathComponent("performance.log")
                let data = Data(line.utf8)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: fileURL, options: .atomic)
                }
            } catch {
                NSLog("EasyPastePerf fileLogError=\(error.localizedDescription)")
            }
        }
    }
}
