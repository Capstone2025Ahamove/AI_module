//  ContentView.swift
//  Capstone AI module

import SwiftUI
import PhotosUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let sender: String // "user" or "assistant"
    let content: String
}

struct ContentView: View {
    @State private var resultText = ""
    @State private var showImagePicker = false
    @State private var isLoading = false
    @State private var threadId: String? = UserDefaults.standard.string(forKey: "threadId")
    @State private var userMessage: String = ""
    @State private var uploadedFileId: String? = nil
    @State private var messages: [ChatMessage] = []

    let assistantId = "asst_p0ajNzziydcju4E9O37JLWtt"
    let apiKey = ""

    var body: some View {
        ScrollViewReader { scrollProxy in
            ZStack(alignment: .bottomTrailing) {
                VStack {
                    Button("Select Image from Photo Library") {
                        showImagePicker = true
                    }
                    .padding()
                    .disabled(isLoading)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { msg in
                                HStack {
                                    if msg.sender == "user" {
                                        Spacer()
                                        Text(msg.content)
                                            .padding()
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(10)
                                            .frame(maxWidth: 250, alignment: .trailing)
                                    } else {
                                        Text(msg.content)
                                            .padding()
                                            .background(Color.gray.opacity(0.2))
                                            .cornerRadius(10)
                                            .frame(maxWidth: 250, alignment: .leading)
                                        Spacer()
                                    }
                                }
                                .id(msg.id)
                            }
                        }
                        .padding()
                    }

                    Spacer()

                    VStack(spacing: 8) {
                        HStack {
                            TextField("Continue conversation...", text: $userMessage)
                                .textFieldStyle(RoundedBorderTextFieldStyle())

                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.leading, 8)
                            }
                        }
                        .padding(.horizontal)

                        Button("Send Message") {
                            print("🔵 Sending message: \(userMessage)")
                            print("📎 Current uploadedFileId: \(uploadedFileId ?? "nil")")
                            print("🧵 Using threadId: \(threadId ?? "nil")")
                            if let tid = threadId, !userMessage.isEmpty {
                                let newMessage = ChatMessage(sender: "user", content: userMessage)
                                messages.append(newMessage)
                                sendChatMessage(threadId: tid, content: userMessage)
                                userMessage = ""

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    scrollProxy.scrollTo(newMessage.id, anchor: .bottom)
                                }
                            }
                        }
                        .disabled(isLoading || threadId == nil || userMessage.isEmpty)
                        .padding(.bottom)
                    }
                    .background(Color(UIColor.systemBackground))
                }
            }
            // ✅ Attach .sheet to the ZStack, not the VStack
            .sheet(isPresented: $showImagePicker) {
                PhotoPicker { image in
                    saveTempImageAndHandle(image)
                }
            }
            // ✅ Handle auto-scroll when new message arrives
            .onChange(of: messages.count) { _ in
                if let last = messages.last {
                    DispatchQueue.main.async {
                        scrollProxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }


    
    func sendChatMessage(threadId: String, content: String) {
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

            DispatchQueue.main.async {
                isLoading = true
            }

            URLSession.shared.dataTask(with: req) { data, _, _ in
                runAssistant(threadId: threadId)
            }.resume()
        }
    func saveTempImageAndHandle(_ image: UIImage) {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("selected.jpg")
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: temp)
            uploadImage(temp)
        } else {
            resultText = "Failed to convert image."
        }
    }

    func uploadImage(_ url: URL) {
        isLoading = true
        DispatchQueue.main.async {
            resultText = "Image received. Analyzing..."
        }
        uploadFileToOpenAI(fileURL: url)
    }

    func uploadFileToOpenAI(fileURL: URL) {
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/files")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let fileData = try? Data(contentsOf: fileURL) else {
            return DispatchQueue.main.async {
                resultText = "Failed to read file."
                isLoading = false
            }
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\nassistants\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let d = data,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let fid = json["id"] as? String else {
                return DispatchQueue.main.async {
                    resultText = "Upload failed."
                    isLoading = false
                }
            }

            uploadedFileId = fid

            DispatchQueue.main.async {
                createThread(with: fid)
            }
        }.resume()
    }

    func createThread(with fileId: String) {
        var req = URLRequest(url: URL(string:"https://api.openai.com/v1/threads")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField:"Authorization")
        req.setValue("application/json", forHTTPHeaderField:"Content-Type")
        req.setValue("assistants=v2", forHTTPHeaderField:"OpenAI-Beta")
        req.httpBody = Data("{}".utf8)

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let d = data,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let tid = json["id"] as? String else {
                DispatchQueue.main.async {
                    resultText = "Failed to start thread."
                    isLoading = false
                }
                return
            }
            DispatchQueue.main.async {
                threadId = tid
                UserDefaults.standard.set(tid, forKey: "threadId")
            }
            addMessage(threadId: tid, fileId: fileId)
        }.resume()
    }

    func addMessage(threadId: String, fileId: String) {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

        // ✅ Use image_file content block, not file_ids
        let payload: [String: Any] = [
            "role": "user",
            "content": [
                [
                    "type": "image_file",
                    "image_file": ["file_id": fileId]
                ]
            ]
        ]

        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        DispatchQueue.main.async {
            resultText = "🖼️ Image uploaded. Analyzing..."
            isLoading = true
        }

        URLSession.shared.dataTask(with: req) { _, _, _ in
            runAssistant(threadId: threadId)
        }.resume()
    }


    func runAssistant(threadId: String) {
        var req = URLRequest(url: URL(string:"https://api.openai.com/v1/threads/\(threadId)/runs")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField:"Authorization")
        req.setValue("application/json", forHTTPHeaderField:"Content-Type")
        req.setValue("assistants=v2", forHTTPHeaderField:"OpenAI-Beta")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["assistant_id":assistantId])

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let d = data,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let runId = json["id"] as? String else {
                DispatchQueue.main.async {
                    resultText = "Run failed."
                    isLoading = false
                }
                return
            }
            pollRun(threadId: threadId, runId: runId)
        }.resume()
    }

    func pollRun(threadId: String, runId: String) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            var req = URLRequest(url: URL(string:"https://api.openai.com/v1/threads/\(threadId)/runs/\(runId)")!)
            req.httpMethod = "GET"
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField:"Authorization")
            req.setValue("assistants=v2", forHTTPHeaderField:"OpenAI-Beta")

            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let d = data,
                      let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let status = json["status"] as? String else {
                    DispatchQueue.main.async {
                        resultText = "Checking status failed."
                        isLoading = false
                    }
                    return
                }
                if status == "completed" {
                    fetchMessages(threadId: threadId)
                } else {
                    pollRun(threadId: threadId, runId: runId)
                }
            }.resume()
        }
    }

    func fetchMessages(threadId: String) {
        var req = URLRequest(url: URL(string:"https://api.openai.com/v1/threads/\(threadId)/messages")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField:"Authorization")
        req.setValue("application/json", forHTTPHeaderField:"Content-Type")
        req.setValue("assistants=v2", forHTTPHeaderField:"OpenAI-Beta")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let d = data,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let msgs = json["data"] as? [[String: Any]],
                  let first = msgs.first,
                  let contentArr = first["content"] as? [[String: Any]],
                  let textObj = contentArr.first?["text"] as? [String:Any],
                  let value = textObj["value"] as? String else {
                return DispatchQueue.main.async {
                    resultText = "Failed to fetch message."
                    isLoading = false
                }
            }
            DispatchQueue.main.async {
                messages.append(ChatMessage(sender: "assistant", content: value))
                isLoading = false
                userMessage = ""
            }
        }.resume()
    }
}

struct PhotoPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration()
        cfg.selectionLimit = 1
        cfg.filter = .images
        let picker = PHPickerViewController(configuration: cfg)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onPick: (UIImage) -> Void
        init(onPick:@escaping(UIImage)->Void){ self.onPick=onPick }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated:true)
            guard let item = results.first?.itemProvider,
                  item.canLoadObject(ofClass:UIImage.self) else { return }
            item.loadObject(ofClass: UIImage.self) { obj, _ in
                if let img = obj as? UIImage { DispatchQueue.main.async { self.onPick(img) }}
            }
        }
    }
}

#Preview {
    ContentView()
}
