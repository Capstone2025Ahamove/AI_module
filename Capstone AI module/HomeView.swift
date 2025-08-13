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
    @State private var isDocumentPicked = false
    @State private var navigateToSummary = false
    @State private var selectedPhotoImage: Image? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color("AppBackground")
                    .ignoresSafeArea()

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

                    // Upload Buttons
                    HStack(spacing: 40) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
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
                        .onChange(of: selectedPhoto) { newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    selectedPhotoImage = Image(uiImage: uiImage)
                                    selectedFileURL = nil // Clear file if any
                                }
                            }
                        }

                        Button(action: {
                            isDocumentPicked = true
                        }) {
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
                                    selectedPhotoImage = nil // Clear image if any
                                }
                            case .failure:
                                break
                            }
                        }
                    }

                    // File Display
                    if selectedPhotoImage != nil || selectedFileURL != nil {
                        HStack(spacing: 12) {
                            // Show image
                            if let selectedPhotoImage = selectedPhotoImage {
                                selectedPhotoImage
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50, height: 50)
                            }

                            // Show file name if picked
                            if let url = selectedFileURL {
                                Text(url.lastPathComponent)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(hex: "#00731D"))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Button("Update") {
                                if selectedPhotoImage != nil {
                                    selectedPhoto = nil // Clear and re-select
                                    selectedPhotoImage = nil
                                } else {
                                    isDocumentPicked = true
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

                    // Analyze Button
                    NavigationLink(destination: SummaryView(fileURL: selectedFileURL, selectedImage: selectedPhotoImage)
, isActive: $navigateToSummary) {
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
}

#Preview {
    HomeView()
}
