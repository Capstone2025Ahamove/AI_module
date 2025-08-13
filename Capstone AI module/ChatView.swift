//
//  ChatView.swift
//  Capstone AI module
//
//  Created by Elwiz Scott on 31/7/25.
//
import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let sender: String // "user" or "assistant"
    let content: String
}

struct ChatView: View {
    var threadId: String?
    var fileId: String?

    @Environment(\.presentationMode) private var presentationMode
    @State private var userMessage = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false

    // Your chat assistant (keep your existing id)
    private let assistantId = "asst_p0ajNzziydcju4E9O37JLWtt"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chatScrollView
                Divider()
                messageInputBar
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
                        Button(action: {}) {
                            Image(systemName: "ellipsis.circle").foregroundColor(Color(hex: "#00731D"))
                        }
                    }
                }
            }
            .onAppear(perform: seedOpeningMessageIfNeeded)
        }
    }

    // MARK: UI

    private var chatScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(messages) { msg in
                    Text(msg.content)
                        .padding()
                        .background(msg.sender == "user" ? Color(hex: "#00731D") : Color.white)
                        .foregroundColor(msg.sender == "user" ? .white : .black)
                        .cornerRadius(10)
                        .frame(maxWidth: .infinity, alignment: msg.sender == "user" ? .trailing : .leading)
                }
            }
            .padding()
        }
    }

    private var messageInputBar: some View {
        HStack {
            TextField("Continue conversation...", text: $userMessage)
                .padding(10)
                .background(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4), lineWidth: 1))

            Button {
                send()
            } label: {
                Image(systemName: "paperplane")
                    .padding(10)
                    .foregroundColor(Color(hex: "#00731D"))
            }
            .disabled(userMessage.isEmpty || isLoading || threadId == nil)
        }
        .padding()
        .background(Color("AppBackground"))
    }

    // MARK: Seed opening chat from thread

    private func seedOpeningMessageIfNeeded() {
        guard messages.isEmpty, let tid = threadId else { return }
        guard let _ = HTTPClient.shared.apiKey, !(HTTPClient.shared.apiKey ?? "").isEmpty else {
            // Show a friendly notice if key is missing
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
                    self.messages.append(ChatMessage(sender: "assistant", content: opener))
                case .failure:
                    // If nothing is found yet, still show a helpful opener
                    self.messages.append(ChatMessage(
                        sender: "assistant",
                        content: "I’m ready to answer questions about your analysis. Ask me anything about the KPIs, trends, or next actions."
                    ))
                }
            }
        }
    }

    // MARK: Send / Run

    private func send() {
        guard let tid = threadId, !userMessage.isEmpty else { return }
        let outgoing = userMessage
        messages.append(ChatMessage(sender: "user", content: outgoing))
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
                if let fid = self.fileId {
                    toolResources = ["code_interpreter": ["file_ids": [fid]]]
                }
                HTTPClient.shared.createRun(threadId: tid, assistantId: assistantId, toolResources: toolResources) { runResult in
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
    ChatView()
}
