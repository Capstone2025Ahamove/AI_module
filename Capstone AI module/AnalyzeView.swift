import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct AnalyzeView: View {
    @State private var summaryText = ""
    @State private var insightText = ""
    @State private var isLoading = false
    @State private var showFilePicker = false
    @State private var selectedPhoto: PhotosPickerItem?

    let summaryAssistantId = "asst_lYMPOqnXe86rZ2oPqe6N3bx2"
    let insightAssistantId = "asst_LIuWUGUi5ClNpJMuEAbYQsRs"
    let apiKey = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Upload a dashboard image or spreadsheet")
                .font(.headline)

            HStack(spacing: 16) {
                Button("Pick Document/Spreadsheet") {
                    showFilePicker = true
                }.disabled(isLoading)

                PhotosPicker("Pick Image", selection: $selectedPhoto, matching: .images)
                    .disabled(isLoading)
            }

            if isLoading {
                ProgressView("Analyzing...").padding()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("📄 Summary")
                        .font(.title3).bold()
                    Text(summaryText)
                        .font(.system(.body, design: .monospaced))

                    Divider()

                    Text("💡 Key Insights & Actions")
                        .font(.title3).bold()
                    Text(insightText)
                        .font(.system(.body, design: .monospaced))
                }.padding()
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .spreadsheet, .data, .png, .jpeg, .image],
            allowsMultipleSelection: false
        ) { result in
            handlePickerResult(result: result)
        }
        .onChange(of: selectedPhoto) { newItem in
            if let item = newItem {
                loadAndAnalyzePhoto(item)
            }
        }
    }

    func handlePickerResult(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let fileURL = urls.first {
                let ext = fileURL.pathExtension.lowercased()
                let isImage = ["jpg", "jpeg", "png", "heic", "bmp", "gif"].contains(ext)
                analyzeWithBothAssistants(fileURL: fileURL, isImage: isImage)
            }
        case .failure(let error):
            summaryText = "❌ File picker failed: \(error.localizedDescription)"
            insightText = ""
        }
    }

    func loadAndAnalyzePhoto(_ item: PhotosPickerItem) {
        isLoading = true
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                    try data.write(to: tempURL)
                    analyzeWithBothAssistants(fileURL: tempURL, isImage: true)
                }
            } catch {
                summaryText = "❌ Failed to load image."
                insightText = ""
                isLoading = false
            }
        }
    }

    func analyzeWithBothAssistants(fileURL: URL, isImage: Bool) {
        isLoading = true
        summaryText = ""
        insightText = ""

        uploadFile(fileURL: fileURL) { fileId in
            guard let fileId = fileId else {
                summaryText = "❌ Upload failed."
                isLoading = false
                return
            }

            analyze(fileId: fileId, isImage: isImage, assistantId: summaryAssistantId) { response in
                DispatchQueue.main.async {
                    summaryText = response
                }
            }

            analyze(fileId: fileId, isImage: isImage, assistantId: insightAssistantId) { response in
                DispatchQueue.main.async {
                    insightText = response
                    isLoading = false
                }
            }
        }
    }

    func uploadFile(fileURL: URL, completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/files")!)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let fileData = try? Data(contentsOf: fileURL) else {
            return completion(nil)
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
            if let data = data,
               let raw = String(data: data, encoding: .utf8) {
                print("📁 Upload response: \(raw)")
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fileId = json["id"] as? String else {
                print("❌ Upload failed or file ID not found")
                completion(nil)
                return
            }
            print("✅ File uploaded with ID: \(fileId)")
            completion(fileId)
        }.resume()
    }

    func analyze(fileId: String, isImage: Bool, assistantId: String, completion: @escaping (String) -> Void) {
        print("🧵 Creating thread...")
        var threadReq = URLRequest(url: URL(string: "https://api.openai.com/v1/threads")!)
        threadReq.httpMethod = "POST"
        threadReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        threadReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        threadReq.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        threadReq.httpBody = Data("{}".utf8)

        URLSession.shared.dataTask(with: threadReq) { data, _, _ in
            guard let data = data else {
                print("❌ No data from thread creation")
                completion("❌ Thread creation failed.")
                return
            }

            if let raw = String(data: data, encoding: .utf8) {
                print("🔹 Thread response: \(raw)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let threadId = json["id"] as? String else {
                print("❌ Failed to parse thread ID")
                completion("❌ Thread creation failed.")
                return
            }

            print("✅ Created threadId: \(threadId)")

            var msgReq = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages")!)
            msgReq.httpMethod = "POST"
            msgReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            msgReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            msgReq.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
            msgReq.httpBody = try? JSONSerialization.data(withJSONObject: [
                "role": "user",
                "content": [["type": "text", "text": "Analyze this file."]],
                "file_ids": [fileId]
            ])

            URLSession.shared.dataTask(with: msgReq) { data, _, _ in
                if let data = data, let raw = String(data: data, encoding: .utf8) {
                    print("📨 Message response: \(raw)")
                }

                var runReq = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs")!)
                runReq.httpMethod = "POST"
                runReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                runReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                runReq.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

                var runPayload: [String: Any] = ["assistant_id": assistantId]
                if !isImage {
                    runPayload["tool_resources"] = [
                        "code_interpreter": ["file_ids": [fileId]]
                    ]
                }

                if let jsonData = try? JSONSerialization.data(withJSONObject: runPayload, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("🧾 Run payload: \(jsonString)")
                }

                runReq.httpBody = try? JSONSerialization.data(withJSONObject: runPayload)

                URLSession.shared.dataTask(with: runReq) { data, _, _ in
                    if let data = data, let raw = String(data: data, encoding: .utf8) {
                        print("🔹 Run response: \(raw)")
                    }

                    guard let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let runId = json["id"] as? String else {
                        print("❌ Failed to parse run ID")
                        completion("❌ Run failed.")
                        return
                    }

                    print("✅ Run started with runId: \(runId)")
                    pollResult(threadId: threadId, runId: runId, completion: completion)
                }.resume()
            }.resume()
        }.resume()
    }

    func pollResult(threadId: String, runId: String, completion: @escaping (String) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            print("📊 Polling run status...")
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs/\(runId)")!)
            req.httpMethod = "GET"
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? String else {
                    print("❌ Poll failed.")
                    completion("❌ Poll failed.")
                    return
                }

                print("📥 Status response: \(status)")

                if status == "completed" {
                    fetchOutput(threadId: threadId, completion: completion)
                } else if status == "failed" {
                    completion("❌ Analysis failed.")
                } else {
                    pollResult(threadId: threadId, runId: runId, completion: completion)
                }
            }.resume()
        }
    }

    func fetchOutput(threadId: String, completion: @escaping (String) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msgs = json["data"] as? [[String: Any]],
                  let first = msgs.first,
                  let contentArr = first["content"] as? [[String: Any]],
                  let textObj = contentArr.first?["text"] as? [String: Any],
                  let value = textObj["value"] as? String else {
                print("❌ Failed to parse response.")
                completion("❌ Failed to parse response.")
                return
            }
            print("✅ Final Output: \(value)")
            completion(value)
        }.resume()
    }
}
