//
//  KPIAnalysisView.swift
//  Capstone AI module
//
//  Created by Andy L on 7/8/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct KPIAnalysisView: View {
    @State private var fileURL: URL?
    @State private var isLoading = false
    @State private var predictionText = ""
    @State private var selectedDepartment = "Marketing"
    @State private var showFilePicker = false

    let departments = ["Marketing", "Sales", "Tech", "Product", "Finance", "Operations", "Customer Support"]

    // Replace with your actual key + Assistant ID
    // let apiKey = ""
    let assistantId = "asst_i0QIqjmFRA8xSFHuEGmU6PfI"

    var body: some View {
        VStack(spacing: 20) {
            Text("\u{1F4CA} KPI Prediction (GPT)")
                .font(.title2).bold()

            Picker("Department", selection: $selectedDepartment) {
                ForEach(departments, id: \ .self) {
                    Text($0)
                }
            }.pickerStyle(.menu)

            Button("Choose KPI CSV File") {
                showFilePicker = true
            }
            .disabled(isLoading)

            if isLoading {
                ProgressView("Analyzing with GPT...")
            }

            ScrollView {
                Text(predictionText)
                    .padding()
                    .font(.system(.body, design: .monospaced))
            }

            Spacer()
        }
        .padding()
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let selected = urls.first {
                    self.fileURL = selected
                    sendToGPT()
                }
            case .failure(let error):
                predictionText = "\u{274C} File import error: \(error.localizedDescription)"
            }
        }
    }

    private func sendToGPT() {
        guard let fileURL = fileURL else {
            predictionText = "\u{274C} No file selected."
            return
        }

        isLoading = true
        predictionText = ""

        let analyzer = KPIAnalyzer(apiKey: apiKey, assistantId: assistantId)
        analyzer.analyzeKPI(fileURL: fileURL, departmentName: selectedDepartment) { result in
            DispatchQueue.main.async {
                self.predictionText = result
                self.isLoading = false
            }
        }
    }
}

struct KPIAnalyzer {
    let apiKey: String
    let assistantId: String

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
        uploadFile(fileURL: fileURL) { fileId in
            guard let fileId = fileId else {
                completion("\u{274C} File upload failed.")
                return
            }

            createThread { threadId in
                guard let threadId = threadId else {
                    completion("\u{274C} Thread creation failed.")
                    return
                }

                let promptText = """
                You are an expert KPI prediction assistant. Two files are attached:
                - One is the current month’s KPI for the **\(departmentName)** department.
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

                sendMessage(threadId: threadId, fileId: fileId, prompt: promptText, departmentName: departmentName) {
                    startRun(threadId: threadId, fileId: fileId, departmentName: departmentName) { runId in
                        guard let runId = runId else {
                            completion("\u{274C} Run initiation failed.")
                            return
                        }

                        pollRunStatus(threadId: threadId, runId: runId) { isCompleted in
                            if isCompleted {
                                fetchResponse(threadId: threadId, completion: completion)
                            } else {
                                completion("\u{274C} Run failed or timed out.")
                            }
                        }
                    }
                }
            }
        }
    }

    // Add all helper methods here exactly as in your previous implementation
    private func uploadFile(fileURL: URL, completion: @escaping (String?) -> Void) {
        print("📤 Uploading file: \(fileURL.lastPathComponent)")

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/files")!)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let fileData = try? Data(contentsOf: fileURL) else {
            print("❌ Failed to read file data")
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
            guard let data = data else {
                print("❌ No data returned from file upload")
                completion(nil)
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let fileId = json["id"] as? String {
                print("✅ File uploaded with ID: \(fileId)")
                completion(fileId)
            } else {
                print("❌ Failed to extract file ID from response")
                completion(nil)
            }
        }.resume()
    }

    private func createThread(completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/threads")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        request.httpBody = Data("{}".utf8)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                completion(nil)
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let threadId = json["id"] as? String {
                completion(threadId)
            } else {
                completion(nil)
            }
        }.resume()
    }

    private func sendMessage(threadId: String, fileId: String, prompt: String, departmentName: String, completion: @escaping () -> Void) {
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

    private func startRun(threadId: String, fileId: String, departmentName: String, completion: @escaping (String?) -> Void) {
        let lowerDept = departmentName.lowercased()
        let historicalFileId = historicalFileIds[lowerDept]
        let fileIds = historicalFileId != nil ? [fileId, historicalFileId!] : [fileId]

        let payload: [String: Any] = [
            "assistant_id": assistantId,
            "tool_resources": [
                "code_interpreter": [
                    "file_ids": fileIds
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let runId = json["id"] as? String else {
                completion(nil)
                return
            }
            completion(runId)
        }.resume()
    }

    private func pollRunStatus(threadId: String, runId: String, completion: @escaping (Bool) -> Void) {
        let url = URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs/\(runId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            URLSession.shared.dataTask(with: request) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? String else {
                    completion(false)
                    return
                }

                if status == "completed" {
                    completion(true)
                } else if status == "failed" {
                    completion(false)
                } else {
                    pollRunStatus(threadId: threadId, runId: runId, completion: completion)
                }
            }.resume()
        }
    }

    private func fetchResponse(threadId: String, completion: @escaping (String) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
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
