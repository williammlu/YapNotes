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

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

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
