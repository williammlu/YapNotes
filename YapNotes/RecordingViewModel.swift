import SwiftUI
import AVFoundation

@MainActor
class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var transcribedText = ""
    @Published var currentAmplitude: CGFloat = 0.0

    private var recorder: AudioRecorder?
    private var whisperContext: WhisperContext?
    private var engine: AVAudioEngine?
    private var audioTimer: Timer?

    init() {
        loadLocalModel()
    }

    private func loadLocalModel() {
        // Attempt to load the pre-bundled model from the app bundle
        if let modelPath = Bundle.main.path(forResource: "ggml-base-q5_1", ofType: "bin") {
            do {
                whisperContext = try WhisperContext.createContext(path: modelPath)
            } catch {
                print("Failed to load context: \(error)")
                whisperContext = nil
            }
        } else {
            print("Model file not found in bundle.")
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

            if let audioFile = await recorder?.recordedFileURL {
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
            print("Could not start AVAudioEngine: \(error)")
        }

        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in }
    }
}
