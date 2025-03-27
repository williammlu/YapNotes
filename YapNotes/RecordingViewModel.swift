import SwiftUI
import AVFoundation

struct YapInfo: Identifiable, Equatable {
    let id = UUID()
    let index: Int
    let duration: Double
    let text: String
    let fileURL: URL?
}

@MainActor
class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var transcribedText = ""

    // We store yap objects (with duration, text, and fileURL)
    @Published var yaps: [YapInfo] = []

    // Real-time amplitude for old single-line waveform
    @Published var currentAmplitude: CGFloat = 0.0

    // Real-time multiple bar amplitudes
    @Published var barAmplitudes: [CGFloat] = Array(repeating: 0, count: 20)

    // For playback
    private var audioPlayer: AVAudioPlayer?

    var recorder: AudioRecorder?
    private var whisperContext: WhisperContext?
    private var engine: AVAudioEngine?
    private var audioTimer: Timer?

    // Session + chunking properties
    private var currentYapSamples = [Float]()
    private var silentFrameCount = 0
    private var yapHasSpeech = false
    private var yapStartTime: Date?
    private var yapIndex = 0

    // Silence / chunk rules
    private let silenceThreshold: Float = 0.005
    private let requiredSilenceFrames = 10
    private let minChunkDurationSec: Double = 1.0

    // For logging total record time
    private var recordingStart: Date?

    // We store the actual sample rate from the engine
    private var engineSampleRate: Double = 16000.0

    // NEW: Track the folder + metadata for this session
    private var currentSessionFolder: URL?
    private var currentSessionMetadata: SessionMetadata?

    init() {
        loadLocalModel()
        prepareAudio()
    }

    private func loadLocalModel() {
        // Adjust path as needed
        if let modelPath = Bundle.main.path(forResource: "ggml-base-q5_1", ofType: "bin", inDirectory: "Models") {
            do {
                whisperContext = try WhisperContext.createContext(path: modelPath)
            } catch {
                print("Failed to load Whisper context: \(error)")
                whisperContext = nil
            }
        } else {
            print("Model file not found in bundle.")
        }
    }

    private func prepareAudio() {
        recorder = AudioRecorder()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Error setting AVAudioSession category: \(error)")
        }

        engine = AVAudioEngine()
        guard let engine = engine else { return }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Store the engine's actual sample rate
        self.engineSampleRate = recordingFormat.sampleRate
        print("AudioEngine sample rate: \(engineSampleRate) Hz")

        // Install a tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)

            // 1) Single overall amplitude
            var sumAmplitude: Float = 0
            for i in 0..<frameCount {
                sumAmplitude += abs(channelData[i])
            }
            let avgAmplitude = sumAmplitude / Float(frameCount)

            // 2) Multi-bar amplitude (20 bars, e.g.)
            let numberOfBars = 20
            let binSize = max(frameCount / numberOfBars, 1)
            var barValues = [Float](repeating: 0, count: numberOfBars)

            for barIndex in 0..<numberOfBars {
                let startIdx = barIndex * binSize
                let endIdx = min(startIdx + binSize, frameCount)
                var sumBin: Float = 0
                for j in startIdx..<endIdx {
                    sumBin += abs(channelData[j])
                }
                let count = Float(endIdx - startIdx)
                barValues[barIndex] = sumBin / max(count, 1)
            }

            // Update UI on main thread
            Task { @MainActor in
                self.barAmplitudes = barValues.map { CGFloat($0 * 1.0) }
                self.currentAmplitude = CGFloat(avgAmplitude * 2.0)
            }

            // 3) If recording, accumulate samples + handle chunking
            if self.isRecording {
                if avgAmplitude > self.silenceThreshold {
                    self.yapHasSpeech = true
                }

                var localBuffer = [Float](repeating: 0, count: frameCount)
                for i in 0..<frameCount {
                    localBuffer[i] = channelData[i]
                }
                self.currentYapSamples.append(contentsOf: localBuffer)

                if avgAmplitude < self.silenceThreshold {
                    self.silentFrameCount += 1
                } else {
                    self.silentFrameCount = 0
                }

                let now = Date()
                let chunkDuration = now.timeIntervalSince(self.yapStartTime ?? now)
                if self.silentFrameCount >= self.requiredSilenceFrames && chunkDuration >= self.minChunkDurationSec {
                    print("Finalizing yap due to silence of frame count #\(self.silentFrameCount) and duration #\(chunkDuration)")
                    self.finalizeYap(force: false)
                }
            }
        }

        // Start engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("Could not start AVAudioEngine: \(error)")
        }
    }

    func stopRecording () async {
        // Stop
        isRecording = false
        audioTimer?.invalidate()
        audioTimer = nil
        await recorder?.stopRecording()

        // Possibly finalize leftover
        if !currentYapSamples.isEmpty {
            finalizeYap(force: true)
        }

        // Combine text
        let allTexts = yaps.map { $0.text }
        transcribedText = allTexts.joined(separator: " ")

        // You might do a final save of metadata here, if needed
        saveCurrentSessionMetadata()

    }
    
    func startRecording() async {
        do {
            let (folderURL, meta) = try SessionManager.shared.createNewSessionFolder()
            currentSessionFolder = folderURL
            currentSessionMetadata = meta
        } catch {
            print("Failed to create session folder: \(error)")
            return
        }

        // Reset
        isRecording = true
        transcribedText = ""
        yaps.removeAll()
        currentYapSamples.removeAll()
        silentFrameCount = 0
        yapHasSpeech = false
        yapIndex = 0

        // Track total record time
        recordingStart = Date()

        // Record to that session folder
        guard let folder = currentSessionFolder else { return }
        let wavURL = folder.appendingPathComponent("session.wav")

        // Start recording
        if recorder == nil {
            recorder = AudioRecorder()
        }
        do {
            print("Starting recording at file \(wavURL)")
            try await recorder?.startRecording(toOutputFile: wavURL)
        } catch {
            isRecording = false
            print("Failed to start recording: \(error)")
            return
        }

        // Mark the start of the first yap
        yapStartTime = Date()
    }
    /// Toggle recording on/off
    func toggleRecording() async {
        guard let whisperContext else { return }

        if isRecording {
            await stopRecording()
        } else {
            // Start new session
           await  startRecording()
        }
    }

    private func finalizeYap(force: Bool) {
        let now = Date()
        let duration = now.timeIntervalSince(yapStartTime ?? now)
        let totalTime = timeStringSinceRecordingBegan()

        let yapSamples = currentYapSamples
        currentYapSamples.removeAll()
        silentFrameCount = 0

        print("Splitting yap #\(yapIndex + 1) at \(totalTime), length: \(duration)s")

        if yapHasSpeech {
            let idx = yapIndex + 1

            // Optionally store each chunk as a separate WAV
            // or you can skip chunk-level WAV
            let chunkFileName = "chunk-\(idx).wav"
            var chunkFileURL: URL?

            if let folder = currentSessionFolder {
                chunkFileURL = folder.appendingPathComponent(chunkFileName)
                do {
                    try savePCMToWav(
                        yapSamples,
                        fileURL: chunkFileURL!,
                        sampleRate: Int32(engineSampleRate)
                    )
                } catch {
                    print("Error saving chunk #\(idx) wav: \(error)")
                }
            }

            Task {
                self.isProcessing = true
                guard let whisperContext, !yapSamples.isEmpty else {
                    self.isProcessing = false
                    return
                }

                let downsampled = self.downsampleTo16k(samples: yapSamples, inputRate: engineSampleRate)
                await whisperContext.fullTranscribe(samples: downsampled)
                let rawYapText = await whisperContext.getTranscription()
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !rawYapText.isEmpty && !isUnacceptableOutput(rawYapText) {
                    let yapInfo = YapInfo(
                        index: idx,
                        duration: duration,
                        text: rawYapText,
                        fileURL: chunkFileURL
                    )
                    await MainActor.run {
                        self.yaps.append(yapInfo)
                    }
                    // Also add to session metadata
                    if var meta = currentSessionMetadata {
                        let chunkMeta = ChunkMetadata(
                            index: idx,
                            duration: duration,
                            text: rawYapText,
                            fileName: chunkFileName
                        )
                        meta.chunks.append(chunkMeta)
                        currentSessionMetadata = meta
                        // Save it right away
                        saveCurrentSessionMetadata()
                    }

                    yapIndex += 1
                } else {
                    print("Skipping chunk #\(idx) with text: \(rawYapText)")
                }
                self.isProcessing = false
            }
        } else {
            print("Skipping yap #\(yapIndex + 1) - silent.")
        }

        yapStartTime = Date()
        yapHasSpeech = false
    }

    /// Save the updated metadata.json for current session
    private func saveCurrentSessionMetadata() {
        guard let folder = currentSessionFolder,
              let meta = currentSessionMetadata else { return }
        SessionManager.shared.saveMetadata(meta, inFolder: folder)
    }

    func playYapAudio(_ yap: YapInfo) {
        guard let fileURL = yap.fileURL else {
            print("No fileURL for yap #\(yap.index)")
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Error playing yap #\(yap.index): \(error)")
        }
    }

    private func timeStringSinceRecordingBegan() -> String {
        guard let recStart = recordingStart else {
            recordingStart = Date()
            return "0.0s (started tracking now)"
        }
        let interval = Date().timeIntervalSince(recStart)
        return String(format: "%.2fs since start", interval)
    }

    // WAV writing with real sample rate
    private func savePCMToWav(
        _ samples: [Float],
        fileURL: URL,
        sampleRate: Int32
    ) throws {
        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16

        let subchunk2Size = int16Samples.count * MemoryLayout<Int16>.size
        let chunkSize: Int32 = 36 + Int32(subchunk2Size)
        let byteRate = Int32(numChannels) * Int32(bitsPerSample / 8) * sampleRate

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: int32ToBytes(chunkSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: int32ToBytes(16))
        data.append(contentsOf: int16ToBytes(1))    // PCM
        data.append(contentsOf: int16ToBytes(numChannels))
        data.append(contentsOf: int32ToBytes(sampleRate))
        data.append(contentsOf: int32ToBytes(byteRate))
        let blockAlign = Int16(numChannels * bitsPerSample / 8)
        data.append(contentsOf: int16ToBytes(blockAlign))
        data.append(contentsOf: int16ToBytes(bitsPerSample))
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: int32ToBytes(Int32(subchunk2Size)))

        for sample in int16Samples {
            data.append(contentsOf: int16ToBytes(sample.littleEndian))
        }

        try data.write(to: fileURL)
    }

    private func downsampleTo16k(samples: [Float], inputRate: Double) -> [Float] {
        guard inputRate > 16000.0 else {
            return samples
        }
        let ratio = inputRate / 16000.0
        var out = [Float]()
        out.reserveCapacity(Int(Double(samples.count) / ratio))

        var index = 0.0
        while Int(index) < samples.count {
            out.append(samples[Int(index)])
            index += ratio
        }
        return out
    }

    private func int16ToBytes(_ value: Int16) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }

    private func int32ToBytes(_ value: Int32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }

    private func isUnacceptableOutput(_ text: String) -> Bool {
        let pattern = "^\\[.{0,18}\\]$"
        if let _ = text.range(of: pattern, options: .regularExpression) {
            return true
        }
        return false
    }
}
