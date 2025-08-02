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
    
    @Environment(\.presentationMode) var presentationMode

    @State private var userMessage = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false

    let assistantId = "asst_p0ajNzziydcju4E9O37JLWtt"
    let apiKey = ""

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
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(Color(hex: "#00731D"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 20) {
                        Button(action: {}) {
                            Image(systemName: "arrow.down.circle")
                                .foregroundColor(Color(hex: "#00731D"))
                        }
                        Button(action: {}) {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(Color(hex: "#00731D"))
                        }
                    }
                }
            }
        }
    }

    private var chatScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(messages) { message in
                    messageBubble(for: message.content, isUser: message.sender == "user")
                }
            }
            .padding()
        }
    }

    private func messageBubble(for text: String, isUser: Bool) -> some View {
        Text(text)
            .padding()
            .background(isUser ? Color(hex: "#00731D") : Color.white)
            .foregroundColor(isUser ? .white : .black)
            .cornerRadius(10)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var messageInputBar: some View {
        HStack {
            TextField("Continue conversation...", text: $userMessage)
                .padding(10)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                )

            Button(action: {
                send()
            }) {
                Image(systemName: "paperplane")
                    .padding(10)
                    .foregroundColor(Color(hex: "#00731D"))
            }
            .disabled(userMessage.isEmpty || isLoading || threadId == nil)
        }
        .padding()
        .background(Color("AppBackground"))
    }

    private func send() {
        guard let threadId = threadId, !userMessage.isEmpty else { return }
        let userMsg = ChatMessage(sender: "user", content: userMessage)
        messages.append(userMsg)
        let messageText = userMessage
        userMessage = ""
        isLoading = true
        sendChatMessage(threadId: threadId, content: messageText)
    }

    private func sendChatMessage(threadId: String, content: String) {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

        let payload: [String: Any] = [
            "role": "user",
            "content": content
        ]

        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { _, _, _ in
            runAssistant(threadId: threadId, fileId: fileId)
        }.resume()
    }

    private func runAssistant(threadId: String, fileId: String?) {
        var req = URLRequest(url: URL(string:"https://api.openai.com/v1/threads/\(threadId)/runs")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

        var payload: [String: Any] = ["assistant_id": assistantId]

        if let fid = fileId {
            payload["tool_resources"] = [
                "code_interpreter": ["file_ids": [fid]]
            ]
        }

        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let runId = json["id"] as? String {
                pollRun(threadId: threadId, runId: runId)
            } else {
                isLoading = false
            }
        }.resume()
    }

    private func pollRun(threadId: String, runId: String) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            var req = URLRequest(url: URL(string:"https://api.openai.com/v1/threads/\(threadId)/runs/\(runId)")!)
            req.httpMethod = "GET"
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? String else {
                    isLoading = false
                    return
                }

                if status == "completed" {
                    fetchMessages(threadId: threadId)
                } else if status == "failed" {
                    isLoading = false
                } else {
                    pollRun(threadId: threadId, runId: runId)
                }
            }.resume()
        }
    }

    private func fetchMessages(threadId: String) {
        var req = URLRequest(url: URL(string:"https://api.openai.com/v1/threads/\(threadId)/messages")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField:"Authorization")
        req.setValue("application/json", forHTTPHeaderField:"Content-Type")
        req.setValue("assistants=v2", forHTTPHeaderField:"OpenAI-Beta")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let d = data else {
                isLoading = false
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let msgs = json["data"] as? [[String: Any]],
                  let first = msgs.first,
                  let contentArr = first["content"] as? [[String: Any]],
                  let textObj = contentArr.first?["text"] as? [String: Any],
                  let value = textObj["value"] as? String else {
                isLoading = false
                return
            }

            DispatchQueue.main.async {
                messages.append(ChatMessage(sender: "assistant", content: value))
                isLoading = false
            }
        }.resume()
    }
}


#Preview {
    ChatView()
}
