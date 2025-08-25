//
//  StoredMessage.swift
//  Capstone AI module
//
//  Created by Elwiz Scott on 25/8/25.
//


import SwiftUI

// A lightweight reader for transcripts saved on disk.
// It tolerates different shapes by decoding only what we need.
private struct StoredMessage: Codable {
    let sender: String?
    let content: String?
}

private struct StoredTranscript: Codable {
    let threadId: String
    let messages: [StoredMessage]
    let updatedAt: Date?
}

// What we show in the list
private struct ConversationRecord: Identifiable {
    let id = UUID()
    let threadId: String
    let preview: String
    let updatedAt: Date
    let messageCount: Int
}

// The folder where ChatView should save transcripts.
// (Matches the path we suggested earlier: Documents/ChatThreads)
private enum ChatThreadsFolder {
    static func dir() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("ChatThreads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func list() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir(),
                                                      includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles]))?
            .filter { $0.pathExtension.lowercased() == "json" } ?? []
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll() {
        list().forEach { delete($0) }
    }
}

struct ConversationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ConversationRecord] = []

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Section {
                        Text("No saved conversations yet.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                } else {
                    ForEach(items) { rec in
                        NavigationLink {
                            // Open the saved thread; ChatView should load its history for this threadId
                            ChatView(threadId: rec.threadId, fileId: nil)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "text.bubble")
                                    .foregroundColor(Color(hex: "#00731D"))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(prettyThread(rec.threadId))
                                        .font(.headline)
                                    Text(rec.preview)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                    Text("\(rec.messageCount) message\(rec.messageCount == 1 ? "" : "s") • \(dateString(rec.updatedAt))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .onDelete(perform: deleteRows)
                }
            }
            .navigationTitle("Conversations")
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(Color(hex: "#00731D"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            ChatThreadsFolder.deleteAll()
                            load()
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                        Button {
                            load()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(Color(hex: "#00731D"))
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Loading & Helpers

    private func load() {
        var recs: [ConversationRecord] = []

        for url in ChatThreadsFolder.list() {
            guard
                let data = try? Data(contentsOf: url),
                let t = try? JSONDecoder().decode(StoredTranscript.self, from: data)
            else { continue }

            let preview = t.messages
                .compactMap { $0.content?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .last ?? "(no preview)"

            let updated = t.updatedAt ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast

            recs.append(
                ConversationRecord(
                    threadId: t.threadId,
                    preview: preview,
                    updatedAt: updated,
                    messageCount: t.messages.count
                )
            )
        }

        // Newest first
        recs.sort { $0.updatedAt > $1.updatedAt }
        items = recs
    }

    private func deleteRows(at offsets: IndexSet) {
        for idx in offsets {
            // Map back to file URL via threadId
            let rec = items[idx]
            let url = ChatThreadsFolder.dir().appendingPathComponent("\(rec.threadId).json")
            ChatThreadsFolder.delete(url)
        }
        load()
    }

    private func prettyThread(_ id: String) -> String {
        // thread_ABC… -> “Thread ABC…”
        let trimmed = id.replacingOccurrences(of: "thread_", with: "")
        return "Thread \(trimmed)"
    }

    private func dateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
