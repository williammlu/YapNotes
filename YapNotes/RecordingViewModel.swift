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

    // NEW: We store multiple bar amplitudes for the bar waveform
    @Published var barAmplitudes: [CGFloat] = Array(repeating: 0, count: 20)

    private var recorder: AudioRecorder?
    private var whisperContext: WhisperContext?
    private var engine: AVAudioEngine?
    private var audioTimer: Timer?

    // For playback
    private var audioPlayer: AVAudioPlayer?

    // Chunking properties
    private var currentYapSamples = [Float]()
    private var silentFrameCount = 0
    private var yapHasSpeech = false
    private var yapStartTime: Date?
    private var yapIndex = 0

    // Silence / chunk rules
    private let silenceThreshold: Float = 0.005
    private let requiredSilenceFrames = 10  // e.g., 10 consecutive quiet frames
    private let minChunkDurationSec: Double = 1.0

    // For logging total record time
    private var recordingStart: Date?

    // We store the actual sample rate from the engine
    private var engineSampleRate: Double = 16000.0 // default 16k, overridden later

    init() {
        loadLocalModel()
        prepareAudio()
    }

    /// Load the smaller base model (ggml-base-q5_1)
    private func loadLocalModel() {
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

    /// Prepare the AVAudioSession, AVAudioEngine, etc. — but do not record yet.
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

        // Install a tap to get audio data for amplitude, chunking, etc.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)

            // 1) Compute a single overall amplitude for “old” wave
            var sumAmplitude: Float = 0
            for i in 0..<frameCount {
                sumAmplitude += abs(channelData[i])
            }
            let avgAmplitude = sumAmplitude / Float(frameCount)

            // 2) Compute 40-bar amplitudes
            let numberOfBars = 40
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
                let barAmplitude = sumBin / max(count, 1)
                barValues[barIndex] = barAmplitude
            }

            // Update UI on main thread
            Task { @MainActor in
                // Scale them up a bit if needed; tweak factor to taste
                self.barAmplitudes = barValues.map { CGFloat($0 * 1.0) }
                self.currentAmplitude = CGFloat(avgAmplitude * 2.0)
            }

            // 3) If we are recording, handle chunk logic
            if self.isRecording {
                // Mark yapHasSpeech if amplitude above threshold
                if avgAmplitude > self.silenceThreshold {
                    self.yapHasSpeech = true
                }

                // Accumulate samples
                var localBuffer = [Float](repeating: 0, count: frameCount)
                for i in 0..<frameCount {
                    localBuffer[i] = channelData[i]
                }
                self.currentYapSamples.append(contentsOf: localBuffer)

                // Silence detection
                if avgAmplitude < self.silenceThreshold {
                    self.silentFrameCount += 1
                } else {
                    self.silentFrameCount = 0
                }

                // Check durations
                let now = Date()
                let chunkDuration = now.timeIntervalSince(self.yapStartTime ?? now)

                // If enough silent frames + chunk is >= minChunkDuration, finalize
                if self.silentFrameCount >= self.requiredSilenceFrames && chunkDuration >= self.minChunkDurationSec {
                    print("Finalizing yap due to silence of frame count #\(self.silentFrameCount) and duration #\(chunkDuration)")
                    self.finalizeYap(force: false)
                }
            }
        }

        // Prepare and start the engine so it's “hot” immediately
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("Could not start AVAudioEngine: \(error)")
        }
    }

    /// Toggle recording on/off
    func toggleRecording() async {
        guard let whisperContext else { return }

        if isRecording {
            // Stop recording
            isRecording = false
            audioTimer?.invalidate()
            audioTimer = nil
            await recorder?.stopRecording()

            // Possibly finalize leftover yap
            if !currentYapSamples.isEmpty {
                finalizeYap(force: true)
            }

            // Combine yap texts into a single final transcript
            let allTexts = yaps.map { $0.text }
            transcribedText = allTexts.joined(separator: " ")

        } else {
            // Start recording
            isRecording = true
            transcribedText = ""
            yaps.removeAll()
            currentYapSamples.removeAll()
            silentFrameCount = 0
            yapHasSpeech = false
            yapIndex = 0

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

            // Mark the start of the first yap
            yapStartTime = Date()
        }
    }

    private func finalizeYap(force: Bool) {
        let now = Date()
        let duration = now.timeIntervalSince(yapStartTime ?? now)
        let totalTime = timeStringSinceRecordingBegan()

        // Copy samples for this yap
        let yapSamples = currentYapSamples
        currentYapSamples.removeAll()

        // Reset counters
        silentFrameCount = 0

        print("Splitting yap #\(yapIndex + 1) at \(totalTime), yap length: \(duration)s")

        if yapHasSpeech {
            let idx = yapIndex + 1

            // Save yap to a .wav file so we can play it back
            let yapFileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("yap-\(idx).wav")

            do {
                // Write with the REAL engine sample rate so playback is correct
                try savePCMToWav(
                    yapSamples,
                    fileURL: yapFileURL,
                    sampleRate: Int32(engineSampleRate)
                )
            } catch {
                print("Error saving yap to wav: \(error)")
            }

            // Transcribe on a background Task
            Task {
                self.isProcessing = true
                guard let whisperContext, !yapSamples.isEmpty else {
                    self.isProcessing = false
                    return
                }

                // Downsample to 16k for Whisper
                let downsampled = self.downsampleTo16k(samples: yapSamples, inputRate: engineSampleRate)

                await whisperContext.fullTranscribe(samples: downsampled)
                let rawYapText = await whisperContext
                    .getTranscription()
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Filter out unacceptable or empty transcripts
                if !rawYapText.isEmpty && !isUnacceptableOutput(rawYapText) {
                    let yapInfo = YapInfo(
                        index: idx,
                        duration: duration,
                        text: rawYapText,
                        fileURL: yapFileURL
                    )
                    await MainActor.run {
                        self.yaps.append(yapInfo)
                    }
                    yapIndex += 1 // Increment yap index only if the yap is valid
                } else {
                    print("Skipping yap #\(idx) with text: \(rawYapText)")
                }
                self.isProcessing = false
            }
        } else {
            print("Skipping yap #\(yapIndex + 1) — all silence.")
        }

        // Reset yap-level tracking
        yapStartTime = Date()
        yapHasSpeech = false
    }

    /// Playback any yap
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

    // MARK: - WAV Writing With Real Sample Rate

    /// Save raw PCM Float samples to a 16-bit WAV file with a specified sampleRate.
    private func savePCMToWav(
        _ samples: [Float],
        fileURL: URL,
        sampleRate: Int32
    ) throws {
        // Convert Float -> Int16
        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }
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

    private func isUnacceptableOutput(_ text: String) -> Bool {
        let pattern = "^\\[.{0,18}\\]$"
        if let _ = text.range(of: pattern, options: .regularExpression) {
            return true
        }
        return false
    }
}
