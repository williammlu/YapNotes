import SwiftUI
import UniformTypeIdentifiers

struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    let maxBarHeight: CGFloat = 200.0

    // Control the visibility of custom side menus
    @State private var showLeftMenu = false
    @State private var showRightMenu = false

    // For auto-scroll logic
    @State private var userHasScrolledUp = false

    // For share sheet
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    // Constants
    private let sideMenuWidth: CGFloat = 250
    private let edgeTriggerWidth: CGFloat = 30
    private let animationDuration: Double = 0.25

    // The main offset for content
    private var mainContentOffsetX: CGFloat {
        if showLeftMenu {
            return sideMenuWidth
        } else if showRightMenu {
            return -sideMenuWidth
        } else {
            return 0
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
            // The left side menu
            SessionSidebarView(onSessionClose: {
                withAnimation(.linear(duration: animationDuration)) {
                    showLeftMenu = false
                }
            })
            .frame(width: sideMenuWidth)
            .offset(x: showLeftMenu ? 0 : -sideMenuWidth)

            // The right side menu
            HStack {
                Spacer()
                SettingsView(onClose: {
                    withAnimation(.linear(duration: animationDuration)) {
                        showRightMenu = false
                    }
                })
                .frame(width: sideMenuWidth)
                .offset(x: showRightMenu ? 0 : sideMenuWidth)
            }

            // The main center content
            ZStack(alignment: .leading) {
                Color.orange.ignoresSafeArea()

                // Main UI
                mainRecordingContent

                // Dark overlay only in center, if a menu is open
                if showLeftMenu || showRightMenu {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.linear(duration: animationDuration)) {
                                showLeftMenu = false
                                showRightMenu = false
                            }
                        }
                }

                // Invisible edge triggers for left & right swipes
                // Left trigger
                HStack { }
                    .frame(width: edgeTriggerWidth)
                    .contentShape(Rectangle())
                    .onTapGesture { /* do nothing, purely for drag detection */ }
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                // If the user drags right from the left edge, open left menu
                                if value.translation.width > 40 && !showRightMenu {
                                    withAnimation(.linear(duration: animationDuration)) {
                                        showLeftMenu = true
                                        showRightMenu = false
                                    }
                                }
                            }
                    )

                // Right trigger
                HStack { Spacer() }
                    .frame(width: edgeTriggerWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                // If the user drags left from the right edge, open right menu
                                if value.translation.width < -40 && !showLeftMenu {
                                    withAnimation(.linear(duration: animationDuration)) {
                                        showRightMenu = true
                                        showLeftMenu = false
                                    }
                                }
                            }
                    )
            }
            .offset(x: mainContentOffsetX)
            .animation(.linear(duration: animationDuration), value: showLeftMenu)
            .animation(.linear(duration: animationDuration), value: showRightMenu)
            .onChange(of: showLeftMenu) { newVal in
                if newVal, viewModel.isRecording {
                    // Pause if currently recording
                    Task { await viewModel.recorder?.stopRecording() }
                }
            }
            .onChange(of: showRightMenu) { newVal in
                if newVal, viewModel.isRecording {
                    // Pause if currently recording
                    Task { await viewModel.recorder?.stopRecording() }
                }
            }
        }
    }

    private var mainRecordingContent: some View {
        VStack(spacing: 10) {
            // Top row
            HStack {
                // Folder button => toggle left
                Button {
                    withAnimation(.linear(duration: animationDuration)) {
                        showLeftMenu.toggle()
                        showRightMenu = false
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

                // Gear => toggle right
                Button {
                    withAnimation(.linear(duration: animationDuration)) {
                        showRightMenu.toggle()
                        showLeftMenu = false
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title)
                        .foregroundColor(.red)
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

            // The yaps list
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
