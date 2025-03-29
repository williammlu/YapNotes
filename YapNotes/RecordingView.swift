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

struct SharePresenter: UIViewControllerRepresentable {
    @Binding var shouldPresent: Bool
    @Binding var items: [Any]

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard shouldPresent else { return }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        DispatchQueue.main.async {
            uiViewController.present(activityVC, animated: true) {
                shouldPresent = false
            }
        }
    }
}

struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    private let debugModeEnabled: Bool = false
    @State private var selectedTab: TabType = .transcribe

    private enum TabType: String, CaseIterable {
        case transcribe = "Transcribe"
        case generate = "Generate"
    }

    // For partial sliding
    @State private var dragOffset: CGFloat = 0
    @State private var verticalDrag: CGFloat = 0
    @State private var isLeftOpen = false
    @State private var isRightOpen = false
    @State private var gestureDirectionLocked: Bool = false
    @State private var isVerticalSwipe: Bool = false

    private let sideMenuWidth: CGFloat = UIConstants.sideMenuWidth
    private let animationDuration: Double = 0.3

    // For auto-scroll logic
    @State private var userHasScrolledUp = false

    // For share sheet
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    // Decide final offset after drag ends
    private func finalizeDrag() {
        // If offset is > 0, we consider left side open or close
        if dragOffset > 0 {
            if dragOffset > sideMenuWidth * UIConstants.sideMenuSwipeThreshold {
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = sideMenuWidth
                }
                isLeftOpen = true
                isRightOpen = false
                if viewModel.isRecording {
                    Task { await viewModel.recorder?.stopRecording() }
                }
            } else {
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = 0
                }
                isLeftOpen = false
                isRightOpen = false
            }
        }
        // If offset < 0, we consider right side
        else if dragOffset < 0 {
            if abs(dragOffset) > sideMenuWidth * UIConstants.sideMenuSwipeThreshold {
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = -sideMenuWidth
                }
                isRightOpen = true
                isLeftOpen = false
                if viewModel.isRecording {
                    Task { await viewModel.recorder?.stopRecording() }
                }
            } else {
                withAnimation(.easeOut(duration: animationDuration)) {
                    dragOffset = 0
                }
                isLeftOpen = false
                isRightOpen = false
            }
        }
        // Otherwise near zero => closed
        else {
            isLeftOpen = false
            isRightOpen = false
        }
        print("finalize drag =>", dragOffset)
    }

    /// Compute overlay alpha based on absolute offset
    private var overlayAlpha: Double {
        let fraction = Double(abs(dragOffset)) / Double(sideMenuWidth)
        // up to 0.9 alpha
        return fraction * 0.3
    }

    // Doggy icon based on amplitude
    private var doggyIconName: String {
        let amp = viewModel.currentAmplitude
        switch amp {
        case ..<0.02:
            return "doggy-sound-0"
        case ..<0.04:
            return "doggy-sound-1"
        case ..<0.075:
            return "doggy-sound-2"
    default:
        return "doggy-sound-3"
    }
    }

    var body: some View {
    ZStack(alignment: .leading) {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .trim(from: 0, to: max(0, (verticalDrag - UIConstants.shareProgressStartThreshold) / (UIConstants.shareActivationThreshold - UIConstants.shareProgressStartThreshold)))
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 60, height: 60)
 
                    Image(systemName: "square.and.arrow.up")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            .padding(.bottom, 28)
        }
        .zIndex(0)
            // Left menu
            SessionSidebarView(
                onSessionClose: {
                    withAnimation(.easeOut(duration: animationDuration)) {
                        dragOffset = 0
                        isLeftOpen = false
                        isRightOpen = false
                    }
                },
                viewModel: viewModel,
                currentSessionID: viewModel.currentSessionMetadata?.id
            )
            .frame(width: sideMenuWidth)
            .offset(x: dragOffset - sideMenuWidth)

            // Right menu
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

        // Main content
        ZStack {
            Color.orange.ignoresSafeArea()
 
            mainContent
            Color.black
                .opacity(overlayAlpha)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation(.easeOut(duration: animationDuration)) {
                        dragOffset = 0
                        isLeftOpen = false
                        isRightOpen = false
                    }
                }
                .allowsHitTesting(overlayAlpha > 0.01)
        }
            .offset(x: dragOffset, y: -verticalDrag)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)
 
                        guard !gestureDirectionLocked else {
                            if isVerticalSwipe {
                            if !viewModel.yaps.isEmpty && !isLeftOpen && !isRightOpen && value.translation.height < 0 {
                                    verticalDrag = min(abs(value.translation.height), UIConstants.shareActivationThreshold)
                                }
                            } else {
                                let base: CGFloat
                                if isLeftOpen {
                                    base = sideMenuWidth
                                } else if isRightOpen {
                                    base = -sideMenuWidth
                                } else {
                                    base = 0
                                }
                                let newOffset = base + value.translation.width
                                dragOffset = newOffset.clamped(to: -sideMenuWidth...sideMenuWidth)
                            }
                            return
                        }
 
                        // Lock direction once clear
                        if horizontal >= 10 || vertical >= 10 {
                            gestureDirectionLocked = true
                            isVerticalSwipe = vertical > horizontal
                        }
                    }
                    .onEnded { value in
                        if gestureDirectionLocked && isVerticalSwipe {
                        if verticalDrag >= UIConstants.shareActivationThreshold {
                            DispatchQueue.main.async {
                                shareItems = [viewModel.yaps.map(\.text).joined(separator: " ")]
                                showShareSheet = true
                            }
                            withAnimation(.easeOut(duration: animationDuration)) {
                                verticalDrag = UIConstants.shareActivationThreshold
                            }
                        } else {
                            withAnimation(.easeOut(duration: animationDuration)) {
                                verticalDrag = 0
                            }
                        }
                        } else {
                            finalizeDrag()
                        }
                        gestureDirectionLocked = false
                    }
            )
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: animationDuration)) {
                    verticalDrag = 0
                }
            }
        }) {
            ActivityViewControllerWrapper(activityItems: shareItems)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            viewModel.saveCurrentSessionMetadata()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 10) {
            // Top row: Left & right toggles
            ZStack(alignment: .top) {
                HStack {
                    // Folder (left) toggle
                    Button {
                        withAnimation(.easeOut(duration: animationDuration)) {
                            if isLeftOpen {
                                dragOffset = 0
                                isLeftOpen = false
                            } else {
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
                        .padding(.leading, 5)

                    Spacer()

                    // Gear (right) toggle
                    Button {
                        withAnimation(.easeOut(duration: animationDuration)) {
                            if isRightOpen {
                                dragOffset = 0
                                isRightOpen = false
                            } else {
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
                .padding(.horizontal, 24)
            }
            .frame(height: 56)

            HStack {
                ForEach(TabType.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.rawValue)
                            .fontWeight(selectedTab == tab ? .bold : .regular)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                            .background(
                                selectedTab == tab ? Color.white.opacity(0.1) : Color.clear
                            )
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 24)

            // Middle text scroller
            if selectedTab == .transcribe {
                ScrollView {
                    Text(viewModel.yaps.map(\.text).joined(separator: " "))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.bottom, 16)

                // Yaps list
                if debugModeEnabled {
                    if viewModel.yaps.isEmpty {
                        Text("No yaps recorded yet.")
                            .foregroundColor(.white)
                            .padding()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: true) {
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
                    }
                }
            } else {
                Text("Coming soon: Generation mode")
                    .foregroundColor(.white.opacity(0.7))
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

            // Big record/pause button
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
