import SwiftUI
import AVFoundation

struct YapInfo: Identifiable, Equatable {
    let id = UUID()
    let index: Int
    let duration: Double
    let text: String
    // fileURL removed since we no longer store chunk WAV files
}

@MainActor
class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var transcribedText = ""
    
    // We store yaps, each corresponding to a chunk of recognized speech
    @Published var yaps: [YapInfo] = []
    
    // Real-time amplitude for waveform
    @Published var currentAmplitude: CGFloat = 0.0
    
    // Real-time multiple bar amplitudes
    @Published var barAmplitudes: [CGFloat] = Array(repeating: 0, count: 20)
    
    // For playback of the *entire* session if desired
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
    
    // Track the folder + metadata for this session
    private var currentSessionFolder: URL?
    @Published var currentSessionMetadata: SessionMetadata?
    
    init() {
        loadLocalModel()
        prepareAudio()
        if currentSessionFolder == nil {
            do {
                let (folderURL, meta) = try SessionManager.shared.createNewSessionFolder()
                currentSessionFolder = folderURL
                currentSessionMetadata = meta
            } catch {
                print("Failed to create session folder during init: \(error)")
            }
        }
    }
    
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
    
    func clearTranscribedText() {
        transcribedText = ""
    }
    
    func removeLastWordFromTranscribedText() {
        let words = transcribedText.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return }
        transcribedText = words.dropLast().joined(separator: " ")
        saveCurrentSessionMetadata()
    }
    
    func clearYaps() {
        yaps.removeAll()
        transcribedText = ""
        saveCurrentSessionMetadata()
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
        
        self.engineSampleRate = recordingFormat.sampleRate
        print("AudioEngine sample rate: \(engineSampleRate) Hz")
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            
            var sumAmplitude: Float = 0
            for i in 0..<frameCount {
                sumAmplitude += abs(channelData[i])
            }
            let avgAmplitude = sumAmplitude / Float(frameCount)
            
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
            
            Task { @MainActor in
                self.barAmplitudes = barValues.map { CGFloat($0) }
                self.currentAmplitude = CGFloat(avgAmplitude * 2.0)
            }
            
            // Chunk accumulation
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
                    print("Finalizing yap due to silence (frames: \(self.silentFrameCount), duration: \(chunkDuration)s)")
                    self.finalizeYap(force: false)
                }
            }
        }
        
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("Could not start AVAudioEngine: \(error)")
        }
    }
    
    func stopRecording() async {
        isRecording = false
        audioTimer?.invalidate()
        audioTimer = nil
        await recorder?.stopRecording()
        
        if !currentYapSamples.isEmpty {
            finalizeYap(force: true)
        }
        
        saveCurrentSessionMetadata()
    }
    
    func startRecording() async {
        isRecording = true
        recordingStart = Date()
        guard let folder = currentSessionFolder else { return }
        let wavURL = folder.appendingPathComponent("session.wav")
        
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
        yapStartTime = Date()
    }
    
    func toggleRecording() async {
        guard let whisperContext else { return }
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }
    
    func endSession() async {
        if isRecording {
            await stopRecording()
        }
        saveCurrentSessionMetadata()
        yaps.removeAll()
        transcribedText = ""
        currentYapSamples.removeAll()
        silentFrameCount = 0
        yapHasSpeech = false
        yapIndex = 0
        
        do {
            let (folderURL, meta) = try SessionManager.shared.createNewSessionFolder()
            currentSessionFolder = folderURL
            currentSessionMetadata = meta
        } catch {
            print("Failed to create new session folder: \(error)")
        }
    }
    
    private func finalizeYap(force: Bool) {
        let now = Date()
        let duration = now.timeIntervalSince(yapStartTime ?? now)
        let totalTime = timeStringSinceRecordingBegan()
        
        let yapSamples = currentYapSamples
        currentYapSamples.removeAll()
        silentFrameCount = 0
        
        print("Finalizing yap #\(yapIndex + 1) at \(totalTime), duration: \(duration)s")
        
        if yapHasSpeech {
            let idx = yapIndex + 1
            // No longer saving chunk WAV
            // No chunkFileURL creation or usage here
            
            Task {
                self.isProcessing = true
                guard let whisperContext, !yapSamples.isEmpty else {
                    self.isProcessing = false
                    return
                }
                
                let downsampled = self.downsampleTo16k(samples: yapSamples, inputRate: engineSampleRate)
                await whisperContext.fullTranscribe(samples: downsampled)
                let rawYapText = (await whisperContext.getTranscription()).trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !rawYapText.isEmpty && !isUnacceptableOutput(rawYapText) {
                    let yapInfo = YapInfo(
                        index: idx,
                        duration: duration,
                        text: rawYapText
                    )
                    await MainActor.run {
                        self.yaps.append(yapInfo)
                        if self.transcribedText.isEmpty {
                            self.transcribedText = rawYapText
                        } else {
                            self.transcribedText += " " + rawYapText
                        }
                    }
                    saveCurrentSessionMetadata()
                    if var meta = currentSessionMetadata {
                        // We keep chunk concept but no longer store a fileName
                        let chunkMeta = ChunkMetadata(
                            index: idx,
                            duration: duration,
                            text: rawYapText
                        )
                        meta.chunks.append(chunkMeta)
                        meta.transcribedText = self.transcribedText
                        currentSessionMetadata = meta
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
    
    func saveCurrentSessionMetadata() {
        guard let folder = currentSessionFolder, let meta = currentSessionMetadata else { return }
        SessionManager.shared.saveMetadata(meta, inFolder: folder)
    }
    
    // Removed chunk-level audio playback since we are no longer storing chunk WAVs:
    func playYapAudio(_ yap: YapInfo) {
        print("Per-chunk playback is no longer available. No WAV file stored for chunk #\(yap.index).")
    }
    
    private func timeStringSinceRecordingBegan() -> String {
        guard let recStart = recordingStart else {
            recordingStart = Date()
            return "0.0s (started tracking now)"
        }
        let interval = Date().timeIntervalSince(recStart)
        return String(format: "%.2fs since start", interval)
    }
    
    private func downsampleTo16k(samples: [Float], inputRate: Double) -> [Float] {
        guard inputRate > 16000.0 else { return samples }
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
    
    private func isUnacceptableOutput(_ text: String) -> Bool {
        let pattern = "^\\[.{0,18}\\]$"
        if let _ = text.range(of: pattern, options: .regularExpression) {
            return true
        }
        return false
    }
}
