import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import UIKit

// MARK: - SummaryView

struct SummaryView: View {
    var fileURL: URL?
    var selectedImage: Image?

    @Environment(\.presentationMode) private var presentationMode

    @State private var summaryText = ""
    @State private var insightText = ""
    @State private var isLoading = false
    @State private var threadId: String? = nil
    @State private var fileId: String? = nil
    @State private var navigateToChat = false

    // UI
    @State private var showReportsFolder = false
    @State private var lastSavedReportURL: URL? = nil
    @State private var saveMessage: String? = nil
    @State private var quickLookURL: URL? = nil
    @State private var showQuickLook = false

    // Your Assistant IDs
    private let summaryAssistantId = "asst_lYMPOqnXe86rZ2oPqe6N3bx2"
    private let insightAssistantId  = "asst_LIuWUGUi5ClNpJMuEAbYQsRs"

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(hex: "#FFFCF7").ignoresSafeArea()

                VStack(spacing: 16) {
                    // Top Bar
                    HStack {
                        Button(action: { presentationMode.wrappedValue.dismiss() }) {
                            Image(systemName: "chevron.left")
                                .resizable()
                                .frame(width: 15, height: 20)
                                .foregroundColor(Color(hex: "#00731D"))
                        }
                        Spacer()
                        HStack(spacing: 20) {
                            // Open the reports folder
                            Button(action: { showReportsFolder = true }) {
                                Image(systemName: "arrow.down.circle")
                                    .resizable().frame(width: 24, height: 24)
                                    .foregroundColor(Color(hex: "#00731D"))
                            }
                            NavigationLink(destination: KPIAnalysisView()) {
                                Image(systemName: "ellipsis.circle")
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(Color(hex: "#00731D"))
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    if let image = selectedImage {
                        image.resizable().scaledToFit()
                            .frame(height: 150)
                            .padding(.horizontal)
                    }

                    if isLoading { ProgressView("Analyzing...").padding() }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Summary")
                                .font(.title3).bold()
                                .foregroundColor(Color(hex: "#00731D"))

                            Text(summaryText).font(.body)

                            Divider()

                            Text("Key Insights")
                                .font(.title3).bold()
                                .foregroundColor(Color(hex: "#00731D"))

                            Text(insightText).font(.body)
                        }
                        .padding()
                    }

                    if let saveMessage = saveMessage {
                        Text(saveMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }

                    Spacer()

                    // Bottom: Download + Chat
                    HStack {
                        Button(action: {
                            let reportText = """
                            Summary:
                            \(summaryText)

                            Key Insights:
                            \(insightText)
                            """
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Report.txt")
                            do {
                                try reportText.write(to: tempURL, atomically: true, encoding: .utf8)
                                let picker = UIDocumentPickerViewController(forExporting: [tempURL])
                                picker.allowsMultipleSelection = false
                                UIApplication.shared.windows.first?.rootViewController?.present(picker, animated: true)
                            } catch {
                                print("❌ Failed to create report: \(error.localizedDescription)")
                            }
                        }) {
                            Text("Download Report")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "#00731D"))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                        }

                        .disabled(summaryText.isEmpty && insightText.isEmpty)

                        NavigationLink(
                            destination: ChatView(threadId: threadId, fileId: fileId),
                            isActive: $navigateToChat
                        ) {
                            Button(action: {
                                print("💬 Continue to Chat: threadId=\(threadId ?? "nil") fileId=\(fileId ?? "nil")")
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
        .onAppear { startAnalysis() }
        .sheet(isPresented: $showReportsFolder) {
            // Folder browser that *returns* the picked file URL
            FolderBrowser(startURL: reportsDirectoryURL()) { url in
                quickLookURL = url
                showQuickLook = true
            }
        }
        .sheet(isPresented: $showQuickLook) {
            if let url = quickLookURL {
                QuickLookPreview(url: url)
            }
        }
        
    }

    // MARK: - Download / Folder

    private func saveReportTapped() {
        do {
            let url = try saveReport(summary: summaryText, insights: insightText)
            lastSavedReportURL = url
            saveMessage = "Saved to: \(url.lastPathComponent) (AIReports)"
            print("✅ Report saved at \(url.path)")
        } catch {
            saveMessage = "Failed to save report: \(error.localizedDescription)"
            print("❌ Save report error: \(error.localizedDescription)")
        }
    }

    /// ~/Documents/AIReports (created if missing)
    private func reportsDirectoryURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let reports = docs.appendingPathComponent("AIReports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: reports.path) {
            try? FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        }
        return reports
    }

    /// Writes a .txt file that includes both sections and a timestamp.
    @discardableResult
    private func saveReport(summary: String, insights: String) throws -> URL {
        let ts = DateFormatter.reportTimestamp.string(from: Date())
        let filename = "Report-\(ts).txt"
        let fileURL = reportsDirectoryURL().appendingPathComponent(filename)

        var body = ""
        if !summary.isEmpty {
            body += "SUMMARY\n\n\(summary)\n\n"
        }
        if !insights.isEmpty {
            body += "KEY INSIGHTS\n\n\(insights)\n"
        }
        if body.isEmpty {
            body = "(No content)"
        }
        try body.data(using: .utf8)!.write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: - Flow (unchanged core; sequential runs to avoid active-run 400s)

    private func startAnalysis() {
        guard let apiKey = HTTPClient.shared.apiKey, !apiKey.isEmpty else {
            print("⚠️ OPENAI_API_KEY is missing. Add it to Info.plist.")
            summaryText = "Missing API key. Please set OPENAI_API_KEY."
            return
        }

        if let fileURL {
            let ext = fileURL.pathExtension.lowercased()
            let isImage = ["jpg","jpeg","png","heic","bmp","gif"].contains(ext)
            print("📂 onAppear: fileURL=\(fileURL.lastPathComponent) isImage=\(isImage)")
            analyze(fileURL: fileURL, isImage: isImage)
        } else if let image = selectedImage,
                  let downscaledData = image.asDownscaledJPEGData(maxDimension: 1600, quality: 0.85) {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            do {
                try downscaledData.write(to: tempURL)
                print("🖼️ onAppear: wrote downscaled image: \(tempURL.lastPathComponent)")
                analyze(fileURL: tempURL, isImage: true)
            } catch {
                print("❌ Failed to write temp image: \(error.localizedDescription)")
                summaryText = "❌ Failed to process image."
                insightText  = ""
            }
        } else {
            print("ℹ️ Nothing to analyze (no fileURL or selectedImage).")
        }
    }

    private func analyze(fileURL: URL, isImage: Bool) {
        isLoading = true
        summaryText = ""
        insightText  = ""

        HTTPClient.shared.uploadFile(fileURL: fileURL) { result in
            switch result {
            case .failure(let err):
                print("❌ uploadFile error: \(err.localizedDescription)")
                DispatchQueue.main.async {
                    self.summaryText = "❌ Upload failed."
                    self.isLoading = false
                }
            case .success(let fid):
                DispatchQueue.main.async { self.fileId = fid }
                print("✅ uploadFile OK: fileId=\(fid) — creating thread…")

                HTTPClient.shared.createThread { threadResult in
                    switch threadResult {
                    case .failure(let err):
                        print("❌ createThread error: \(err.localizedDescription)")
                        DispatchQueue.main.async {
                            self.summaryText = "❌ Thread creation failed."
                            self.isLoading = false
                        }
                    case .success(let tid):
                        DispatchQueue.main.async { self.threadId = tid }
                        print("✅ thread created: \(tid)")

                        runSummaryThenInsights(threadId: tid, fileId: fid, isImage: isImage)
                    }
                }
            }
        }
    }

    private func runSummaryThenInsights(threadId: String, fileId: String, isImage: Bool) {
        addMessageOnce(threadId: threadId, isImage: isImage, fileId: fileId) { addMsgResult in
            switch addMsgResult {
            case .failure(let err):
                print("❌ addMessageOnce error: \(err.localizedDescription)")
                DispatchQueue.main.async {
                    self.summaryText = "❌ Could not add message."
                    self.isLoading = false
                }
            case .success:
                // SUMMARY
                let summaryTools: [String: Any]? = isImage ? nil : ["code_interpreter": ["file_ids": [fileId]]]
                HTTPClient.shared.createRun(threadId: threadId, assistantId: summaryAssistantId, toolResources: summaryTools) { runRes in
                    switch runRes {
                    case .failure(let err):
                        print("❌ createRun (summary) error: \(err.localizedDescription)")
                        DispatchQueue.main.async { self.summaryText = "❌ Run failed." }
                        self.startInsights(threadId: threadId, fileId: fileId, isImage: isImage)
                    case .success(let runId):
                        HTTPClient.shared.pollRunWithBackoff(threadId: threadId, runId: runId, maxAttempts: 10, initialDelay: 2.0) { pollRes in
                            switch pollRes {
                            case .failure(let err):
                                print("❌ poll (summary) error: \(err.localizedDescription)")
                                DispatchQueue.main.async { self.summaryText = "❌ Run failed." }
                            case .success:
                                HTTPClient.shared.fetchLatestAssistantText(threadId: threadId) { textRes in
                                    switch textRes {
                                    case .failure(let err):
                                        print("❌ fetchLatestAssistantText (summary) error: \(err.localizedDescription)")
                                        DispatchQueue.main.async { self.summaryText = "❌ Failed to parse response." }
                                    case .success(let text):
                                        DispatchQueue.main.async { self.summaryText = text }
                                    }
                                    self.startInsights(threadId: threadId, fileId: fileId, isImage: isImage)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func startInsights(threadId: String, fileId: String, isImage: Bool) {
        let insightTools: [String: Any]? = isImage ? nil : ["code_interpreter": ["file_ids": [fileId]]]
        HTTPClient.shared.createRun(threadId: threadId, assistantId: insightAssistantId, toolResources: insightTools) { runRes in
            switch runRes {
            case .failure(let err):
                print("❌ createRun (insights) error: \(err.localizedDescription)")
                DispatchQueue.main.async {
                    self.insightText = "❌ Run failed."
                    self.isLoading = false
                }
            case .success(let runId):
                HTTPClient.shared.pollRunWithBackoff(threadId: threadId, runId: runId, maxAttempts: 10, initialDelay: 2.0) { pollRes in
                    switch pollRes {
                    case .failure(let err):
                        print("❌ poll (insights) error: \(err.localizedDescription)")
                        DispatchQueue.main.async {
                            self.insightText = "❌ Run failed."
                            self.isLoading = false
                        }
                    case .success:
                        HTTPClient.shared.fetchLatestAssistantText(threadId: threadId) { textRes in
                            DispatchQueue.main.async {
                                switch textRes {
                                case .failure(let err):
                                    print("❌ fetchLatestAssistantText (insights) error: \(err.localizedDescription)")
                                    self.insightText = "❌ Failed to parse response."
                                case .success(let text):
                                    self.insightText = text
                                }
                                self.isLoading = false
                            }
                        }
                    }
                }
            }
        }
    }

    private func addMessageOnce(threadId: String, isImage: Bool, fileId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let content: [[String: Any]]
        if isImage {
            content = [
                ["type": "text", "text": "Analyze this dashboard image for KPIs and trends, then summarize."],
                ["type": "image_file", "image_file": ["file_id": fileId]]
            ]
        } else {
            content = [
                ["type": "text", "text": "This spreadsheet contains KPIs. Analyze trends and provide a short summary."] // no file_ids here
            ]
        }
        HTTPClient.shared.addMessage(threadId: threadId, content: content, completion: completion)
    }
}

//// MARK: - Folder Browser (opens a directory in Files UI)
//
//struct FolderBrowser: UIViewControllerRepresentable {
//    let startURL: URL
//
//    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
//        // Open-anything type; start in our folder
//        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
//        picker.directoryURL = startURL
//        picker.allowsMultipleSelection = false
//        return picker
//    }
//    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
//}

// MARK: - HTTPClient (same as your latest version)

final class HTTPClient {
    static let shared = HTTPClient()
    let apiKey: String? = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String
    private let base = URL(string: "https://api.openai.com/v1")!
    private let betaHeader = "assistants=v2"

    private func makeRequest(path: String, method: String, json: Any? = nil, headers: [String: String] = [:]) -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        if let key = apiKey { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        req.setValue(betaHeader, forHTTPHeaderField: "OpenAI-Beta")
        if json != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if let json = json { req.httpBody = try? JSONSerialization.data(withJSONObject: json) }
        return req
    }

    private func checkHTTP(_ response: URLResponse?, data: Data?) -> Error? {
        guard let http = response as? HTTPURLResponse else {
            return NSError(domain: "HTTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTPURLResponse"])
        }
        if (200...299).contains(http.statusCode) { return nil }
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
        print("⚠️ HTTP \(http.statusCode) — \(body)")
        return NSError(domain: "HTTPClient", code: http.statusCode,
                       userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
    }

    func uploadFile(fileURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let boundary = UUID().uuidString
        var req = URLRequest(url: base.appendingPathComponent("files"))
        req.httpMethod = "POST"
        if let key = apiKey { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let fileData = try? Data(contentsOf: fileURL) else {
            return completion(.failure(NSError(domain: "HTTPClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot read file data"])))
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\nassistants\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        print("📤 uploadFile: \(fileURL.lastPathComponent) (\(fileData.count) bytes)")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { return completion(.failure(err)) }
            if let e = self.checkHTTP(resp, data: data) { return completion(.failure(e)) }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fileId = json["id"] as? String else {
                return completion(.failure(NSError(domain: "HTTPClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Upload parse error"])))
            }
            print("✅ uploadFile -> fileId: \(fileId)")
            completion(.success(fileId))
        }.resume()
    }

    func createThread(completion: @escaping (Result<String, Error>) -> Void) {
        let req = makeRequest(path: "threads", method: "POST", json: [:])
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { return completion(.failure(err)) }
            if let e = self.checkHTTP(resp, data: data) { return completion(.failure(e)) }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tid = json["id"] as? String else {
                return completion(.failure(NSError(domain: "HTTPClient", code: -4, userInfo: [NSLocalizedDescriptionKey: "Thread parse error"])))
            }
            print("✅ createThread -> \(tid)")
            completion(.success(tid))
        }.resume()
    }

    func addMessage(threadId: String,
                    content: [[String: Any]],
                    completion: @escaping (Result<Void, Error>) -> Void) {
        let json: [String: Any] = ["role": "user", "content": content]
        let req = makeRequest(path: "threads/\(threadId)/messages", method: "POST", json: json)

        if let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let s = String(data: pretty, encoding: .utf8) {
            print("📝 addMessage payload:\n\(s)")
        }

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { return completion(.failure(err)) }
            if let e = self.checkHTTP(resp, data: data) { return completion(.failure(e)) }
            completion(.success(()))
        }.resume()
    }

    func createRun(threadId: String,
                   assistantId: String,
                   toolResources: [String: Any]?,
                   completion: @escaping (Result<String, Error>) -> Void) {
        var json: [String: Any] = ["assistant_id": assistantId]
        if let tr = toolResources { json["tool_resources"] = tr }

        let req = makeRequest(path: "threads/\(threadId)/runs", method: "POST", json: json)

        if let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let s = String(data: pretty, encoding: .utf8) {
            print("🧾 createRun payload:\n\(s)")
        }

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { return completion(.failure(err)) }
            if let e = self.checkHTTP(resp, data: data) { return completion(.failure(e)) }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rid = json["id"] as? String else {
                return completion(.failure(NSError(domain: "HTTPClient", code: -6, userInfo: [NSLocalizedDescriptionKey: "Run parse error"])))
            }
            print("✅ createRun -> runId: \(rid)")
            completion(.success(rid))
        }.resume()
    }

    func pollRunWithBackoff(threadId: String,
                            runId: String,
                            maxAttempts: Int,
                            initialDelay: TimeInterval,
                            completion: @escaping (Result<Void, Error>) -> Void) {
        func attempt(_ n: Int, delay: TimeInterval) {
            guard n <= maxAttempts else {
                return completion(.failure(NSError(domain: "HTTPClient", code: -7, userInfo: [NSLocalizedDescriptionKey: "Polling timed out"])))
            }

            let req = self.makeRequest(path: "threads/\(threadId)/runs/\(runId)", method: "GET")
            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err { return completion(.failure(err)) }
                if let e = self.checkHTTP(resp, data: data) { return completion(.failure(e)) }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? String else {
                    return completion(.failure(NSError(domain: "HTTPClient", code: -8, userInfo: [NSLocalizedDescriptionKey: "Poll parse error"])))
                }

                print("📥 poll(\(n)) status=\(status)")
                switch status {
                case "completed": completion(.success(()))
                case "failed":
                    let msg = ((json["last_error"] as? [String: Any])?["message"] as? String) ?? "Run failed"
                    completion(.failure(NSError(domain: "HTTPClient", code: -9, userInfo: [NSLocalizedDescriptionKey: msg])))
                case "queued", "in_progress", "requires_action":
                    let nextDelay = min(delay * 1.6, 12.0)
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        attempt(n + 1, delay: nextDelay)
                    }
                default:
                    completion(.failure(NSError(domain: "HTTPClient", code: -10, userInfo: [NSLocalizedDescriptionKey: "Unknown run status: \(status)"])))
                }
            }.resume()
        }
        attempt(1, delay: initialDelay)
    }

    func fetchLatestAssistantText(threadId: String,
                                  completion: @escaping (Result<String, Error>) -> Void) {
        let req = makeRequest(path: "threads/\(threadId)/messages", method: "GET")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { return completion(.failure(err)) }
            if let e = self.checkHTTP(resp, data: data) { return completion(.failure(e)) }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msgs = json["data"] as? [[String: Any]] else {
                return completion(.failure(NSError(domain: "HTTPClient", code: -11, userInfo: [NSLocalizedDescriptionKey: "Messages parse error"])))
            }

            let sorted = msgs.sorted { ($0["created_at"] as? Int ?? 0) > ($1["created_at"] as? Int ?? 0) }
            if let assistantMsg = sorted.first(where: { ($0["role"] as? String) == "assistant" }),
               let contentArr = assistantMsg["content"] as? [[String: Any]] {
                let texts = contentArr.compactMap { item -> String? in
                    guard let textObj = item["text"] as? [String: Any],
                          let value = textObj["value"] as? String else { return nil }
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let joined = texts.joined(separator: "\n\n")
                if !joined.isEmpty { return completion(.success(joined)) }
            }
            completion(.failure(NSError(domain: "HTTPClient", code: -12, userInfo: [NSLocalizedDescriptionKey: "No assistant text found"])))
        }.resume()
    }
}

// MARK: - Utilities

extension Image {
    func asDownscaledJPEGData(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let controller = UIHostingController(rootView: self.resizable().scaledToFit())
        let view = controller.view
        let size = CGSize(width: maxDimension, height: maxDimension)
        view?.bounds = CGRect(origin: .zero, size: size)
        view?.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { _ in
            view?.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        let scaled = img.downscaled(toMaxDimension: maxDimension)
        return scaled.jpegData(compressionQuality: quality)
    }
}

extension UIImage {
    func downscaled(toMaxDimension maxDim: CGFloat) -> UIImage {
        let w = size.width, h = size.height
        let scale = Swift.min(1.0, maxDim / Swift.max(w, h))
        guard scale < 1.0 else { return self }
        let newSize = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

private extension DateFormatter {
    static let reportTimestamp: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df
    }()
}

#Preview {
    SummaryView()
}
