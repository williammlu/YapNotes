### ./YapNotes/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>com.wml.YapNotes</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>YapNotes</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSRequiresIPhoneOS</key>
  <true/>
  <key>UILaunchScreen</key>
  <dict/>
  <key>UIRequiredDeviceCapabilities</key>
  <array>
    <string>armv7</string>
  </array>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
</dict>
</plist>

### ./YapNotes/Assets.xcassets/Contents.json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

### ./YapNotes/YapNotesApp.swift
import SwiftUI

@main
struct YapNotesApp: App {
    var body: some Scene {
        WindowGroup {
            RecordingView()
        }
    }
}

### ./YapNotes/RecordingView.swift
import SwiftUI

struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: {}) {
                        Image(systemName: "folder")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button(action: {}) {
                        Image(systemName: "gearshape")
                            .font(.title)
                            .foregroundColor(.red)
                    }
                }
                .padding([.leading, .trailing, .top], 24)

                Spacer()

                if viewModel.isDownloadingModel {
                    Text("Downloading model... \(Int(viewModel.downloadProgress * 100))%")
                        .foregroundColor(.white)
                        .padding(.bottom, 12)
                } else if !viewModel.isModelDownloaded {
                    Button(action: {
                        Task {
                            await viewModel.downloadModel()
                        }
                    }) {
                        Text("Download Model")
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                    .padding(.bottom, 12)
                } else {
                    if viewModel.isProcessing {
                        Text("Processing")
                            .foregroundColor(.white)
                            .padding(.bottom, 24)
                    }

                    WaveformView(amplitude: viewModel.currentAmplitude)
                        .frame(height: 120)
                        .padding(.bottom, 16)

                    Button(action: {
                        Task {
                            await viewModel.toggleRecording()
                        }
                    }) {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.white)
                            .frame(width: 70, height: 70)
                    }
                    .padding(.bottom, 16)

                    Text(viewModel.isRecording ? "Recording..." : "Voice")
                        .foregroundColor(.white)
                        .padding(.bottom, 8)

                    if !viewModel.transcribedText.isEmpty {
                        Text(viewModel.transcribedText)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(10)
                            .padding(.horizontal, 24)
                    }
                }

                Spacer()
            }
        }
    }
}

struct WaveformView: View {
    var amplitude: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let midY = height / 2

            Path { path in
                path.move(to: CGPoint(x: 0, y: midY))
                for x in stride(from: 0, through: width, by: 2) {
                    let relativeX = x / width
                    let normalized = sin(relativeX * 2.0 * .pi)
                    let y = midY + normalized * amplitude * midY
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.white, lineWidth: 2)
        }
    }
}


### ./YapNotes/RecordingViewModel.swift
import SwiftUI
import AVFoundation

@MainActor
class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isModelDownloaded = false
    @Published var isDownloadingModel = false
    @Published var downloadProgress: Double = 0.0
    @Published var transcribedText = ""
    @Published var currentAmplitude: CGFloat = 0.0

    private var recorder: AudioRecorder?
    private var whisperContext: WhisperContext?
    private var engine: AVAudioEngine?
    private var audioTimer: Timer?

    func downloadModel() async {
        guard !isModelDownloaded else { return }
        isDownloadingModel = true
        downloadProgress = 0.0

        let modelName = "ggml-base-q5_1.bin"
        let modelURLString = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin"

        do {
            try await ModelDownloadManager.shared.download(urlString: modelURLString,
                                                           fileName: modelName,
                                                           progressHandler: { progress in
                Task { @MainActor in
                    self.downloadProgress = progress
                }
            })
            isModelDownloaded = true
        } catch {
            isModelDownloaded = false
        }
        isDownloadingModel = false

        if isModelDownloaded {
            loadWhisperModel()
        }
    }

    private func loadWhisperModel() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelFile = docsDir.appendingPathComponent("ggml-base-q5_1.bin")
        do {
            whisperContext = try WhisperContext.createContext(path: modelFile.path)
        } catch {
            whisperContext = nil
            isModelDownloaded = false
        }
    }

    func toggleRecording() async {
        guard let whisperContext else { return }

        if isRecording {
            isRecording = false
            audioTimer?.invalidate()
            audioTimer = nil
            await recorder?.stopRecording()
            isProcessing = true

            if let audioFile = recorder?.recordedFileURL {
                do {
                    let samples = try decodeWaveFile(audioFile)
                    await whisperContext.fullTranscribe(samples: samples)
                    let text = await whisperContext.getTranscription()
                    transcribedText = text
                } catch {
                    transcribedText = "Error transcribing."
                }
            }
            isProcessing = false
        } else {
            isRecording = true
            transcribedText = ""

            if recorder == nil {
                recorder = AudioRecorder()
            }
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("output.wav")

            do {
                try await recorder?.startRecording(toOutputFile: fileURL)
            } catch {
                isRecording = false
                return
            }

            startMetering()
        }
    }

    private func startMetering() {
        engine = AVAudioEngine()
        guard let engine = engine else { return }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            let channelData = buffer.floatChannelData?[0]
            let frames = Int(buffer.frameLength)
            var avgValue: Float = 0.0
            if let channelData {
                var sum: Float = 0.0
                for i in 0..<frames {
                    sum += abs(channelData[i])
                }
                avgValue = sum / Float(frames)
            }
            Task { @MainActor in
                self.currentAmplitude = CGFloat(avgValue * 2.0)
            }
        }
        do {
            try engine.start()
        } catch {
            return
        }
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in }
    }
}


### ./YapNotes/AudioRecorder.swift
import Foundation
import AVFoundation

actor AudioRecorder {
    private var recorder: AVAudioRecorder?
    var recordedFileURL: URL?

    enum RecorderError: Error {
        case couldNotStartRecording
    }

    func startRecording(toOutputFile url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        #endif

        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        newRecorder.isMeteringEnabled = true
        if newRecorder.record() == false {
            throw RecorderError.couldNotStartRecording
        }
        recorder = newRecorder
        recordedFileURL = url
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
    }
}


### ./YapNotes/LibWhisper.swift
import Foundation
import UIKit
import whisper

enum WhisperError: Error {
    case couldNotInitializeContext
}

actor WhisperContext {
    private var context: OpaquePointer

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    func fullTranscribe(samples: [Float]) {
        let maxThreads = max(1, min(8, cpuCount() - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        "en".withCString { cLang in
            params.print_realtime = false
            params.print_progress = false
            params.print_timestamps = false
            params.print_special = false
            params.translate = false
            params.language = cLang
            params.n_threads = Int32(maxThreads)
            params.offset_ms = 0
            params.no_context = true
            params.single_segment = false

            whisper_reset_timings(context)
            samples.withUnsafeBufferPointer { ptr in
                if whisper_full(context, params, ptr.baseAddress, Int32(samples.count)) != 0 {
                    print("Failed to run the model.")
                } else {
                    whisper_print_timings(context)
                }
            }
        }
    }

    func getTranscription() -> String {
        var text = ""
        let nSegments = whisper_full_n_segments(context)
        for i in 0..<nSegments {
            let segmentText = whisper_full_get_segment_text(context, i)
            if let cString = segmentText {
                text += String(cString: cString)
            }
        }
        return text
    }

    static func createContext(path: String) throws -> WhisperContext {
        var params = whisper_context_default_params()
        #if targetEnvironment(simulator)
        params.use_gpu = false
        #endif
        let ctx = whisper_init_from_file_with_params(path, params)
        guard let ctx else {
            throw WhisperError.couldNotInitializeContext
        }
        return WhisperContext(context: ctx)
    }
}

private func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}


### ./YapNotes/ModelDownloadManager.swift
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


### ./YapNotes/RiffWaveUtils.swift
import Foundation

func decodeWaveFile(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    guard data.count > 44 else {
        return []
    }
    let strideSize = 2
    let startIndex = 44
    var floats = [Float]()
    var i = startIndex
    while i + strideSize <= data.count {
        let sampleData = data[i..<(i + strideSize)]
        let value = sampleData.withUnsafeBytes {
            Float(Int16(littleEndian: $0.load(as: Int16.self))) / 32767.0
        }
        floats.append(value)
        i += strideSize
    }
    return floats
}