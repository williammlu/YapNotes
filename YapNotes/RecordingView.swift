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

    // For partial sliding
    @State private var dragOffset: CGFloat = 0
    @State private var isLeftOpen = false
    @State private var isRightOpen = false

    private let sideMenuWidth: CGFloat = 250
    private let animationDuration: Double = 0.3

    // For auto-scroll logic
    @State private var userHasScrolledUp = false

    // For share sheet
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    // Decide final
    private func finalizeDrag() {
        if dragOffset > 0 {
            // Possibly open left
            if dragOffset > sideMenuWidth / 2 {
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = sideMenuWidth
                }
                isLeftOpen = true
                isRightOpen = false
                if viewModel.isRecording {
                    Task { await viewModel.recorder?.stopRecording() }
                }
            } else {
                // Snap closed
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = 0
                }
                isLeftOpen = false
                isRightOpen = false
            }
        } else if dragOffset < 0 {
            // Possibly open right
            if abs(dragOffset) > sideMenuWidth / 2 {
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = -sideMenuWidth
                }
                isRightOpen = true
                isLeftOpen = false
                if viewModel.isRecording {
                    Task { await viewModel.recorder?.stopRecording() }
                }
            } else {
                // Snap closed
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = 0
                }
                isLeftOpen = false
                isRightOpen = false
            }
        } else {
            // Ended near zero => fully closed
            isLeftOpen = false
            isRightOpen = false
        }
    }

    // Doggy icon
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
                    isLeftOpen = false
                    isRightOpen = false
                }
            }
            .frame(width: sideMenuWidth)
            .offset(x: dragOffset - sideMenuWidth)

            // RIGHT MENU
            HStack {
                Spacer()
                SettingsView {
                    withAnimation(.easeOut(duration: animationDuration)) {
                        dragOffset = 0
                        isLeftOpen = false
                        isRightOpen = false
                    }
                }
                .frame(width: sideMenuWidth)
                .offset(x: sideMenuWidth + dragOffset)
            }

            // MAIN CONTENT
            ZStack {
                Color.orange.ignoresSafeArea()

                mainContent

                // Overlay if partially open
                if dragOffset != 0 {
                    Color.black
                        .opacity(0.3 * Double(abs(dragOffset) / sideMenuWidth))
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: animationDuration)) {
                                dragOffset = 0
                                isLeftOpen = false
                                isRightOpen = false
                            }
                        }
                }
            }
            .offset(x: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // We compute a base offset depending on which side is open
                        // or none. If left is open => base=+250, if right => -250, else 0.
                        // Then we add the current drag translation.
                        let base: CGFloat
                        if isLeftOpen {
                            base = sideMenuWidth
                        } else if isRightOpen {
                            base = -sideMenuWidth
                        } else {
                            base = 0
                        }

                        // total offset
                        let newOffset = base + value.translation.width
                        dragOffset = newOffset.clamped(to: -sideMenuWidth ... sideMenuWidth)
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
                // Left toggle
                Button {
                    withAnimation(.easeOut(duration: animationDuration)) {
                        if isLeftOpen {
                            // close
                            dragOffset = 0
                            isLeftOpen = false
                        } else {
                            // open left
                            dragOffset = sideMenuWidth
                            isLeftOpen = true
                            isRightOpen = false
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

                // Right toggle
                Button {
                    withAnimation(.easeOut(duration: animationDuration)) {
                        if isRightOpen {
                            // close
                            dragOffset = 0
                            isRightOpen = false
                        } else {
                            // open right
                            dragOffset = -sideMenuWidth
                            isRightOpen = true
                            isLeftOpen = false
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

            // The rest
            ScrollView {
                Text(viewModel.yaps.map(\.text).joined(separator: " "))
                    .foregroundColor(.white)
                    .padding()
            }
            .frame(maxHeight: .infinity)

            BarWaveformView(barAmplitudes: viewModel.barAmplitudes, maxBarHeight: maxBarHeight)
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
                            .fill(viewModel.isRecording ? .white : .red)
                            .frame(width: 70, height: 70)
                        Circle()
                            .stroke(.white, lineWidth: 2)
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
