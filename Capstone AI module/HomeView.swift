//
//  HomeView.swift
//  Capstone AI module
//
//  Created by Elwiz Scott on 31/7/25.
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct HomeView: View {
    @State private var selectedFileURL: URL? = nil
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var selectedPhotoImage: Image? = nil

    @State private var isDocumentPicked = false
    @State private var showPhotoPicker = false       // reopen photo picker from "Update"

    @State private var navigateToSummary = false

    // NEW: fingerprint of the current input so downstream views can avoid reloading
    @State private var inputKey: String? = nil
    

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Use explicit hex to avoid asset issues
                Color(hex: "#FFFCF7").ignoresSafeArea()

                VStack(spacing: 24) {
                    // Top Buttons
                    HStack {
                        Button(action: {}) {
                            Image(systemName: "person.circle")
                                .resizable()
                                .frame(width: 28, height: 28)
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

                    // Title
                    VStack(spacing: 4) {
                        Text("AI DASHBOARD")
                            .font(.largeTitle).bold()
                            .foregroundColor(Color(hex:  "#00731D"))
                        Text("INTERPRETER")
                            .font(.title).bold()
                            .foregroundColor(Color(hex: "#00731D"))
                        Text("Generate summaries and insights from images or spreadsheets")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.horizontal)
                    }

                    // Upload row
                    HStack(spacing: 40) {
                        // Photo picker button
                        Button {
                            showPhotoPicker = true
                        } label: {
                            VStack {
                                Image(systemName: "photo")
                                    .font(.system(size: 32))
                                Text("Upload photo")
                                    .font(.headline)
                            }
                            .foregroundColor(Color(hex: "#00731D"))
                            .frame(width: 120, height: 100)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#00731D"), lineWidth: 2))
                        }
                        // Present the Photos picker when requested or when user taps Update
                        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
                        .onChange(of: selectedPhoto) { newItem in
                            Task {
                                guard let data = try? await newItem?.loadTransferable(type: Data.self),
                                      let uiImage = UIImage(data: data) else { return }
                                selectedPhotoImage = Image(uiImage: uiImage)
                                selectedFileURL = nil
                                inputKey = "img-" + UUID().uuidString // new image → new key
                            }
                        }

                        // File importer button
                        Button(action: { isDocumentPicked = true }) {
                            VStack {
                                Image(systemName: "tablecells")
                                    .font(.system(size: 32))
                                Text("Upload spreadsheet")
                                    .font(.headline)
                            }
                            .foregroundColor(Color(hex: "#00731D"))
                            .frame(width: 120, height: 100)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#00731D"), lineWidth: 2))
                        }
                        .fileImporter(
                            isPresented: $isDocumentPicked,
                            allowedContentTypes: [.commaSeparatedText, .spreadsheet, .data],
                            allowsMultipleSelection: false
                        ) { result in
                            switch result {
                            case .success(let urls):
                                if let first = urls.first {
                                    selectedFileURL = first
                                    selectedPhotoImage = nil
                                    inputKey = fingerprint(for: first)   // file → fingerprint
                                }
                            case .failure:
                                break
                            }
                        }
                    }

                    // File Display
                    if selectedPhotoImage != nil || selectedFileURL != nil {
                        HStack(spacing: 12) {
                            if let selectedPhotoImage = selectedPhotoImage {
                                selectedPhotoImage
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50, height: 50)
                            }

                            if let url = selectedFileURL {
                                Text(url.lastPathComponent)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(hex: "#00731D"))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            // UPDATE: re-open the appropriate picker without clearing the selection
                            Button("Update") {
                                if selectedPhotoImage != nil {
                                    showPhotoPicker = true            // re-open photo picker
                                } else {
                                    isDocumentPicked = true           // re-open file importer
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .foregroundColor(.white)
                            .background(Color(hex: "#00731D"))
                            .cornerRadius(6)

                            Button("Delete") {
                                selectedPhotoImage = nil
                                selectedFileURL = nil
                                inputKey = nil
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .foregroundColor(.white)
                            .background(Color(hex: "#EB4605"))
                            .cornerRadius(6)
                        }
                        .padding(6)
                        .frame(width: 280)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: "#00731D"), lineWidth: 2)
                        )
                        .padding(.horizontal)
                    }

                    Spacer()

                    // Analyze Button → pass file, image, and inputKey
                    NavigationLink(
                        destination: SummaryView(
                            fileURL: selectedFileURL,
                            selectedImage: selectedPhotoImage,
                            inputKey: inputKey
                        ),
                        isActive: $navigateToSummary
                    ) {
                        Text("Start Analyze")
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(hex: "#00731D"))
                            .foregroundColor(.white)
                            .font(.headline)
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                    }
                    .disabled(selectedPhotoImage == nil && selectedFileURL == nil)
                }
            }
        }
    }

    // MARK: - Helpers

    private func fingerprint(for url: URL) -> String {
        let name = url.lastPathComponent
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size  = (attrs[.size] as? NSNumber)?.intValue ?? -1
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        return "\(name)|\(size)|\(Int(mtime))"
    }
}

#Preview {
    HomeView()
}
