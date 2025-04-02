import SwiftUI
import UniformTypeIdentifiers

fileprivate extension Comparable {
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
    
    enum TabType: String, CaseIterable {
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
        } else if dragOffset < 0 {
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
        } else {
            isLeftOpen = false
            isRightOpen = false
        }
    }
    
    private var overlayAlpha: Double {
        let fraction = Double(abs(dragOffset)) / Double(sideMenuWidth)
        return fraction * 0.3
    }
    
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
            // Share ring at bottom center
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .trim(from: 0,
                                  to: max(0, (verticalDrag - UIConstants.shareProgressStartThreshold) / (UIConstants.shareActivationThreshold - UIConstants.shareProgressStartThreshold)))
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
                mainContentView
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
                    .onEnded { _ in
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
    
    @ViewBuilder
    private var mainContentView: some View {
        VStack(spacing: 10) {
            RecordingHeaderView(
                onLeftMenuTapped: {
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
                },
                onRightMenuTapped: {
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
                },
                doggyIconName: doggyIconName
            )
            RecordingTabsView(
                tabs: TabType.allCases,
                selectedTab: $selectedTab
            )
            
            if selectedTab == .transcribe {
                TranscribeTabView(
                    transcribedText: viewModel.transcribedText
                )
            } else {
                GenerateTabView(
                    generateSummary: generateSummary,
                    isGeneratingSummary: isGeneratingSummary
                )
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
            
            if selectedTab == .transcribe {
                RecordingFooterControls(
                    onClearText: {
                        viewModel.clearTranscribedText()
                    },
                    onToggleRecording: {
                        Task { await viewModel.toggleRecording() }
                    },
                    isRecording: viewModel.isRecording,
                    onRemoveLastWord: {
                        viewModel.removeLastWordFromTranscribedText()
                    }
                )
            }
        }
    }
}