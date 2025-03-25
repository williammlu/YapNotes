import SwiftUI
import UniformTypeIdentifiers

struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    // Adjust as needed
    let maxBarHeight: CGFloat = 200.0

    // Tracks whether user is intentionally scrolled up (so we don’t auto-scroll)
    @State private var userHasScrolledUp = false

    // For share sheet
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    // For showing the session sidebar
    @State private var showSidebar = false

    // Doggy icon based on amplitude (example)
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
            Color.orange
                .ignoresSafeArea()

            VStack(spacing: 10) {
                // -- Top row of buttons with the doggy icon in the middle --
                HStack {
                    Button(action: {
                        // Show the sidebar with past sessions
                        showSidebar = true
                    }) {
                        Image(systemName: "folder")
                            .font(.title)
                            .foregroundColor(.white)
                    }

                    Spacer()
                    // Doggy icon in the center
                    Image(doggyIconName)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white)
                        .colorInvert()
                        .frame(width: 100, height: 100)

                    Spacer()

                    Button(action: {}) {
                        Image(systemName: "gearshape")
                            .font(.title)
                            .foregroundColor(.red)
                    }
                }
                .padding([.leading, .trailing, .top], 24)

                // -- Single text view with all joined text (if you like)
                ScrollView {
                    Text(allYapsConcatenated)
                        .foregroundColor(.white)
                        .padding()
                }
                .frame(maxHeight: .infinity)

                // -- Histogram bars --
                BarWaveformView(
                    barAmplitudes: viewModel.barAmplitudes,
                    maxBarHeight: maxBarHeight
                )
                .frame(height: maxBarHeight)

                // -- some space before yaps list --
                Spacer().frame(height: 10)

                // -- Scrollable yaps with auto-scroll --
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
                                .id(yap.id)
                                .onTapGesture {
                                    viewModel.playYapAudio(yap)
                                }
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = yap.text
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }

                                    Button {
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

                        // If processing, show message
                        if viewModel.isProcessing {
                            Text("Processing")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                                .padding()
                                .id("PROCESSING")
                        }

                        Spacer().frame(height: 120).id("BOTTOM")
                    }
                    .onPreferenceChange(BottomOffsetPreferenceKey.self) { newOffset in
                        let screenHeight = UIScreen.main.bounds.height
                        let threshold = screenHeight * 1.2
                        userHasScrolledUp = (newOffset < -threshold)
                    }
                    .onChange(of: viewModel.yaps) { _ in
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
                            .fill(viewModel.isRecording ? Color.white : Color.red)
                            .frame(width: 70, height: 70)
                        // Outer border circle
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 74, height: 74)
                        // Pause icon if recording
                        if viewModel.isRecording {
                            Image(systemName: "pause.fill")
                                .foregroundColor(.red)
                                .font(.title)
                        }
                    }
                    .onTapGesture {
                        Task {
                            await viewModel.toggleRecording()
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 32)
            }
        }
        // Display share sheet
        .sheet(isPresented: $showShareSheet) {
            ActivityViewControllerWrapper(activityItems: shareItems)
        }
        // Sidebar for sessions
        .sheet(isPresented: $showSidebar) {
            SessionSidebarView()
        }
    }

    private var allYapsConcatenated: String {
        viewModel.yaps.map { $0.text }.joined(separator: " ")
    }
}

// MARK: - BarWaveformView (unchanged)
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
                Spacer()
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let amplitude = barAmplitudes[i]
                        let scaledHeight = min(sqrt(amplitude) * maxBarHeight, maxBarHeight)
                        RoundedCorners(radius: 3, corners: [.topLeft, .topRight])
                            .fill(Color.white)
                            .frame(width: barWidth, height: scaledHeight)
                    }
                }
            }
        }
    }
}

// MARK: - Rounding shape
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

// MARK: - Preference Key
struct BottomOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Share Sheet
struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}