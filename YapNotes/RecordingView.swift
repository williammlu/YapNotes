import SwiftUI
import UniformTypeIdentifiers

struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    let maxBarHeight: CGFloat = 200.0

    // We'll remove showLeftMenu / showRightMenu booleans,
    // and replace them with a single drag offset that can be from -250...0...250
    // to represent side drawer states. The "open" states are offset == 250 (left) or -250 (right).

    @State private var dragOffset: CGFloat = 0 // Real-time offset from center
    private var dragFactor: CGFloat = 0.025

    // For auto-scroll logic
    @State private var userHasScrolledUp = false

    // For share sheet
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    // Constants
    private let sideMenuWidth: CGFloat = 250
    private let animationDuration: Double = 0.3

    // If offset == sideMenuWidth, left drawer is "open"
    // If offset == -sideMenuWidth, right drawer is "open"
    // If offset == 0, none open

    // Doggy icon name
    private var doggyIconName: String {
        let amp = viewModel.currentAmplitude
        if amp < 0.02 { return "doggy-sound-0" }
        else if amp < 0.04 { return "doggy-sound-1" }
        else if amp < 0.075 { return "doggy-sound-2" }
        else { return "doggy-sound-3" }
    }

    // A helper to check if left is open
    private var isLeftOpen: Bool {
        dragOffset == sideMenuWidth
    }
    // Right open
    private var isRightOpen: Bool {
        dragOffset == -sideMenuWidth
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Left side menu
            SessionSidebarView {
                // Tapping "Close" => animate offset to 0
                withAnimation(.linear(duration: animationDuration)) {
                    dragOffset = 0
                }
            }
            .frame(width: sideMenuWidth)
            .offset(x: dragOffset >= 0 ? 0 : -sideMenuWidth) // If offset < 0, hide left menu
            // We only show the left menu if dragOffset > 0

            // Right side menu
            HStack {
                Spacer()
                SettingsView {
                    withAnimation(.linear(duration: animationDuration)) {
                        dragOffset = 0
                    }
                }
                .frame(width: sideMenuWidth)
                // We only show the right menu if dragOffset < 0
                .offset(x: dragOffset <= 0 ? 0 : sideMenuWidth)
            }

            // Main content with partial offset
            ZStack {
                Color.orange.ignoresSafeArea()

                mainCenterContent

                // If offset != 0, show overlay (i.e. user is partially or fully opening a menu)
                if dragOffset != 0 {
                    Color.black
                        .opacity(0.3 * Double(abs(dragOffset / sideMenuWidth)))
                        .ignoresSafeArea()
                        .onTapGesture {
                            // Tapping overlay => close
                            withAnimation(.linear(duration: animationDuration)) {
                                dragOffset = 0
                            }
                        }
                }
            }
            .offset(x: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Live update the offset
                        // We clamp dragOffset between -sideMenuWidth...sideMenuWidth
                        let newOffset = (value.translation.width) // - math.clamp(value.translation.width, -20, 20)
                        print(newOffset, " ", isLeftOpen, isRightOpen)
                        dragOffset = max(-sideMenuWidth, min(sideMenuWidth, newOffset))
                    }
                    .onEnded { value in
                        // In onEnded, decide final position
                        // If user was near left edge or the offset > 0 => possibly open left
                        if dragOffset > 0 {
                            // if dragOffset > half of sideMenuWidth, snap open. else snap closed
                            if dragOffset > sideMenuWidth / 2 {
                                withAnimation(.smooth(duration: animationDuration)) {
                                    dragOffset = sideMenuWidth
                                }
                                // Pause if needed
                                if viewModel.isRecording {
                                    Task { await viewModel.recorder?.stopRecording() }
                                }
                            } else {
                                withAnimation(.easeInOut(duration: animationDuration)) {
                                    dragOffset = 0
                                }
                            }
                        }
                        // If user was near right edge or the offset < 0 => possibly open right
                        else if dragOffset < 0 {
                            if abs(dragOffset) > (sideMenuWidth / 2) {
                                withAnimation(.easeInOut(duration: animationDuration)) {
                                    dragOffset = -sideMenuWidth
                                }
                                // Pause if needed
                                if viewModel.isRecording {
                                    Task { await viewModel.recorder?.stopRecording() }
                                }
                            } else {
                                withAnimation(.easeInOut(duration: animationDuration)) {
                                    dragOffset = 0
                                }
                            }
                        }
                    }
            )
        }
    }

    private var mainCenterContent: some View {
        VStack(spacing: 10) {
            // Top row
            HStack {
                // Folder -> if we are not open on the left, animate to left
                // or close if open
                Button {
                    withAnimation(.linear(duration: animationDuration)) {
                        if isLeftOpen {
                            dragOffset = 0
                        } else {
                            dragOffset = sideMenuWidth
                            if viewModel.isRecording {
                                Task { await viewModel.recorder?.stopRecording() }
                            }
                        }
                    }
                } label: {
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

                // Gear -> open right or close
                Button {
                    withAnimation(.linear(duration: animationDuration)) {
                        if isRightOpen {
                            dragOffset = 0
                        } else {
                            dragOffset = -sideMenuWidth
                            if viewModel.isRecording {
                                Task { await viewModel.recorder?.stopRecording() }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            .padding([.leading, .trailing, .top], 24)

            // Single text with all yaps
            ScrollView {
                Text(allYapsConcatenated)
                    .foregroundColor(.white)
                    .padding()
            }
            .frame(maxHeight: .infinity)

            // Waveform
            BarWaveformView(
                barAmplitudes: viewModel.barAmplitudes,
                maxBarHeight: maxBarHeight
            )
            .frame(height: maxBarHeight)

            Spacer().frame(height: 10)

            // Yaps list
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
                .onPreferenceChange(BottomOffsetPreferenceKey.self) { offset in
                    let screenHeight = UIScreen.main.bounds.height
                    let threshold = screenHeight * 1.2
                    userHasScrolledUp = (offset < -threshold)
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
                        Task { await viewModel.toggleRecording() }
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

