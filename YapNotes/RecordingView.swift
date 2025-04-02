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
    
    
    @State private var generateSummary: String = ""
    @State private var hasGeneratedSummary = false
    @State private var isGeneratingSummary = false
    // For auto-scroll logic
    @State private var userHasScrolledUp = false
    
    // For share sheet
    @State private var showShareSheet = false
    @State private var shareContent: String = ""
    
    // Decide final offset after drag ends
    private func finalizeDrag() {
        // If offset is > 0, we consider left side open or close
        if dragOffset > 0 {
            let threshold = sideMenuWidth * (isLeftOpen ? (1.0 - UIConstants.sideMenuSwipeThreshold) : UIConstants.sideMenuSwipeThreshold)
            if dragOffset >= threshold {
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
            let threshold = sideMenuWidth * (isRightOpen ? (1.0 - UIConstants.sideMenuSwipeThreshold) : UIConstants.sideMenuSwipeThreshold)
            if dragOffset <= -threshold {
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
            // Share progress ring fixed at bottom (centered horizontally)
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
                        if horizontal >= 10 || vertical >= 10 {
                            gestureDirectionLocked = true
                            isVerticalSwipe = vertical > horizontal
                        }
                    }
                    .onEnded { value in
                        if gestureDirectionLocked && isVerticalSwipe {
                            if verticalDrag >= UIConstants.shareActivationThreshold {
                                DispatchQueue.main.async {
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
        .sheet(isPresented: Binding(
            get: {
                showShareSheet && !shareContent.isEmpty && shareContent.lengthOfBytes(using: .utf8) > 0
            },
            set: { showShareSheet = $0 }
        ), onDismiss: {
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: animationDuration)) {
                    verticalDrag = 0
                }
            }
        }) {
            ActivityViewControllerWrapper(activityItems: [shareContent])
                .presentationDetents([.medium, .large])
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            viewModel.saveCurrentSessionMetadata()
        }
        .onChange(of: viewModel.transcribedText) { text in
            shareContent = text
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
            
            // Tab selector
            HStack {
                ForEach(TabType.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.rawValue)
                            .fontWeight(selectedTab == tab ? .bold : .regular)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                            .background(selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            if selectedTab == .transcribe {
                
                // Transcript text
                ScrollView {
                    Text(viewModel.transcribedText)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.bottom, 16)
            } else {
                // Generate tab
                VStack(alignment: .leading, spacing: 12) {
                    Button("Regenerate Summary") {
                        // Optionally trigger summary regeneration here.
                    }
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    
                    if isGeneratingSummary {
                        Text("Generating summary...")
                            .foregroundColor(.white.opacity(0.7))
                            .padding()
                    } else {
                        ScrollView {
                            Text(generateSummary.isEmpty ? "No summary available." : generateSummary)
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                }
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
            
            // Big record/pause button shown only on Transcribe tab
            if selectedTab == .transcribe {
                VStack {
                    Spacer()
                    HStack(alignment: .center) {
                        Spacer()
                        // X button
                        Button {
                            viewModel.clearTranscribedText()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.white)
                                .font(.title)
                                .padding(12)
                                .background(Color.black.opacity(0.2))
                                .clipShape(Circle())
                        }
                        Spacer()
                        // Record/pause button
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
                        // Backspace button
                        Button {
                            viewModel.removeLastWordFromTranscribedText()
                        } label: {
                            Image(systemName: "delete.left")
                                .foregroundColor(.white)
                                .font(.title)
                                .padding(12)
                                .background(Color.black.opacity(0.2))
                                .clipShape(Circle())
                                .offset(x: -2) // Nudge the icon 2px to the left
                        }
                        Spacer()
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }
}
