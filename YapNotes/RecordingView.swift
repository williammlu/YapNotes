import SwiftUI
import UniformTypeIdentifiers

struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    let maxBarHeight: CGFloat = 200.0

    // Control the visibility of our custom side menus
    @State private var showLeftMenu = false
    @State private var showRightMenu = false

    // Tracks whether user is intentionally scrolled up (so we don’t auto-scroll)
    @State private var userHasScrolledUp = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    // Doggy icon
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

    // The main content offset X based on side menus
    private var mainContentOffsetX: CGFloat {
        if showLeftMenu { 
            // Slide right to reveal left menu
            return 250 
        } else if showRightMenu {
            // Slide left to reveal right settings
            return -250
        } else {
            return 0
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Left side menu (SessionSidebarView)
            SessionSidebarView(
                onSessionClose: {
                    withAnimation { showLeftMenu = false }
                }
            )
            .frame(width: 250)
            .offset(x: showLeftMenu ? 0 : -250)

            // Right side menu (SettingsView)
            HStack {
                Spacer()
                SettingsView(onClose: {
                    withAnimation { showRightMenu = false }
                })
                .frame(width: 250)
                .offset(x: showRightMenu ? 0 : 250)
            }

            // Main content
            mainRecordingContent
                .offset(x: mainContentOffsetX)
                .animation(.easeOut, value: showLeftMenu)
                .animation(.easeOut, value: showRightMenu)
        }
    }

    private var mainRecordingContent: some View {
        ZStack {
            Color.orange
                .ignoresSafeArea()

            VStack(spacing: 10) {
                // Top row
                HStack {
                    Button(action: {
                        // Toggle the left menu
                        withAnimation {
                            showLeftMenu.toggle()
                            showRightMenu = false
                        }
                    }) {
                        Image(systemName: "folder")
                            .font(.title)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Image(doggyIconName)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white)
                        .colorInvert()
                        .frame(width: 100, height: 100)

                    Spacer()

                    Button(action: {
                        withAnimation {
                            showRightMenu.toggle()
                            showLeftMenu = false
                        }
                    }) {
                        Image(systemName: "gearshape")
                            .font(.title)
                            .foregroundColor(.red)
                    }
                }
                .padding([.leading, .trailing, .top], 24)

                // Single text with all joined text
                ScrollView {
                    Text(allYapsConcatenated)
                        .foregroundColor(.white)
                        .padding()
                }
                .frame(maxHeight: .infinity)

                // Histogram bars
                BarWaveformView(
                    barAmplitudes: viewModel.barAmplitudes,
                    maxBarHeight: maxBarHeight
                )
                .frame(height: maxBarHeight)

                Spacer().frame(height: 10)

                // Scrollable yaps with auto-scroll
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

            // Record button pinned at bottom
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecording ? Color.white : Color.red)
                            .frame(width: 70, height: 70)
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 74, height: 74)
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
        .sheet(isPresented: $showShareSheet) {
            ActivityViewControllerWrapper(activityItems: shareItems)
        }
    }

    private var allYapsConcatenated: String {
        viewModel.yaps.map { $0.text }.joined(separator: " ")
    }
}

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

struct BottomOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}