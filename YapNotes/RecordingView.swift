import SwiftUI

struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    // Adjust as needed
    let maxBarHeight: CGFloat = 200.0

    // Tracks whether user is intentionally scrolled up (so we don’t auto-scroll)
    @State private var userHasScrolledUp = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // -- Top row of buttons --
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

                // -- Spacer to push histogram further down --
                Spacer().frame(height: 100)

                // -- Histogram bars --
                BarWaveformView(
                    barAmplitudes: viewModel.barAmplitudes,
                    maxBarHeight: maxBarHeight
                )
                .frame(height: maxBarHeight)
                .padding(.bottom, 16)

                // -- Possibly some space before chunk list --
                Spacer().frame(height: 20)

                // -- Scrollable chunk list with auto-scroll logic --
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: true) {
                        if !viewModel.chunks.isEmpty {
                            ForEach(viewModel.chunks) { chunk in
                                VStack(alignment: .leading, spacing: 4) {
                                    // Removed extra backslash in format string
                                    Text("Chunk #\(chunk.index) — \(String(format: "%.2f", chunk.duration))s")
                                        .foregroundColor(.yellow)
                                        .font(.subheadline)

                                    Text(chunk.text)
                                        .foregroundColor(.white)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(10)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 4)
                                .id(chunk.id) // So we can scroll to this chunk
                                // Tap gesture to play audio chunk
                                .onTapGesture {
                                    viewModel.playChunkAudio(chunk)
                                }
                            }
                        } else {
                            Text("No chunks recorded yet.")
                                .foregroundColor(.white)
                                .padding()
                        }

                        // Bottom spacer – we track its offset to see if user is near bottom
                        Spacer().frame(height: 100).id("BOTTOM")
                        
                        // Attach a preference so we know the vertical offset
                        Color.clear
                            .frame(height: 1)
                            .background(GeometryReader { geo in
                                Color.clear
                                    .preference(key: BottomOffsetPreferenceKey.self,
                                                value: geo.frame(in: .global).minY)
                            })
                    }
                    .onPreferenceChange(BottomOffsetPreferenceKey.self) { newOffset in
                        // This is a simplistic check: if newOffset is near the bottom
                        // of the screen, assume user is scrolled down.
                        // Tweak threshold as needed (e.g. 800, 1000, etc.)
                        let screenHeight = UIScreen.main.bounds.height
                        let threshold = screenHeight * 1.2

                        // If minY is > -threshold, user is near the bottom
                        userHasScrolledUp = (newOffset < -threshold)
                    }
                    .onChange(of: viewModel.chunks) { _ in
                        // Whenever new chunks arrive, if user is not scrolled up, jump to bottom
                        if !userHasScrolledUp {
                            DispatchQueue.main.async {
                                withAnimation {
                                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }

            // -- Record button pinned at bottom, centered horizontally --
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        // Inner circle
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.white)
                            .frame(width: 70, height: 70)
                        // Outer border circle (2px gap => 4 px bigger diameter)
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 74, height: 74)
                    }
                    .onTapGesture {
                        Task {
                            await viewModel.toggleRecording()
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 32) // Adjust as desired
            }

            // -- Overlay 'Processing' text so it doesn’t push layout --
            if viewModel.isProcessing {
                VStack {
                    Spacer().frame(height: 150) // position below the top row
                    Text("Processing")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding()
                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeInOut, value: viewModel.isProcessing)
            }
        }
    }
}

// MARK: - BarWaveformView with top corners rounded
struct BarWaveformView: View {
    let barAmplitudes: [CGFloat]
    let maxBarHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let barCount = barAmplitudes.count
            let spacing: CGFloat = 2
            let totalSpacing = CGFloat(barCount - 1) * spacing
            let availableWidth = geometry.size.width - totalSpacing
            let barWidth = availableWidth / CGFloat(barCount)

            VStack(spacing: 0) {
                Spacer() // push bars to the bottom

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let amplitude = barAmplitudes[i]
                        let scaledHeight = min(amplitude * maxBarHeight, maxBarHeight)
                        
                        // Rounded top corners: 3px
                        RoundedCorners(radius: 3, corners: [.topLeft, .topRight])
                            .fill(Color.white)
                            .frame(width: barWidth, height: scaledHeight)
                    }
                }
            }
        }
    }
}

// MARK: - A Shape for rounding only top corners
struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preference Key to track scroll offset
struct BottomOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
