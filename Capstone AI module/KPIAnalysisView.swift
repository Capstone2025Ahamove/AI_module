//
//  KPIAnalysisView.swift
//  Capstone AI module
//
//  Created by Andy L on 7/8/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation
import UIKit

struct KPIAnalysisView: View {
    // UI state
    @Environment(\.presentationMode) private var presentationMode
    @State private var fileURL: URL?
    @State private var isLoading = false
    @State private var predictionText = ""
    @State private var selectedDepartment = "Marketing"
    @State private var showFilePicker = false

    // Export (save) sheet
    @State private var exportURL: URL?
    @State private var showExportPicker = false

    // NEW: folder browser like SummaryView
    @State private var showReportsFolder = false
    @State private var quickLookURL: URL? = nil
    @State private var showQuickLook = false


    private let departments = ["Marketing", "Sales", "Tech", "Product", "Finance", "Operations", "Customer Support"]

    // Assistant ID
    private let kpiAssistantId = "asst_i0QIqjmFRA8xSFHuEGmU6PfI"

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(hex: "#FFFCF7").ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    // Top bar
                    HStack {
                        Button { presentationMode.wrappedValue.dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .resizable().frame(width: 15, height: 20)
                                .foregroundColor(Color(hex: "#00731D"))
                        }
                        Spacer()
                        HStack(spacing: 20) {
                            // Open our app's KPIReports folder in Files-style browser
                            Button(action: {
                                ensureKPIReportsDirectoryExists()
                                showReportsFolder = true
                            }) {
                                Image(systemName: "arrow.down.circle")
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(Color(hex: "#00731D"))
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    // Title
                    Text("KPI Prediction")
                        .font(.largeTitle).bold()
                        .foregroundColor(Color(hex: "#00731D"))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal)

                    // Subtitle
                    Text("Forecast KPI performance\nbased on historical data")
                        .multilineTextAlignment(.center)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(hex: "#00731D"))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)

                    // Controls row (picker + choose file)
                    HStack(spacing: 12) {
                        // Department picker styled like a capsule with green border
                        Menu {
                            Picker("", selection: $selectedDepartment) {
                                ForEach(departments, id: \.self) { Text($0) }
                            }
                        } label: {
                            HStack {
                                Text(selectedDepartment)
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(Color(hex: "#00731D"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "#00731D"), lineWidth: 2)
                            )
                        }
                        .disabled(isLoading)

                        Button {
                            showFilePicker = true
                        } label: {
                            Text("KPI CSV file")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(hex: "#00731D"))
                                .cornerRadius(16)
                        }
                        .disabled(isLoading)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)

                    if let fileURL {
                        Text(fileURL.lastPathComponent)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }

                    if isLoading {
                        ProgressView("Analyzing with GPT…")
                            .padding(.horizontal)
                    }

                    // Result container
                    ScrollView {
                        Text(predictionText.isEmpty ? " " : predictionText)
                            .font(.system(.body))
                            .foregroundColor(.black)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(hex: "#00731D").opacity(0.25), lineWidth: 1)
                            )
                            .padding(.horizontal)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }

                    // Bottom download button
                    Button(action: exportReport) {
                        Text("Download Report")
                            .font(.system(size: 22, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: "#00731D"))
                            .foregroundColor(.white)
                            .cornerRadius(22)
                            .padding(.horizontal)
                    }
                    .disabled(predictionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer(minLength: 10)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        // File importer for CSV
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let selected = urls.first {
                    fileURL = selected
                    sendToGPT()
                }
            case .failure(let error):
                predictionText = "❌ File import error: \(error.localizedDescription)"
            }
        }
        // Export picker
        .sheet(isPresented: $showExportPicker) {
            if let exportURL {
                DocumentExporter(url: exportURL)
            }
        }
        // Folder browser (Files-like) for KPIReports
        .sheet(isPresented: $showReportsFolder) {
            // Folder browser that *returns* the picked file URL
            FolderBrowser(startURL: kpiReportsDirectoryURL()) { url in
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

    // MARK: - Actions

    private func exportReport() {
        // Compose text body
        let body = predictionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        // Write to a temp file, then present UIDocumentPicker in export mode
        let ts = DateFormatter.reportTimestamp.string(from: Date())
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("KPI_Prediction_\(ts).txt")
        do {
            try body.data(using: .utf8)!.write(to: tmp, options: .atomic)
            exportURL = tmp
            showExportPicker = true
        } catch {
            print("❌ Failed to create export file: \(error.localizedDescription)")
        }
    }

    private func sendToGPT() {
        guard let fileURL else {
            predictionText = "❌ No file selected."
            return
        }
        guard let _ = HTTPClient.shared.apiKey, !(HTTPClient.shared.apiKey ?? "").isEmpty else {
            predictionText = "Missing API key. Please set OPENAI_API_KEY in Info.plist."
            return
        }

        isLoading = true
        predictionText = ""

        let analyzer = KPIAnalyzer(assistantId: kpiAssistantId)
        analyzer.analyzeKPI(fileURL: fileURL, departmentName: selectedDepartment) { result in
            DispatchQueue.main.async {
                self.predictionText = result
                self.isLoading = false
            }
        }
    }

    // MARK: - KPI Reports folder helpers

    private func kpiReportsDirectoryURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("KPIReports", isDirectory: true)
    }

    private func ensureKPIReportsDirectoryExists() {
        let dir = kpiReportsDirectoryURL()
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) || !isDir.boolValue {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Analyzer (unchanged core)

struct KPIAnalyzer {
    let assistantId: String
    private var apiKey: String? { HTTPClient.shared.apiKey }

    let historicalFileIds: [String: String] = [
        "marketing": "file-TJYfXNfMKrPAttAKrUjmTk",
        "sales": "file-N5tC9anVXgmgq41jDcnCjq",
        "tech": "file-NPaZXz5EuToA2Pw24C1Ms5",
        "product": "file-VRMzU8QMTasBxcyCPtDHZt",
        "finance": "file-E7MQvXTgk1bRy4SBcttuwx",
        "operations": "file-8KhZbBwixYyBcm5VpLBY8g",
        "customer support": "file-UZttM4zsKqoVGiTNMPnW5J"
    ]

    func analyzeKPI(fileURL: URL, departmentName: String, completion: @escaping (String) -> Void) {
        guard let key = apiKey, !key.isEmpty else {
            completion("Missing API key. Please set OPENAI_API_KEY in Info.plist.")
            return
        }

        uploadFile(apiKey: key, fileURL: fileURL) { fileId in
            guard let fileId else { completion("❌ File upload failed."); return }

            createThread(apiKey: key) { threadId in
                guard let threadId else { completion("❌ Thread creation failed."); return }

                let promptText = """
                You are an expert KPI prediction assistant. Two files are attached:
                - One is the current month’s KPI for the \(departmentName) department.
                - The other contains last year’s trends for the same department.

                Your job:
                1. Calculate each KPI’s current value from raw data.
                2. Compare it with the same KPI from the same month last year.
                3. Use BSC targets to determine: Prediction = Meet | Not Meet
                4. Explain the prediction based on trends and targets.

                Output format:

                KPI: <name>
                Current Value: <value>
                Last Year (Same Month): <value>
                Target: <target>
                Prediction: Meet | Not Meet
                Reason: <reason>
                """

                sendMessage(apiKey: key, threadId: threadId, fileId: fileId, prompt: promptText, departmentName: departmentName) {
                    startRun(apiKey: key, threadId: threadId, fileId: fileId, departmentName: departmentName) { runId in
                        guard let runId else { completion("❌ Run initiation failed."); return }

                        pollRunStatus(apiKey: key, threadId: threadId, runId: runId) { ok in
                            if ok {
                                fetchResponse(apiKey: key, threadId: threadId, completion: completion)
                            } else {
                                completion("❌ Run failed or timed out.")
                            }
                        }
                    }
                }
            }
        }
    }

    // --- OpenAI helpers (same pattern you use elsewhere) ---

    private func uploadFile(apiKey: String, fileURL: URL, completion: @escaping (String?) -> Void) {
        print("📤 Uploading file: \(fileURL.lastPathComponent)")

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/files")!)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let fileData = try? Data(contentsOf: fileURL) else {
            completion(nil); return
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
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fileId = json["id"] as? String else { completion(nil); return }
            print("✅ File uploaded: \(fileId)")
            completion(fileId)
        }.resume()
    }

    private func createThread(apiKey: String, completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/threads")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        request.httpBody = Data("{}".utf8)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let threadId = json["id"] as? String else { completion(nil); return }
            print("✅ Thread created: \(threadId)")
            completion(threadId)
        }.resume()
    }

    private func sendMessage(apiKey: String, threadId: String, fileId: String, prompt: String, departmentName: String, completion: @escaping () -> Void) {
        let lowerDept = departmentName.lowercased()
        let historicalFileId = historicalFileIds[lowerDept] ?? ""

        var attachments: [[String: Any]] = [[
            "file_id": fileId,
            "tools": [["type": "code_interpreter"]]
        ]]

        if !historicalFileId.isEmpty {
            attachments.append([
                "file_id": historicalFileId,
                "tools": [["type": "code_interpreter"]]
            ])
        }

        let payload: [String: Any] = [
            "role": "user",
            "content": [["type": "text", "text": prompt]],
            "attachments": attachments
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { _, _, _ in
            completion()
        }.resume()
    }

    private func startRun(apiKey: String, threadId: String, fileId: String, departmentName: String, completion: @escaping (String?) -> Void) {
        let lowerDept = departmentName.lowercased()
        let historicalFileId = historicalFileIds[lowerDept]
        let fileIds = historicalFileId != nil ? [fileId, historicalFileId!] : [fileId]

        let payload: [String: Any] = [
            "assistant_id": assistantId,
            "tool_resources": [
                "code_interpreter": ["file_ids": fileIds]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let runId = json["id"] as? String else { completion(nil); return }
            print("✅ Run created: \(runId)")
            completion(runId)
        }.resume()
    }

    private func pollRunStatus(apiKey: String, threadId: String, runId: String, completion: @escaping (Bool) -> Void) {
        let url = URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs/\(runId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

        func poll(after delay: TimeInterval) {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                URLSession.shared.dataTask(with: request) { data, _, _ in
                    guard let data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let status = json["status"] as? String else { completion(false); return }

                    print("📥 poll status=\(status)")
                    switch status {
                    case "completed": completion(true)
                    case "failed": completion(false)
                    default: poll(after: min(delay * 1.5, 10))
                    }
                }.resume()
            }
        }
        poll(after: 2)
    }

    private func fetchResponse(apiKey: String, threadId: String, completion: @escaping (String) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = json["data"] as? [[String: Any]],
                  let first = messages.first,
                  let contentArr = first["content"] as? [[String: Any]],
                  let textObj = contentArr.first?["text"] as? [String: Any],
                  let value = textObj["value"] as? String else {
                completion("❌ Failed to parse GPT response.")
                return
            }
            completion(value)
        }.resume()
    }
}

// MARK: - Export helper (UIDocumentPicker for exporting one file)

struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url])
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

// MARK: - Helpers

private extension DateFormatter {
    static let reportTimestamp: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df
    }()
}

#Preview {
    KPIAnalysisView()
}
