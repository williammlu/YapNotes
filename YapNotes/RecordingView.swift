import SwiftUI
import UniformTypeIdentifiers

struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    let maxBarHeight: CGFloat = 200.0

    // Control left/right side menus
    @State private var showLeftMenu = false
    @State private var showRightMenu = false

    // For auto-scroll logic
    @State private var userHasScrolledUp = false

    // For share sheet
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    // Constants
    private let sideMenuWidth: CGFloat = 250
    private let animationDuration: Double = 0.25
    private let edgeThreshold: CGFloat = 40
    private let dragOpenThreshold: CGFloat = 40

    // The main offset for center content
    private var mainContentOffsetX: CGFloat {
        if showLeftMenu { return sideMenuWidth }
        else if showRightMenu { return -sideMenuWidth }
        else { return 0 }
    }

    // Doggy icon name
    private var doggyIconName: String {
        let amp = viewModel.currentAmplitude
        if amp < 0.02 { return "doggy-sound-0" }
        else if amp < 0.04 { return "doggy-sound-1" }
        else if amp < 0.075 { return "doggy-sound-2" }
        else { return "doggy-sound-3" }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // 1) Left side menu behind everything
            SessionSidebarView {
                withAnimation(.linear(duration: animationDuration)) {
                    showLeftMenu = false
                }
            }
            .frame(width: sideMenuWidth)
            .offset(x: showLeftMenu ? 0 : -sideMenuWidth)

            // 2) Right side menu
            HStack {
                Spacer()
                SettingsView {
                    withAnimation(.linear(duration: animationDuration)) {
                        showRightMenu = false
                    }
                }
                .frame(width: sideMenuWidth)
                .offset(x: showRightMenu ? 0 : sideMenuWidth)
            }

            // 3) Main content, offset left/right
            mainCenterContent
                .offset(x: mainContentOffsetX)
                .animation(.linear(duration: animationDuration), value: showLeftMenu)
                .animation(.linear(duration: animationDuration), value: showRightMenu)

            // 4) Top-level overlay (not offset!) 
            // If either menu is open, show a dark overlay
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
        }
        // Pause recording if user opens a side
        .onChange(of: showLeftMenu) { newVal in
            if newVal, viewModel.isRecording {
                Task { await viewModel.recorder?.stopRecording() }
            }
        }
        .onChange(of: showRightMenu) { newVal in
            if newVal, viewModel.isRecording {
                Task { await viewModel.recorder?.stopRecording() }
            }
        }
        // Single drag for open logic
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    let screenWidth = UIScreen.main.bounds.width
                    let startX = value.startLocation.x
                    let totalDX = value.translation.width

                    // If user started near left edge & dragged right
                    if startX < edgeThreshold && totalDX > dragOpenThreshold {
                        // open left if right isn't open
                        if !showRightMenu {
                            withAnimation(.linear(duration: animationDuration)) {
                                showLeftMenu = true
                                showRightMenu = false
                            }
                            if viewModel.isRecording {
                                Task { await viewModel.recorder?.stopRecording() }
                            }
                        }
                    }
                    // If user started near right edge & dragged left
                    else if startX > screenWidth - edgeThreshold && totalDX < -dragOpenThreshold {
                        // open right if left isn't open
                        if !showLeftMenu {
                            withAnimation(.linear(duration: animationDuration)) {
                                showRightMenu = true
                                showLeftMenu = false
                            }
                            if viewModel.isRecording {
                                Task { await viewModel.recorder?.stopRecording() }
                            }
                        }
                    }
                }
        )
    }

    // The main center content
    private var mainCenterContent: some View {
        ZStack {
            Color.orange.ignoresSafeArea()

            VStack(spacing: 10) {
                // Top row
                HStack {
                    Button {
                        withAnimation(.linear(duration: animationDuration)) {
                            showLeftMenu.toggle()
                            if showLeftMenu { showRightMenu = false }
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

                    Button {
                        withAnimation(.linear(duration: animationDuration)) {
                            showRightMenu.toggle()
                            if showRightMenu { showLeftMenu = false }
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

                BarWaveformView(
                    barAmplitudes: viewModel.barAmplitudes,
                    maxBarHeight: maxBarHeight
                )
                .frame(height: maxBarHeight)

                Spacer().frame(height: 10)

                // Yaps
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
    }

    private var allYapsConcatenated: String {
        viewModel.yaps.map { $0.text }.joined(separator: " ")
    }
}

struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
