//
//  ActivityViewControllerWrapper.swift
//  YapNotes
//
//  Created by William Lu on 3/28/25.
//
import SwiftUI

struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
