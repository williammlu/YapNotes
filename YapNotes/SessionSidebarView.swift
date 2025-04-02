import SwiftUI

struct SessionSidebarView: View {
    // Called when user taps “Close” in the top bar
    var onSessionClose: () -> Void
    @ObservedObject var viewModel: RecordingViewModel
    let currentSessionID: String?

    @State private var sessions: [SessionMetadata] = []
    @State private var selectedSession: SessionMetadata?

    var body: some View {
        ZStack(alignment: .leading) {
            Color.orange.edgesIgnoringSafeArea(.vertical)

            VStack(alignment: .leading) {
                // Title + new session button
                HStack {
                    Text("Yap Sessions")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        Task {
                            await viewModel.endSession()
                            loadSessions()
                            onSessionClose()
                        }
                    }) {
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                            .font(.title3)
                            .padding(6)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                // iOS 15+ approach with List & .swipeActions
                List {
                    ForEach(sessions, id: \.id) { session in
                        SessionRowView(session: session, isCurrent: session.id == currentSessionID)
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
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(PlainListStyle())
                .scrollContentBackground(.hidden)
                .background(Color.white) // Updated background color
            }
            .padding(.top, 20)
        }
        .frame(width: UIConstants.sideMenuWidth)
        .onAppear { loadSessions() }
        .onReceive(NotificationCenter.default.publisher(for: .sessionMetadataDidUpdate)) { _ in
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
        SessionManager.shared.deleteSession(session)
    }
}

extension Notification.Name {
    static let sessionMetadataDidUpdate = Notification.Name("sessionMetadataDidUpdate")
}


// Custom row view for a session
struct SessionRowView: View {
    let session: SessionMetadata
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let first = session.chunks.first {
                Text("\"\(first.text.prefix(40))\"")
                    .font(.headline)
                    .foregroundColor(.black) // Updated text color
            }
            Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundColor(.gray)
            if isCurrent {
                Text("Current")
                    .font(.caption2)
                    .foregroundColor(.black) // Updated text color
                    .padding(4)
                    .background(Color.orange.opacity(0.3)) // Updated background opacity
                    .cornerRadius(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.gray.opacity(0.1)) // Updated background color
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
                    Text("Final Transcript:")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text((session.transcribedText == nil ? "No transcript available." : session.transcribedText) ?? "nothing..")
                        .font(.body)
                        .foregroundColor(.white)
                }
                .padding()
            }
            .navigationTitle("Session Details")
        }
    }
}
