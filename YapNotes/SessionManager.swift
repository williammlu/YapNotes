import Foundation

/// Simple struct to describe one finalized chunk
struct ChunkMetadata: Codable {
    let index: Int
    let duration: Double
    let text: String
    let fileName: String? // chunk-1.wav if you store chunk wavs, or nil
}

/// Holds all metadata for one session, stored in metadata.json
struct SessionMetadata: Codable, Identifiable {
    let id: String            // e.g., a UUID or timestamp
    let startTime: Date
    var chunks: [ChunkMetadata]
    var transcribedText: String?
}

/// Manages creation & loading of session folders with WAV + JSON
class SessionManager {

    static let shared = SessionManager()

    private init() {}

    /// Create a new folder for a session, returning the folder URL + empty metadata
    func createNewSessionFolder() throws -> (folderURL: URL, metadata: SessionMetadata) {
        let dateFormatter = ISO8601DateFormatter()
        let timeStamp = dateFormatter.string(from: Date())  // e.g. 2023-09-25T14:03:12Z
        let sessionID = "session-\(timeStamp)"

        let folderURL = try getRecordingsDirectory().appendingPathComponent(sessionID)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // Create initial metadata
        let meta = SessionMetadata(
            id: sessionID,
            startTime: Date(),
            chunks: [],
            transcribedText: nil
        )
        return (folderURL, meta)
    }

    /// Load all session folders in the Recordings directory, read metadata.json if present
    func loadAllSessions() -> [SessionMetadata] {
        var results: [SessionMetadata] = []

        do {
            let root = try getRecordingsDirectory()
            let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            // Filter only directories named like 'session-...'
            let sessionFolders = contents.filter { $0.lastPathComponent.hasPrefix("session-") }

            for folder in sessionFolders {
                let metaURL = folder.appendingPathComponent("metadata.json")
                if FileManager.default.fileExists(atPath: metaURL.path) {
                    do {
                        let data = try Data(contentsOf: metaURL)
                        let meta = try JSONDecoder().decode(SessionMetadata.self, from: data)
                        results.append(meta)
                    } catch {
                        print("Could not load metadata for folder \(folder.lastPathComponent): \(error)")
                    }
                }
            }

        } catch {
            print("Error loading sessions: \(error)")
        }

        return results
    }

    /// Save the metadata.json for a session
    func saveMetadata(_ metadata: SessionMetadata, inFolder folderURL: URL) {
        let metaURL = folderURL.appendingPathComponent("metadata.json")
        do {
            let data = try JSONEncoder().encode(metadata)
            print("saving data \(data)")
            try data.write(to: metaURL)
            NotificationCenter.default.post(name: .sessionMetadataDidUpdate, object: nil)
        } catch {
            print("Error writing metadata: \(error)")
        }
    }

    /// Delete a session's folder (including metadata.json & any WAV files)
    func deleteSession(_ session: SessionMetadata) {
        do {
            let root = try getRecordingsDirectory()
            let folderURL = root.appendingPathComponent(session.id)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                try FileManager.default.removeItem(at: folderURL)
            }
        } catch {
            print("Error removing session folder for \(session.id): \(error)")
        }
    }

    /// Returns the main 'Recordings' directory inside Documents
    private func getRecordingsDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recDir = docs.appendingPathComponent("Recordings")
        if !FileManager.default.fileExists(atPath: recDir.path) {
            try FileManager.default.createDirectory(at: recDir, withIntermediateDirectories: true)
        }
        return recDir
    }
}

extension Notification.Name {
    static let sessionMetadataDidUpdate = Notification.Name("sessionMetadataDidUpdate")
}
