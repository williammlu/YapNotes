import SwiftUI

struct SessionSidebarView: View {
    // Called when user taps “Close” in the top bar
    var onSessionClose: () -> Void
    @ObservedObject var viewModel: RecordingViewModel

    @State private var sessions: [SessionMetadata] = []
    @State private var selectedSession: SessionMetadata?

    var body: some View {
        ZStack(alignment: .leading) {
            Color(.systemBackground)
                .edgesIgnoringSafeArea(.vertical)

            VStack(alignment: .leading) {
                // Title + close
                HStack {
                    Text("All Sessions")
                        .font(.headline)
                    Spacer()
                    Button("Close") {
                        onSessionClose()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                
                Button(action: {
                    Task {
                        await viewModel.endSession()
                        loadSessions()
                    }
                }) {
                    Label("New Session", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)

                // iOS 15+ approach with List & .swipeActions
                List {
                    ForEach(sessions, id: \.id) { session in
                        SessionRowView(session: session)
                            .onTapGesture {
                                selectedSession = session
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteSession(session)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
            .padding(.top, 20)
        }
        .onAppear { loadSessions() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            loadSessions()
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
        }
    }

    private func loadSessions() {
        sessions = SessionManager.shared.loadAllSessions().sorted { $0.startTime > $1.startTime }
    }

    private func deleteSession(_ session: SessionMetadata) {
        // 1. Remove from local array
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions.remove(at: idx)
        }
        // 2. Also remove physically if you want from disk, e.g. SessionManager method
        // Suppose you add a function "SessionManager.shared.deleteSession(_ session: SessionMetadata)" 
        // that removes the folder from disk
        SessionManager.shared.deleteSession(session)
    }
}

// Custom row view for a session
struct SessionRowView: View {
    let session: SessionMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.plaintext")
                    .foregroundColor(.orange)
                Text(session.id)
                    .font(.headline)
                Spacer()
                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            if let preview = session.chunks.last?.text, !preview.isEmpty {
                Text("\"\(preview.prefix(40))\"")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

// Example detail view
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
