import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct SummaryView: View {
    var fileURL: URL?
    var selectedImage: Image?

    @Environment(\.presentationMode) var presentationMode

    @State private var summaryText = ""
    @State private var insightText = ""
    @State private var isLoading = false
    @State private var threadId: String? = nil
    @State private var fileId: String? = nil
    @State private var navigateToChat = false

    let summaryAssistantId = "asst_lYMPOqnXe86rZ2oPqe6N3bx2"
    let insightAssistantId = "asst_LIuWUGUi5ClNpJMuEAbYQsRs"
    let apiKey = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color("AppBackground").ignoresSafeArea()

                VStack(spacing: 16) {
                    // Top Bar
                    HStack {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "chevron.left")
                                .resizable()
                                .frame(width: 15, height: 20)
                                .foregroundColor(Color(hex: "#00731D"))
                        }
                        Spacer()
                        HStack(spacing: 20) {
                            Button(action: {}) {
                                Image(systemName: "arrow.down.circle")
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(Color(hex: "#00731D"))
                            }
                            Button(action: {}) {
                                Image(systemName: "ellipsis.circle")
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(Color(hex: "#00731D"))
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    // Image Preview (if exists)
                    if let image = selectedImage {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                            .padding(.horizontal)
                    }

                    if isLoading {
                        ProgressView("Analyzing...").padding()
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Summary")
                                .font(.title3).bold()
                                .foregroundColor(Color(hex: "#00731D"))

                            Text(summaryText)
                                .font(.system(.body, design: .default))

                            Divider()

                            Text("Key Insights")
                                .font(.title3).bold()
                                .foregroundColor(Color(hex: "#00731D"))

                            Text(insightText)
                                .font(.system(.body, design: .default))
                        }
                        .padding()
                    }

                    Spacer()

                    // Bottom Row: Download + Chat
                    HStack {
                        Button(action: {
                            // TODO: implement download report
                        }) {
                            Text("Download Report")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "#00731D"))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                        }

                        NavigationLink(destination: ChatView(threadId: threadId, fileId: fileId), isActive: $navigateToChat) {
                            Button(action: {
                                navigateToChat = true
                            }) {
                                Image(systemName: "ellipses.bubble")
                                    .font(.system(size: 22, weight: .semibold))
                                    .padding()
                                    .background((threadId != nil && fileId != nil) ? Color(hex: "#00731D") : Color.gray)
                                    .foregroundColor(.white)
                                    .clipShape(Circle())
                            }
                            .disabled(threadId == nil || fileId == nil)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if let fileURL = fileURL {
                let ext = fileURL.pathExtension.lowercased()
                let isImage = ["jpg", "jpeg", "png", "heic", "bmp", "gif"].contains(ext)
                analyzeWithBothAssistants(fileURL: fileURL, isImage: isImage)
            } else if let image = selectedImage,
                      let uiImage = image.asUIImage(),
                      let data = uiImage.jpegData(compressionQuality: 0.8) {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                do {
                    try data.write(to: tempURL)
                    analyzeWithBothAssistants(fileURL: tempURL, isImage: true)
                } catch {
                    summaryText = "❌ Failed to process image."
                    insightText = ""
                }
            }
        }
    }

    func analyzeWithBothAssistants(fileURL: URL, isImage: Bool) {
        isLoading = true
        summaryText = ""
        insightText = ""

        uploadFile(fileURL: fileURL) { uploadedFileId in
            DispatchQueue.main.async {
                if let uploadedFileId = uploadedFileId {
                    self.fileId = uploadedFileId
                    createThreadAndRun(fileId: uploadedFileId, isImage: isImage)
                } else {
                    summaryText = "❌ Upload failed."
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
            completion(nil)
            return
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
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fileId = json["id"] as? String else {
                completion(nil)
                return
            }
            completion(fileId)
        }.resume()
    }

    func createThreadAndRun(fileId: String, isImage: Bool) {
        var threadReq = URLRequest(url: URL(string: "https://api.openai.com/v1/threads")!)
        threadReq.httpMethod = "POST"
        threadReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        threadReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        threadReq.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        threadReq.httpBody = Data("{}".utf8)

        URLSession.shared.dataTask(with: threadReq) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tid = json["id"] as? String else {
                summaryText = "❌ Thread creation failed."
                isLoading = false
                return
            }

            DispatchQueue.main.async {
                self.threadId = tid
            }

            // Run assistant 1
            analyze(fileId: fileId, isImage: isImage, assistantId: summaryAssistantId, threadId: tid) { response in
                DispatchQueue.main.async {
                    self.summaryText = response
                }
            }

            // Run assistant 2
            analyze(fileId: fileId, isImage: isImage, assistantId: insightAssistantId, threadId: tid) { response in
                DispatchQueue.main.async {
                    self.insightText = response
                    self.isLoading = false
                }
            }
        }.resume()
    }

    func analyze(fileId: String, isImage: Bool, assistantId: String, threadId: String, completion: @escaping (String) -> Void) {
        var msgReq = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages")!)
        msgReq.httpMethod = "POST"
        msgReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        msgReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        msgReq.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

        let payload: [String: Any] = [
            "role": "user",
            "content": [["type": "text", "text": "Analyze this file."]],
            "file_ids": [fileId]
        ]

        msgReq.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: msgReq) { _, _, _ in
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

            runReq.httpBody = try? JSONSerialization.data(withJSONObject: runPayload)

            URLSession.shared.dataTask(with: runReq) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let runId = json["id"] as? String else {
                    completion("❌ Run failed.")
                    return
                }
                pollResult(threadId: threadId, runId: runId, completion: completion)
            }.resume()
        }.resume()
    }

    func pollResult(threadId: String, runId: String, completion: @escaping (String) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs/\(runId)")!)
            req.httpMethod = "GET"
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? String else {
                    completion("❌ Poll failed.")
                    return
                }

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
                completion("❌ Failed to parse response.")
                return
            }
            completion(value)
        }.resume()
    }
}

// Helper to convert Image to UIImage
extension Image {
    func asUIImage() -> UIImage? {
        let controller = UIHostingController(rootView: self.resizable())
        let view = controller.view
        let targetSize = CGSize(width: 300, height: 300)
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}





#Preview {
    SummaryView(fileURL: nil)
}
