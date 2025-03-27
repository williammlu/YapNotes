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
    // Decide how close to the edge we consider "edge swipe"
    private let edgeThreshold: CGFloat = 40
    // Decide how far horizontally user must drag to open menu
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
            // Left side menu
            SessionSidebarView {
                withAnimation(.linear(duration: animationDuration)) {
                    showLeftMenu = false
                }
            }
            .frame(width: sideMenuWidth)
            .offset(x: showLeftMenu ? 0 : -sideMenuWidth)

            // Right side menu
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

            // Main center content
            ZStack(alignment: .leading) {
                Color.orange.ignoresSafeArea()

                // The main UI
                mainRecordingContent

                // Dark overlay if a menu is open
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
            .offset(x: mainContentOffsetX)
            .animation(.linear(duration: animationDuration), value: showLeftMenu)
            .animation(.linear(duration: animationDuration), value: showRightMenu)
            .gesture(
                // Single drag gesture for the entire center area
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        let screenWidth = UIScreen.main.bounds.width
                        let startX = value.startLocation.x
                        let totalDX = value.translation.width

                        // If user started near the left edge & dragged right
                        if startX < edgeThreshold && totalDX > dragOpenThreshold {
                            // open left if right isn't open
                            if !showRightMenu {
                                withAnimation(.linear(duration: animationDuration)) {
                                    showLeftMenu = true
                                    showRightMenu = false
                                }
                                // Pause if currently recording
                                if viewModel.isRecording {
                                    Task { await viewModel.recorder?.stopRecording() }
                                }
                            }
                        }
                        // If user started near the right edge & dragged left
                        else if startX > screenWidth - edgeThreshold && totalDX < -dragOpenThreshold {
                            // open right if left isn't open
                            if !showLeftMenu {
                                withAnimation(.linear(duration: animationDuration)) {
                                    showRightMenu = true
                                    showLeftMenu = false
                                }
                                // Pause if currently recording
                                if viewModel.isRecording {
                                    Task { await viewModel.recorder?.stopRecording() }
                                }
                            }
                        }
                    }
            )
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
        }
    }

    private var mainRecordingContent: some View {
        VStack(spacing: 10) {
            // Top row
            HStack {
                // Folder -> open/close left
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
                // Gear -> open/close right
                Button {
                    withAnimation(.linear(duration: animationDuration)) {
                        showRightMenu.toggle()
                        if showRightMenu { showLeftMenu = false }
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

            // Bottom record button
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
