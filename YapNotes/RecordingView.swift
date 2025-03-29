import SwiftUI
import UniformTypeIdentifiers

fileprivate extension Comparable {
    /// Clamps the value to a closed range
    func clamped(to range: ClosedRange<Self>) -> Self {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}


struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    let maxBarHeight: CGFloat = 200.0

    /// A single offset from -sideMenuWidth to sideMenuWidth
    /// Positive => left menu partially or fully in
    /// Negative => right menu partially or fully in
    @State private var dragOffset: CGFloat = 0

    private let sideMenuWidth: CGFloat = 250
    private let animationDuration: Double = 0.3

    // For auto-scroll logic in the yaps list
    @State private var userHasScrolledUp = false

    // For share sheet
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    // This function checks if the user wants to open or close at the end of a drag
    private func finalizeDrag() {
        if dragOffset > 0 {
            // Possibly open left
            if dragOffset > sideMenuWidth / 2 {
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = sideMenuWidth
                }
                if viewModel.isRecording {
                    Task { await viewModel.recorder?.stopRecording() }
                }
            } else {
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = 0
                }
            }
        } else if dragOffset < 0 {
            // Possibly open right
            if abs(dragOffset) > sideMenuWidth / 2 {
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = -sideMenuWidth
                }
                if viewModel.isRecording {
                    Task { await viewModel.recorder?.stopRecording() }
                }
            } else {
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = 0
                }
            }
        }
    }

    // Doggy icon name based on amplitude
    private var doggyIconName: String {
        let amp = viewModel.currentAmplitude
        if amp < 0.02 { return "doggy-sound-0" }
        else if amp < 0.04 { return "doggy-sound-1" }
        else if amp < 0.075 { return "doggy-sound-2" }
        else { return "doggy-sound-3" }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // LEFT MENU
            SessionSidebarView {
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = 0
                }
            }
            .frame(width: sideMenuWidth)
            // We'll offset the left menu so it slides from off-screen to on-screen
            .offset(x: dragOffset - sideMenuWidth)
            // e.g., if dragOffset=0 => offset is -250 (off screen)
            // if dragOffset=250 => offset is 0 => fully on screen

            // RIGHT MENU
            HStack {
                Spacer()
                SettingsView {
                    withAnimation(.easeOut(duration: animationDuration)) {
                        dragOffset = 0
                    }
                }
                .frame(width: sideMenuWidth)
                // We want if dragOffset = -250 => offset=0 => fully on
                // if dragOffset=0 => offset=+250 => off screen
                .offset(x: sideMenuWidth + dragOffset)
            }

            // MAIN CONTENT
            ZStack {
                Color.orange.ignoresSafeArea()
                mainContent

                if dragOffset != 0 {
                    Color.black
                        .opacity(0.3 * Double(abs(dragOffset) / sideMenuWidth))
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: animationDuration)) {
                                dragOffset = 0
                            }
                        }
                }
            }
            .offset(x: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newOffset = value.translation.width
                        // use our clamp extension
                        let clamped = newOffset.clamped(to: -sideMenuWidth ... sideMenuWidth)
                        dragOffset = clamped
                    }
                    .onEnded { _ in
                        finalizeDrag()
                    }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewControllerWrapper(activityItems: shareItems)
        }
    }

    private var mainContent: some View {
        VStack(spacing: 10) {
            // Top row
            HStack {
                // Left button
                Button {
                    withAnimation(.easeOut(duration: animationDuration)) {
                        if dragOffset == sideMenuWidth {
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

                // Right button
                Button {
                    withAnimation(.easeOut(duration: animationDuration)) {
                        if dragOffset == -sideMenuWidth {
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

            ScrollView {
                Text(viewModel.yaps.map(\.text).joined(separator: " "))
                    .foregroundColor(.white)
                    .padding()
            }
            .frame(maxHeight: .infinity)

            BarWaveformView(
                barAmplitudes: viewModel.barAmplitudes,
                maxBarHeight: maxBarHeight
            )
            .frame(height: maxBarHeight)

            Spacer().frame(height: 10)

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
                                    showShareSheet = true
                                    shareItems = [yap.text]
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
    }
}
