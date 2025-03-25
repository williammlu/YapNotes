//
//  SessionSidebarView.swift
//  YapNotes
//
//  Created by William Lu on 3/25/25.
//


import SwiftUI

struct SessionSidebarView: View {
    @Environment(\.presentationMode) var presentationMode

    @State private var sessions: [SessionMetadata] = []
    @State private var selectedSession: SessionMetadata?

    var body: some View {
        NavigationView {
            List {
                ForEach(sessions, id: \.id) { session in
                    VStack(alignment: .leading) {
                        Text(session.id)
                            .font(.headline)
                        Text("Started: \(session.startTime.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .onTapGesture {
                        selectedSession = session
                    }
                }
            }
            .navigationTitle("All Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                loadSessions()
            }
            // If you want a detail view: 
            .sheet(item: $selectedSession) { session in
                SessionDetailView(session: session)
            }
        }
    }

    private func loadSessions() {
        sessions = SessionManager.shared.loadAllSessions()
    }
}

/// Example detail view that shows chunk data from that session
struct SessionDetailView: View {
    let session: SessionMetadata

    var body: some View {
        VStack(alignment: .leading) {
            Text("Session: \(session.id)")
                .font(.headline)
                .padding(.bottom, 6)

            ForEach(session.chunks, id: \.index) { chunk in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chunk #\(chunk.index)").bold()
                    Text("Duration: \(chunk.duration, specifier: "%.2f")s")
                    Text("\(chunk.text)")
                }
                .padding(.bottom, 8)
            }
            Spacer()
        }
        .padding()
    }
}