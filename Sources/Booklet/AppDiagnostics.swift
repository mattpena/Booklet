import Foundation
import OSLog

enum AppDiagnostics {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Booklet", isDirectory: true)
    static let fileURL = directory.appendingPathComponent("Booklet.log")

    private static let logger = Logger(subsystem: "com.albumbooklet.app", category: "Diagnostics")
    private static let queue = DispatchQueue(label: "com.albumbooklet.app.diagnostics", qos: .utility)

    static func record(_ event: String) {
        logger.notice("\(event, privacy: .public)")
        queue.async {
            let fileManager = FileManager.default
            guard (try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return }

            if (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 1_000_000 {
                let previous = directory.appendingPathComponent("Booklet.previous.log")
                try? fileManager.removeItem(at: previous)
                try? fileManager.moveItem(at: fileURL, to: previous)
            }

            if !fileManager.fileExists(atPath: fileURL.path) {
                _ = fileManager.createFile(atPath: fileURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = Data("\(timestamp) \(event)\n".utf8)
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        }
    }
}
