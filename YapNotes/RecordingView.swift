import SwiftUI
import UniformTypeIdentifiers
import AssetsLibrary

struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    // Adjust as needed
    let maxBarHeight: CGFloat = 200.0

    // Tracks whether user is intentionally scrolled up (so we don’t auto-scroll)
    @State private var userHasScrolledUp = false

    // For share sheet
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    // MARK: - Doggy Icon Name
    // Picks which doggy-sound-X to use based on the current amplitude.
    // Thresholds: 0.05 => doggy-sound-1, 0.1 => doggy-sound-2, 0.2 => doggy-sound-3.
    private var doggyIconName: String {
        let amplitude = viewModel.currentAmplitude
        if amplitude < 0.02 {
            return "doggy-sound-0"
        } else if amplitude < 0.04 {
            return "doggy-sound-1"
        } else if amplitude < 0.075 {
            return "doggy-sound-2"
        } else {
            return "doggy-sound-3"
        }
    }

    var body: some View {
        ZStack {
            Color.green
                .ignoresSafeArea()

            VStack(spacing: 10) {
                // -- Top row of buttons with the doggy icon in the middle --
                HStack {
                    Button(action: {}) {
                        Image(systemName: "folder")
                            .font(.title)
                            .foregroundColor(.white)
//                            .colorInvert()
                    }
                    Spacer()
                    // Doggy icon in the center
                    Image(doggyIconName)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white)
                        .colorInvert()
                        .frame(width: 100, height: 100) // adjust size as you like
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "gearshape")
                            .font(.title)
                            .foregroundColor(.red)
                    }
                }
                .padding([.leading, .trailing, .top], 24)

                // -- Scrollable single text view with all yaps concatenated --
                ScrollView {
                    Text(allYapsConcatenated)
                        .foregroundColor(.white)
                        .padding()
                }
                .frame(maxHeight: .infinity) // Fill available space

                // -- Histogram bars --
                BarWaveformView(
                    barAmplitudes: viewModel.barAmplitudes,
                    maxBarHeight: maxBarHeight
                )
                .frame(height: maxBarHeight)

                // -- some space before yap list --
                Spacer().frame(height: 10)

                // -- Scrollable yap list with auto-scroll logic --
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: true) {
                        if !viewModel.yaps.isEmpty {
                            ForEach(viewModel.yaps) { yap in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Yap #\(yap.index) — \(String(format: "%.2f", yap.duration))s")
                                        .foregroundColor(.yellow)
                                        .font(.subheadline)

                                    Text(yap.text)
                                        .foregroundColor(.white)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(10)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 4)
                                .id(yap.id) // So we can scroll to this yap
                                // Tap gesture to play audio yap
                                .onTapGesture {
                                    viewModel.playYapAudio(yap)
                                }
                                // 1) Long-press for Copy & Share
                                .contextMenu {
                                    Button {
                                        // Copy to clipboard
                                        UIPasteboard.general.string = yap.text
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }

                                    Button {
                                        // Show share sheet with yap text
                                        shareItems = [yap.text]
                                        showShareSheet = true
                                    } label: {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                }
                            }
                        } else {
                            Text("No yaps recorded yet.")
                                .foregroundColor(.white)
                                .padding()
                        }

                        // Show "Processing" text under the last yap if processing
                        if viewModel.isProcessing {
                            Text("Processing")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                                .padding()
                                .id("PROCESSING")
                        }

                        // Bottom spacer – we track its offset to see if user is near bottom
                        Spacer().frame(height: 120).id("BOTTOM")

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
                        let screenHeight = UIScreen.main.bounds.height
                        let threshold = screenHeight * 1.2

                        userHasScrolledUp = (newOffset < -threshold)
                    }
                    .onChange(of: viewModel.yaps) { _ in
                        // Whenever new yaps arrive, if user is not scrolled up, jump to bottom
                        if (!userHasScrolledUp) {
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
                            .fill(viewModel.isRecording ? Color.white : Color.red)
                            .frame(width: 70, height: 70)
                        // Outer border circle (2px gap => 4 px bigger diameter)
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 74, height: 74)
                        // Pause icon when recording
                        if viewModel.isRecording {
                            Image(systemName: "pause.fill")
                                .foregroundColor(.red)
                                .font(.title)
                        }
                    }
                    .onTapGesture {
                        // Continue recording along same list
                        Task {
                            await viewModel.toggleRecording()
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 32) // Adjust as desired
            }
        }
        // Display share sheet
        .sheet(isPresented: $showShareSheet) {
            ActivityViewControllerWrapper(activityItems: shareItems)
        }
    }

    // Helper: join all yaps’ text into one big string
    private var allYapsConcatenated: String {
        viewModel.yaps.map { $0.text }.joined(separator: " ")
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
                        // Example scaling: sqrt() to compress high amplitudes
                        let scaledHeight = min(sqrt(amplitude) * maxBarHeight, maxBarHeight)

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

// MARK: - Share Sheet Wrapper
struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // nothing
    }
}
