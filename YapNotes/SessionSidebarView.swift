import SwiftUI

// Updated to remove .sheet usage and rely on parent controlling offset
struct SessionSidebarView: View {
    // For custom close action
    var onSessionClose: () -> Void

    @State private var sessions: [SessionMetadata] = []
    @State private var selectedSession: SessionMetadata?

    var body: some View {
        ZStack(alignment: .leading) {
            Color(.systemBackground).edgesIgnoringSafeArea(.vertical)
            VStack(alignment: .leading) {
                HStack {
                    Text("All Sessions")
                        .font(.headline)
                    Spacer()
                    Button("Close") {
                        onSessionClose()
                    }
                }
                .padding()
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
                .listStyle(.inset)
            }
            .padding(.top, 20)
        }
        .onAppear { loadSessions() }
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
        }
    }

    private func loadSessions() {
        sessions = SessionManager.shared.loadAllSessions()
    }
}

struct SessionDetailView: View {
    let session: SessionMetadata
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Session: \(session.id)")
                        .font(.title2)
                    Text("Started: \(session.startTime.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Divider()
                    ForEach(session.chunks, id: \.index) { chunk in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chunk #\(chunk.index)").bold()
                            Text("Duration: \(chunk.duration, specifier: "%.2f")s")
                            Text(chunk.text)
                        }
                        .padding(.bottom, 6)
                    }
                }
                .padding()
            }
            .navigationTitle("Session Details")
        }
    }
}