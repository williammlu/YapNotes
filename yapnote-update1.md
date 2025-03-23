### ./YapNotes/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required for microphone access -->
    <key>NSMicrophoneUsageDescription</key>
    <string>This app needs access to the microphone to record audio notes.</string>
</dict>
</plist>

### ./YapNotes/YapNotesApp.swift
import SwiftUI

@main
struct YapNotesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

### ./YapNotes/ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var transcribedText: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("YapNotes Audio Recorder")
                .font(.title)

            Text(transcribedText)
                .foregroundColor(.gray)
                .padding()
                .frame(height: 200)
                .border(Color.secondary, width: 1)

            Button(action: {
                if audioRecorder.isRecording {
                    // Stop recording and transcribe
                    audioRecorder.stopRecording()
                    transcribeAudio()
                } else {
                    // Start recording
                    transcribedText = ""
                    audioRecorder.startRecording()
                }
            }) {
                Text(audioRecorder.isRecording ? "Stop Recording" : "Start Recording")
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(audioRecorder.isRecording ? Color.red : Color.blue)
                    .cornerRadius(8)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    private func transcribeAudio() {
        let floatData = audioRecorder.recordedFloats
        Task {
            if let result = await SpeechRecognitionManager.shared.transcribeAudio(floatData: floatData) {
                transcribedText = result
            } else {
                transcribedText = "Transcription failed or model not loaded."
            }
        }
    }
}

### ./YapNotes/AudioRecorder.swift
import AVFoundation
import SwiftUI

class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    private var audioEngine: AVAudioEngine?
    private var mixerNode: AVAudioMixerNode?
    private var format: AVAudioFormat?

    // Store floating-point audio data here
    private(set) var recordedFloats: [Float] = []

    func startRecording() {
        recordedFloats = []
        isRecording = true

        let engine = AVAudioEngine()
        audioEngine = engine

        // Whisper models often expect 16k mono
        // We'll set up an input format for 16k, 1 channel if possible
        let inputNode = engine.inputNode
        let desiredSampleRate: Double = 16000.0
        let desiredFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: desiredSampleRate,
                                          channels: 1,
                                          interleaved: false)
        format = desiredFormat

        // Attach a mixer to convert from hardware sample rate to 16k
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)

        // Connect input -> mixer with desired format
        engine.connect(inputNode, to: mixer, format: inputNode.inputFormat(forBus: 0))
        engine.connect(mixer, to: engine.mainMixerNode, format: desiredFormat)
        mixer.outputVolume = 1.0
        mixerNode = mixer

        // Install a tap on the mixer to receive audio data
        mixer.installTap(onBus: 0, bufferSize: 1024, format: desiredFormat) { buffer, _ in
            guard let channelData = buffer.floatChannelData?.pointee else { return }
            let frameCount = Int(buffer.frameLength)
            // Append the floats to our array
            self.recordedFloats.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frameCount))
        }

        do {
            try engine.start()
        } catch {
            print("Error starting AVAudioEngine: \(error)")
        }
    }

    func stopRecording() {
        isRecording = false
        audioEngine?.stop()
        mixerNode?.removeTap(onBus: 0)
        audioEngine = nil
    }
}

### ./YapNotes/SpeechRecognitionManager.swift
import Foundation

class SpeechRecognitionManager {
    static let shared = SpeechRecognitionManager()

    private var whisperWrapper: WhisperWrapper?
    private var isModelLoaded = false

    private init() {
        // Attempt to load a Whisper model from the app bundle.
        // For example, if you have a file named "ggml-base.en.bin" in the main bundle:
        if let modelPath = Bundle.main.path(forResource: "ggml-base.en", ofType: "bin") {
            let wrapper = WhisperWrapper()
            if wrapper.loadModel(modelPath) {
                whisperWrapper = wrapper
                isModelLoaded = true
            }
        }
    }

    func transcribeAudio(floatData: [Float]) async -> String? {
        guard isModelLoaded, let wrapper = whisperWrapper else {
            return nil
        }
        // For demonstration, pass entire buffer to whisper
        let count = Int32(floatData.count)

        // We must ensure that floatData is passed as a pointer
        return floatData.withUnsafeBufferPointer { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return nil }
            return wrapper.transcribeAudio(baseAddress, length: count)
        }
    }
}

### ./YapNotes/YapNotes-Bridging-Header.h
#import "WhisperWrapper.h"

### ./YapNotes/Whisper/WhisperWrapper.h
#ifndef WhisperWrapper_h
#define WhisperWrapper_h

#import <Foundation/Foundation.h>

@interface WhisperWrapper : NSObject

- (BOOL)loadModel:(NSString *)modelPath;
- (NSString * _Nullable)transcribeAudio:(float *)audioData length:(int)length;

@end

#endif /* WhisperWrapper_h */

### ./YapNotes/Whisper/WhisperWrapper.mm
#import "WhisperWrapper.h"
#import "whisper.h"

@implementation WhisperWrapper {
    struct whisper_context *ctx;
}

- (instancetype)init {
    self = [super init];
    if(self) {
        ctx = NULL;
    }
    return self;
}

- (BOOL)loadModel:(NSString *)modelPath {
    const char *cModelPath = [modelPath UTF8String];
    ctx = whisper_init(cModelPath);
    return (ctx != NULL);
}

- (NSString *)transcribeAudio:(float *)audioData length:(int)length {
    if(!ctx) {
        return @"Model not loaded";
    }
    struct whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.print_progress = false;
    wparams.print_realtime = false;
    wparams.print_timestamps = false;

    int result = whisper_full(ctx, wparams, audioData, length);
    if (result != 0) {
        return @"Transcription failed";
    }
    int segments = whisper_full_n_segments(ctx);
    NSMutableString *finalString = [NSMutableString new];
    for (int i = 0; i < segments; i++) {
        const char *textCStr = whisper_full_get_segment_text(ctx, i);
        if (textCStr) {
            [finalString appendString:[NSString stringWithUTF8String:textCStr]];
        }
    }
    return finalString;
}

@end

### ./YapNotes/Whisper/whisper.h
#ifndef whisper_h
#define whisper_h

#ifdef __cplusplus
extern "C" {
#endif

typedef struct whisper_context whisper_context;

whisper_context* whisper_init(const char * path);

typedef enum {
    WHISPER_SAMPLING_GREEDY = 0,
} whisper_sampling_strategy;

typedef struct whisper_full_params {
    bool print_progress;
    bool print_realtime;
    bool print_timestamps;
    whisper_sampling_strategy strategy;
} whisper_full_params;

struct whisper_full_params whisper_full_default_params(whisper_sampling_strategy strategy);
int whisper_full(whisper_context * ctx, struct whisper_full_params params, const float * samples, int n_samples);
int whisper_full_n_segments(whisper_context * ctx);
const char* whisper_full_get_segment_text(whisper_context * ctx, int index);

#ifdef __cplusplus
}
#endif

#endif /* whisper_h */

### ./YapNotes/Whisper/whisper.cpp
#include "whisper.h"
#include <stdlib.h>
#include <string.h>

// Minimal example stub for demonstration.
// For real use, include the full whisper.cpp from https://github.com/ggerganov/whisper.cpp

struct whisper_context {
    char* modelPath;
    char* lastTranscript;
};

whisper_context* whisper_init(const char* path) {
    whisper_context* ctx = (whisper_context*)malloc(sizeof(whisper_context));
    if (ctx) {
        ctx->modelPath = strdup(path);
        ctx->lastTranscript = NULL;
    }
    return ctx;
}

whisper_full_params whisper_full_default_params(whisper_sampling_strategy strategy) {
    whisper_full_params params;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.strategy = strategy;
    return params;
}

int whisper_full(whisper_context* ctx, whisper_full_params params, const float* samples, int n_samples) {
    // Fake transcription logic for demonstration
    // In a real setup, you'd use the full whisper.cpp library
    if (ctx->lastTranscript) {
        free(ctx->lastTranscript);
    }
    const char *fakeResult = "Transcribed text from whisper.cpp (demo stub).";
    ctx->lastTranscript = strdup(fakeResult);
    return 0;
}

int whisper_full_n_segments(whisper_context* ctx) {
    if (!ctx->lastTranscript) return 0;
    return 1;
}

const char* whisper_full_get_segment_text(whisper_context* ctx, int index) {
    if (!ctx->lastTranscript) return "";
    return ctx->lastTranscript;
}