import Foundation

/// Plain-text log of what Wave saw and did, so a test session can be read back afterwards. Text only, no images.
/// A fresh file starts each time Wave is switched on: ~/Library/Logs/Wave/session.log
enum SessionLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Wave/session.log")
    private static var handle: FileHandle?
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func begin() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        log("session start")
    }

    /// Main thread only.
    static func log(_ s: String) {
        handle?.write(Data("\(time.string(from: Date())) \(s)\n".utf8))
    }
}
