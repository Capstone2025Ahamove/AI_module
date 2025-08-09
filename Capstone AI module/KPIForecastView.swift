////
////  KPIForecastView.swift
////  Capstone AI module
////
////  Created by Andy L on 7/8/25.
////
//
//
//import SwiftUI
//import UniformTypeIdentifiers
//import Foundation
//
//struct KPIForecaster {
//    let apiKey: String
//    let assistantId: String
//
//    // Pre-uploaded 2025 department files mapped by lowercase department name
//    let historicalFileIds: [String: String] = [
//        "marketing": "file-81z6cKZfQ7ViQicL5N1UBs",
//        "sales": "file-F5GZ3FDfRKS4NNeBhcne49",
//        "tech": "file-CudYVYGo9X8vaGAEpd4Mu5",
//        "product": "file-U9hgTKh84nftG6BMzj6SrR",
//        "finance": "file-RnfPYhEyLmAYd48EhDk74X",
//        "operations": "file-6erp1u3HmUkRF1xEDH82EV",
//        "customer support": "file-LaCEQfUbCwVq8TtMfetqKF"
//    ]
//
//    func forecastKPI(fileURL: URL, completion: @escaping (String) -> Void) {
//        uploadFile(fileURL: fileURL) { userFileId in
//            guard let userFileId = userFileId else {
//                completion("❌ File upload failed.")
//                return
//            }
//
//            // Detect department from filename
//            let fileName = fileURL.lastPathComponent.lowercased()
//            let matchedDept = historicalFileIds.keys.first { dept in fileName.contains(dept) }
//            let historicalFileId = matchedDept.flatMap { historicalFileIds[$0] }
//
//            print("📁 Matched Department: \(matchedDept ?? "unknown")")
//            print("🕐 Historical File ID: \(historicalFileId ?? "none")")
//
//            createThread { threadId in
//                guard let threadId = threadId else {
//                    completion("❌ Thread creation failed.")
//                    return
//                }
//
//                let promptText = """
//                The uploaded file contains raw KPI variables for the current month or recent months. Use predefined formulas to calculate KPIs and compare to last year's trend if provided.
//
//                If full months only → decide Met / Not Met  
//                If partial months → predict Likely to Meet / Unlikely to Meet based on past 12-month trend
//
//                Output format:
//                KPI: <name>  
//                Current Value / Estimate: <value>  
//                Target: <target>  
//                Prediction: Met | Not Met | Likely to Meet | Unlikely to Meet  
//                Reason: <short explanation>
//                """
//
//                sendMessage(threadId: threadId, fileIds: [userFileId, historicalFileId].compactMap { $0 }, prompt: promptText) {
//                    startRun(threadId: threadId, fileIds: [userFileId, historicalFileId].compactMap { $0 }) { runId in
//                        guard let runId = runId else {
//                            completion("❌ Run initiation failed.")
//                            return
//                        }
//
//                        pollRunStatus(threadId: threadId, runId: runId) { isCompleted in
//                            if isCompleted {
//                                fetchResponse(threadId: threadId, completion: completion)
//                            } else {
//                                completion("❌ Run failed or timed out.")
//                            }
//                        }
//                    }
//                }
//            }
//        }
//    }
//
//    private func uploadFile(fileURL: URL, completion: @escaping (String?) -> Void) {
//        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/files")!)
//        request.httpMethod = "POST"
//        let boundary = UUID().uuidString
//        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
//
//        guard let fileData = try? Data(contentsOf: fileURL) else {
//            completion(nil)
//            return
//        }
//
//        var body = Data()
//        body.append("--\(boundary)\r\n".data(using: .utf8)!)
//        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\nassistants\r\n".data(using: .utf8)!)
//        body.append("--\(boundary)\r\n".data(using: .utf8)!)
//        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
//        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
//        body.append(fileData)
//        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
//        request.httpBody = body
//
//        URLSession.shared.dataTask(with: request) { data, _, _ in
//            guard let data = data,
//                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
//                  let fileId = json["id"] as? String else {
//                completion(nil)
//                return
//            }
//            completion(fileId)
//        }.resume()
//    }
//
//    private func createThread(completion: @escaping (String?) -> Void) {
//        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/threads")!)
//        request.httpMethod = "POST"
//        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
//        request.httpBody = Data("{}".utf8)
//
//        URLSession.shared.dataTask(with: request) { data, _, _ in
//            guard let data = data,
//                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
//                  let threadId = json["id"] as? String else {
//                completion(nil)
//                return
//            }
//            completion(threadId)
//        }.resume()
//    }
//
//    private func sendMessage(threadId: String, fileIds: [String], prompt: String, completion: @escaping () -> Void) {
//        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages")!)
//        request.httpMethod = "POST"
//        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
//
//        let payload: [String: Any] = [
//            "role": "user",
//            "content": [["type": "text", "text": prompt]],
//            "tool_resources": [
//                "code_interpreter": ["file_ids": fileIds]
//            ]
//        ]
//
//        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
//        URLSession.shared.dataTask(with: request) { _, _, _ in completion() }.resume()
//    }
//
//    private func startRun(threadId: String, fileIds: [String], completion: @escaping (String?) -> Void) {
//        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs")!)
//        request.httpMethod = "POST"
//        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
//
//        let payload: [String: Any] = [
//            "assistant_id": assistantId,
//            "tool_resources": [
//                "code_interpreter": ["file_ids": fileIds]
//            ]
//        ]
//
//        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
//        URLSession.shared.dataTask(with: request) { data, _, _ in
//            guard let data = data,
//                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
//                  let runId = json["id"] as? String else {
//                completion(nil)
//                return
//            }
//            completion(runId)
//        }.resume()
//    }
//
//    private func pollRunStatus(threadId: String, runId: String, completion: @escaping (Bool) -> Void) {
//        let url = URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs/\(runId)")!
//        var request = URLRequest(url: url)
//        request.httpMethod = "GET"
//        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
//
//        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
//            URLSession.shared.dataTask(with: request) { data, _, _ in
//                guard let data = data,
//                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
//                      let status = json["status"] as? String else {
//                    completion(false)
//                    return
//                }
//
//                if status == "completed" {
//                    completion(true)
//                } else if status == "failed" {
//                    completion(false)
//                } else {
//                    self.pollRunStatus(threadId: threadId, runId: runId, completion: completion)
//                }
//            }.resume()
//        }
//    }
//
//    private func fetchResponse(threadId: String, completion: @escaping (String) -> Void) {
//        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages")!)
//        request.httpMethod = "GET"
//        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
//
//        URLSession.shared.dataTask(with: request) { data, _, _ in
//            guard let data = data,
//                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
//                  let messages = json["data"] as? [[String: Any]],
//                  let first = messages.first,
//                  let contentArr = first["content"] as? [[String: Any]],
//                  let textObj = contentArr.first?["text"] as? [String: Any],
//                  let value = textObj["value"] as? String else {
//                completion("❌ Failed to parse GPT response.")
//                return
//            }
//            completion(value)
//        }.resume()
//    }
//}
//
////#Preview {
//    KPIForecastView()
//}
//
