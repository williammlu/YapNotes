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