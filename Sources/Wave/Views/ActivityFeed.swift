import Foundation
import Observation

/// Tails ~/Library/Logs/Wave/session.log for Home and the Log page. Views call `poll()` every 0.5 s while visible.
@Observable
final class ActivityFeed {
    static let shared = ActivityFeed()
    static let keep = 1500

    /// The newest lines of the log, oldest first.
    var lines: [String] = []

    @ObservationIgnored private var offset: UInt64 = 0
    @ObservationIgnored private var fileID: Int?
    @ObservationIgnored private var partial = ""

    func poll() {
        // Reopened by path each time: SessionLog.begin() replaces the file whenever Wave is switched on.
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: SessionLog.url.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let h = try? FileHandle(forReadingFrom: SessionLog.url) else { return }
        defer { try? h.close() }
        let id = (attrs[.systemFileNumber] as? NSNumber)?.intValue
        if id != fileID || size < offset { fileID = id; offset = 0; partial = ""; lines = [] }
        guard size > offset, (try? h.seek(toOffset: offset)) != nil, let data = try? h.readToEnd() else { return }
        offset += UInt64(data.count)
        var parts = (partial + String(decoding: data, as: UTF8.self)).components(separatedBy: "\n")
        partial = parts.removeLast()
        lines = Array((lines + parts).suffix(Self.keep))
    }

    /// Things Wave did, newest first, in plain words. What it merely saw (hands, gestures, signs) is left out, and so are
    /// cursor enter/exit/scroll and sticky notch lines, which the notch flashes already report.
    func recent(_ n: Int) -> [(time: String, text: String)] {
        let cursor = ["cursor leftClick(1)": "Click", "cursor leftClick(2)": "Double-click", "cursor rightClick": "Right-click",
                      "cursor leftDown": "Drag started", "cursor leftUp": "Dropped", "session start": "Session started"]
        var out: [(String, String)] = []
        for line in lines.reversed() where out.count < n {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let msg = parts[1]
            let text: String
            if let c = cursor[msg] { text = c }
            else if msg.hasPrefix("notch \"") { text = msg.dropFirst(6).replacingOccurrences(of: "\"", with: "") }
            else if ["hands ", "gesture ", "sign ", "cursor ", "notch "].contains(where: msg.hasPrefix) { continue }
            else { text = msg.prefix(1).uppercased() + msg.dropFirst() }
            // The L sign's 🇱 renders as a boxed placeholder.
            out.append((String(parts[0].prefix(8)), text.replacingOccurrences(of: "🇱", with: "L")))
        }
        return out
    }

    /// From the latest "hands seen=N kept=M" line: hands kept and hands ignored as too far away.
    var handCounts: (kept: Int, ignored: Int)? {
        guard let line = lines.last(where: { $0.contains(" hands seen=") }) else { return nil }
        func value(_ key: String) -> Int? {
            line.components(separatedBy: " ").first { $0.hasPrefix(key) }.flatMap { Int($0.dropFirst(key.count)) }
        }
        guard let seen = value("seen="), let kept = value("kept=") else { return nil }
        return (kept, max(0, seen - kept))
    }

    /// Polls until the calling view's task is cancelled (the view went away).
    func follow() async {
        while !Task.isCancelled {
            poll()
            try? await Task.sleep(for: .seconds(0.5))
        }
    }
}
