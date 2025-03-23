import SwiftUI
import AVFoundation

struct ChunkInfo: Identifiable {
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

    // We store chunk objects (with duration, text, and fileURL)
    @Published var chunks: [ChunkInfo] = []

    // Real-time amplitude for waveform
    @Published var currentAmplitude: CGFloat = 0.0

    private var recorder: AudioRecorder?
    private var whisperContext: WhisperContext?
    private var engine: AVAudioEngine?
    private var audioTimer: Timer?

    // For playback
    private var audioPlayer: AVAudioPlayer?

    // Chunking properties
    private var currentChunkSamples = [Float]()
    private var silentFrameCount = 0
    private var chunkHasSpeech = false
    private var chunkStartTime: Date?
    private var chunkIndex = 0

    // Silence / chunk rules
    private let silenceThreshold: Float = 0.01
    private let requiredSilenceFrames = 10  // e.g., 10 consecutive quiet frames
    private let minChunkDurationSec: Double = 1.0

    // For logging total record time
    private var recordingStart: Date?

    // NEW: We store the actual sample rate from the engine
    private var engineSampleRate: Double = 16000.0 // default 16k, to be overridden

    init() {
        loadLocalModel()
    }

    /// Load the smaller base model (ggml-base-q5_1)
    private func loadLocalModel() {
        if let modelPath = Bundle.main.path(forResource: "ggml-base-q5_1", ofType: "bin") {
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

    func toggleRecording() async {
        guard let whisperContext else { return }

        if isRecording {
            // Stop recording
            isRecording = false
            audioTimer?.invalidate()
            audioTimer = nil
            await recorder?.stopRecording()
            engine?.stop()
            engine = nil

            // Possibly finalize leftover chunk
            if !currentChunkSamples.isEmpty {
                finalizeChunk(force: true)
            }

            // Combine chunk texts if you want a single final transcript
            let allTexts = chunks.map { $0.text }
            transcribedText = allTexts.joined(separator: " ")

        } else {
            // Start recording
            isRecording = true
            transcribedText = ""
            chunks.removeAll()
            currentChunkSamples.removeAll()
            silentFrameCount = 0
            chunkHasSpeech = false
            chunkIndex = 0

            // Track total record time
            recordingStart = Date()

            // Prepare final output.wav
            if recorder == nil {
                recorder = AudioRecorder()
            }
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("output.wav")
            do {
                print("Starting recording on file \(fileURL)")
                try await recorder?.startRecording(toOutputFile: fileURL)
            } catch {
                isRecording = false
                print("Failed to start recording: \(error)")
                return
            }

            // Mark the start of the first chunk
            chunkStartTime = Date()
            startAudioEngine()
        }
    }

    private func startAudioEngine() {
        engine = AVAudioEngine()
        guard let engine = engine else { return }

        // Attempt voiceChat mode for noise suppression
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Error setting AVAudioSession category: \(error)")
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Store the engine's actual sample rate
        self.engineSampleRate = recordingFormat.sampleRate
        print("AudioEngine sample rate: \(engineSampleRate) Hz")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            let channelData = buffer.floatChannelData?[0]
            let frameCount = Int(buffer.frameLength)
            var sumAmplitude: Float = 0

            var localBuffer = [Float](repeating: 0, count: frameCount)
            if let channelData {
                for i in 0..<frameCount {
                    let val = channelData[i]
                    sumAmplitude += abs(val)
                    localBuffer[i] = val
                }
            }

            let avgAmplitude = sumAmplitude / Float(frameCount)

            // Update UI amplitude
            Task { @MainActor in
                self.currentAmplitude = CGFloat(avgAmplitude * 2.0)
            }

            // Mark chunkHasSpeech if amplitude above threshold
            if avgAmplitude > self.silenceThreshold {
                // print("Speech detected")
                self.chunkHasSpeech = true
            }

            // Accumulate samples
            self.currentChunkSamples.append(contentsOf: localBuffer)

            // Silence detection
            if avgAmplitude < self.silenceThreshold {
                self.silentFrameCount += 1
            } else {
                self.silentFrameCount = 0
            }

            // Check durations
            let now = Date()
            let chunkDuration = now.timeIntervalSince(self.chunkStartTime ?? now)

            // If enough silent frames + chunk is >= minChunkDuration, finalize
            if self.silentFrameCount >= self.requiredSilenceFrames && chunkDuration >= self.minChunkDurationSec {
                print("Finalizing chunk due to silence of frame count #\(self.silentFrameCount) and duration #\(chunkDuration)")
                self.finalizeChunk(force: false)
            }
        }

        do {
            try engine.start()
        } catch {
            print("Could not start AVAudioEngine: \(error)")
        }
    }

    private func finalizeChunk(force: Bool) {
        let now = Date()
        let duration = now.timeIntervalSince(chunkStartTime ?? now)
        let totalTime = timeStringSinceRecordingBegan()

        // Copy samples for this chunk
        let chunkSamples = currentChunkSamples
        currentChunkSamples.removeAll()

        // Reset counters
        silentFrameCount = 0

        print("Splitting chunk #\(chunkIndex + 1) at \(totalTime), chunk length: \(duration)s")

        if chunkHasSpeech {
            let idx = chunkIndex + 1
            chunkIndex += 1

            // Save chunk to a .wav file so we can play it back
            let chunkFileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("chunk-\(idx).wav")

            do {
                // Write with the REAL engine sample rate so playback is correct
                try savePCMToWav(
                    chunkSamples,
                    fileURL: chunkFileURL,
                    sampleRate: Int32(engineSampleRate)
                )
            } catch {
                print("Error saving chunk to wav: \(error)")
            }

            // Transcribe on a background Task
            Task {
                self.isProcessing = true
                guard let whisperContext, !chunkSamples.isEmpty else {
                    self.isProcessing = false
                    return
                }

                // Downsample to 16k for Whisper
                let downsampled = self.downsampleTo16k(samples: chunkSamples, inputRate: engineSampleRate)

                await whisperContext.fullTranscribe(samples: downsampled)
                let chunkText = await whisperContext
                    .getTranscription()
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !chunkText.isEmpty {
                    let chunkInfo = ChunkInfo(
                        index: idx,
                        duration: duration,
                        text: chunkText,
                        fileURL: chunkFileURL
                    )
                    await MainActor.run {
                        self.chunks.append(chunkInfo)
                    }
                } else {
                    print("Chunk #\(idx) had speech but no text output.")
                }
                self.isProcessing = false
            }
        } else {
            print("Skipping chunk #\(chunkIndex + 1) — all silence.")
        }

        // Reset chunk-level tracking
        chunkStartTime = Date()
        chunkHasSpeech = false
    }

    /// Playback any chunk
    func playChunkAudio(_ chunk: ChunkInfo) {
        guard let fileURL = chunk.fileURL else {
            print("No fileURL for chunk #\(chunk.index)")
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Error playing chunk #\(chunk.index): \(error)")
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

    // MARK: - WAV Writing With Real Sample Rate

    /// Save raw PCM Float samples to a 16-bit WAV file with a specified sampleRate.
    private func savePCMToWav(
        _ samples: [Float],
        fileURL: URL,
        sampleRate: Int32
    ) throws {
        // Convert Float -> Int16
        let int16Samples = samples.map { Int16($0 * Float(Int16.max)) }

        // WAV header fields
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16

        let subchunk2Size = int16Samples.count * MemoryLayout<Int16>.size
        let chunkSize: Int32 = 36 + Int32(subchunk2Size)

        let byteRate = Int32(numChannels) * Int32(bitsPerSample / 8) * sampleRate

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: int32ToBytes(chunkSize))
        data.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: int32ToBytes(16))            // Subchunk1Size = 16
        data.append(contentsOf: int16ToBytes(1))             // AudioFormat = 1 (PCM)
        data.append(contentsOf: int16ToBytes(numChannels))
        data.append(contentsOf: int32ToBytes(sampleRate))
        data.append(contentsOf: int32ToBytes(byteRate))

        let blockAlign = Int16(numChannels * bitsPerSample / 8)
        data.append(contentsOf: int16ToBytes(blockAlign))
        data.append(contentsOf: int16ToBytes(bitsPerSample))

        // data subchunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: int32ToBytes(Int32(subchunk2Size)))

        // samples
        for sample in int16Samples {
            data.append(contentsOf: int16ToBytes(sample.littleEndian))
        }

        try data.write(to: fileURL)
    }
    // MARK: - Downsample to 16k

    /// Very simple downsampling: picks every (inputRate/16000)th sample
    /// for demonstration only. For better audio, use a real DSP filter.
    private func downsampleTo16k(samples: [Float], inputRate: Double) -> [Float] {
        guard inputRate > 16000.0 else {
            // If engine sample rate is already 16k or less, no downsample needed
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

    // MARK: - Byte Helpers

    private func int16ToBytes(_ value: Int16) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }

    private func int32ToBytes(_ value: Int32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }
}
