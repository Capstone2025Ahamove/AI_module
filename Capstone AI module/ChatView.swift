//
//  ChatView.swift
//  Capstone AI module
//

import SwiftUI

// MARK: - Models (Codable for persistence)

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let sender: String   // "user" or "assistant"
    let content: String

    init(id: UUID = UUID(), sender: String, content: String) {
        self.id = id
        self.sender = sender
        self.content = content
    }
}

struct ChatTranscript: Codable {
    let threadId: String
    var messages: [ChatMessage]
    var updatedAt: Date
}

// MARK: - Disk store (per-thread JSON)

enum ChatStore {
    static func folderURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("ChatThreads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func fileURL(for threadId: String) -> URL {
        folderURL().appendingPathComponent("\(threadId).json")
    }

    static func load(threadId: String) -> [ChatMessage]? {
        let url = fileURL(for: threadId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let t = try? JSONDecoder().decode(ChatTranscript.self, from: data) {
            return t.messages
        }
        return nil
    }

    static func save(threadId: String, messages: [ChatMessage]) {
        let t = ChatTranscript(threadId: threadId, messages: messages, updatedAt: Date())
        if let data = try? JSONEncoder().encode(t) {
            try? data.write(to: fileURL(for: threadId), options: .atomic)
        }
    }
}

// MARK: - ChatView

struct ChatView: View {
    var threadId: String?
    var fileId: String?
    /// Optional: if you pass a summary from SummaryView, it will be used only when no history exists yet.
    var openingText: String? = nil

    @Environment(\.presentationMode) private var presentationMode
    @State private var userMessage = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false

    // Keep your existing assistant id
    private let assistantId = "asst_p0ajNzziydcju4E9O37JLWtt"

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#FFFCF7").ignoresSafeArea()

                VStack(spacing: 0) {
                    chatScrollView
                    Divider()
                    messageInputBar
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { presentationMode.wrappedValue.dismiss() } label: {
                        Image(systemName: "chevron.left").foregroundColor(Color(hex: "#00731D"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 20) {
                        Button(action: {}) {
                            Image(systemName: "arrow.down.circle").foregroundColor(Color(hex: "#00731D"))
                        }
                        NavigationLink {
                            ConversationsView()
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(Color(hex: "#00731D"))
                        }
                    }
                }
            }
            .onAppear(perform: loadOrSeed)
            .onDisappear(perform: persistIfPossible)
        }
    }

    // MARK: UI

    private var chatScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(messages) { msg in
                    Text(msg.content)
                        .padding(12)
                        .background(msg.sender == "user" ? Color(hex: "#00731D") : Color.white)
                        .foregroundColor(msg.sender == "user" ? .white : .black)
                        .cornerRadius(12)
                        .frame(maxWidth: .infinity, alignment: msg.sender == "user" ? .trailing : .leading)
                }
            }
            .padding()
        }
        .background(Color.clear)
    }

    private var messageInputBar: some View {
        HStack(spacing: 10) {
            TextField("Continue conversation...", text: $userMessage)
                .padding(10)
                .background(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))

            Button(action: send) {
                Image(systemName: "paperplane")
                    .padding(10)
                    .foregroundColor(Color(hex: "#00731D"))
            }
            .disabled(userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || threadId == nil)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(hex: "#FFFCF7"))
    }

    // MARK: Load/Seed/Persist

    private func loadOrSeed() {
        guard let tid = threadId else { return }

        // 1) Load from disk if exists
        if let saved = ChatStore.load(threadId: tid), !saved.isEmpty {
            messages = saved
            return
        }

        // 2) If you passed an openingText (e.g., Summary), seed with that once
        if let opening = openingText?.trimmingCharacters(in: .whitespacesAndNewlines), !opening.isEmpty {
            let opener = opening + "\n\nAsk me anything about the analysis."
            messages = [ChatMessage(sender: "assistant", content: opener)]
            ChatStore.save(threadId: tid, messages: messages)
            return
        }

        // 3) Otherwise, fetch latest assistant reply from the thread to start
        guard let _ = HTTPClient.shared.apiKey, !(HTTPClient.shared.apiKey ?? "").isEmpty else {
            messages = [ChatMessage(sender: "assistant", content: "Missing API key. Please set OPENAI_API_KEY in Info.plist.")]
            return
        }

        isLoading = true
        HTTPClient.shared.fetchLatestAssistantText(threadId: tid) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let text):
                    let opener = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        + "\n\nAsk me anything about the analysis."
                    self.messages = [ChatMessage(sender: "assistant", content: opener)]
                case .failure:
                    self.messages = [ChatMessage(
                        sender: "assistant",
                        content: "I’m ready to answer questions about your analysis. Ask me anything about the KPIs, trends, or next actions."
                    )]
                }
                self.persistIfPossible()
            }
        }
    }

    private func persistIfPossible() {
        if let tid = threadId, !messages.isEmpty {
            ChatStore.save(threadId: tid, messages: messages)
        }
    }

    // MARK: Send / Run

    private func send() {
        guard let tid = threadId else { return }
        let outgoing = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !outgoing.isEmpty else { return }

        messages.append(ChatMessage(sender: "user", content: outgoing))
        persistIfPossible()
        userMessage = ""
        isLoading = true

        // 1) Add user message to the thread
        let content: [[String: Any]] = [["type": "text", "text": outgoing]]
        HTTPClient.shared.addMessage(threadId: tid, content: content) { result in
            switch result {
            case .failure:
                DispatchQueue.main.async { self.isLoading = false }
            case .success:
                // 2) Run the chat assistant on the same thread (attach file to code interpreter if available)
                var toolResources: [String: Any]? = nil
                if let fid = self.fileId, !fid.isEmpty {
                    toolResources = ["code_interpreter": ["file_ids": [fid]]]
                }

                HTTPClient.shared.createRun(threadId: tid, assistantId: self.assistantId, toolResources: toolResources) { runResult in
                    switch runResult {
                    case .failure:
                        DispatchQueue.main.async { self.isLoading = false }
                    case .success(let runId):
                        // 3) Poll and then fetch the newest assistant text
                        HTTPClient.shared.pollRunWithBackoff(threadId: tid, runId: runId, maxAttempts: 10, initialDelay: 2.0) { pollResult in
                            switch pollResult {
                            case .failure:
                                DispatchQueue.main.async { self.isLoading = false }
                            case .success:
                                HTTPClient.shared.fetchLatestAssistantText(threadId: tid) { textResult in
                                    DispatchQueue.main.async {
                                        self.isLoading = false
                                        if case .success(let reply) = textResult {
                                            self.messages.append(ChatMessage(sender: "assistant", content: reply))
                                            self.persistIfPossible()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ChatView(threadId: "demo_thread", fileId: nil, openingText: "Here’s a sample summary.")
}
