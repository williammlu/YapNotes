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
                    let y = midY + normalized * amplitude * midY * 40
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.white, lineWidth: 2)
        }
    }
}
