import AppKit
import SwiftUI

/// The session log, following new lines as they arrive.
struct LogView: View {
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        let lines = ActivityFeed.shared.lines
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(lines.isEmpty ? "The log is empty. Switch Wave on to start a session." : lines.joined(separator: "\n"))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(lines.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.top, for: .alignment) // a short log starts at the top, not the bottom
            .onChange(of: lines.count) { proxy.scrollTo("end", anchor: .bottom) }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString((try? String(contentsOf: SessionLog.url, encoding: .utf8)) ?? "", forType: .string)
                }
                .help("Copy the whole log")
                Button("Reveal in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([SessionLog.url])
                }
                .help("Show session.log in Finder")
            }
        }
        .navigationSubtitle(lines.count >= ActivityFeed.keep ? "Last \(ActivityFeed.keep) lines" : "")
        .task { if !snapshot { await ActivityFeed.shared.follow() } }
    }
}
