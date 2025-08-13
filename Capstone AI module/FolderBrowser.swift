//
//  FolderBrowser.swift
//  Capstone AI module
//
//  Created by Elwiz Scott on 13/8/25.
//


import UniformTypeIdentifiers
import SwiftUI

struct FolderBrowser: UIViewControllerRepresentable {
    let startURL: URL
    let onPick: (URL) -> Void   // NEW

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        vc.directoryURL = startURL
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)   // hand the file back to SwiftUI
        }
    }
}
