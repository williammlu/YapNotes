import Foundation

actor ModelDownloadManager {
    static let shared = ModelDownloadManager()

    func download(urlString: String,
                  fileName: String,
                  progressHandler: @escaping (Double) -> Void) async throws {
        guard let url = URL(string: urlString) else { return }

        let request = URLRequest(url: url)
        let (downloadStream, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destination = docsDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let expectedLength = httpResponse.expectedContentLength
        var receivedLength: Int64 = 0

        let outputStream = OutputStream(url: destination, append: false)!
        outputStream.open()

        for try await byte in downloadStream {
            outputStream.write([byte], maxLength: 1)
            receivedLength += 1
            if expectedLength > 0 {
                let progress = Double(receivedLength) / Double(expectedLength)
                progressHandler(progress)
            }
        }

        outputStream.close()
    }
}