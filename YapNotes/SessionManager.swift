import Foundation

struct ChunkMetadata: Codable {
    let index: Int
    let duration: Double
    let text: String
    // Removed fileName property, as chunk WAV files are no longer used
}

struct SessionMetadata: Codable, Identifiable {
    let id: String
    let startTime: Date
    var chunks: [ChunkMetadata]
    var transcribedText: String?
}

class SessionManager {

    static let shared = SessionManager()

    private init() {}

    func createNewSessionFolder() throws -> (folderURL: URL, metadata: SessionMetadata) {
        let dateFormatter = ISO8601DateFormatter()
        let timeStamp = dateFormatter.string(from: Date())
        let sessionID = "session-\(timeStamp)"

        let folderURL = try getRecordingsDirectory().appendingPathComponent(sessionID)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let meta = SessionMetadata(
            id: sessionID,
            startTime: Date(),
            chunks: [],
            transcribedText: nil
        )
        return (folderURL, meta)
    }

    func loadAllSessions() -> [SessionMetadata] {
        var results: [SessionMetadata] = []

        do {
            let root = try getRecordingsDirectory()
            let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
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

    private func getRecordingsDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recDir = docs.appendingPathComponent("Recordings")
        if !FileManager.default.fileExists(atPath: recDir.path) {
            try FileManager.default.createDirectory(at: recDir, withIntermediateDirectories: true)
        }
        return recDir
    }
}
