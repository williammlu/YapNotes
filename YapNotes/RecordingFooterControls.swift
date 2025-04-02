import SwiftUI

struct RecordingFooterControls: View {
    var onClearText: () -> Void
    var onToggleRecording: () -> Void
    var isRecording: Bool
    var onRemoveLastWord: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .center) {
                Spacer()
                Button {
                    onClearText()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.title)
                        .padding(12)
                        .background(Color.black.opacity(0.2))
                        .clipShape(Circle())
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(isRecording ? .white : .red)
                        .frame(width: 70, height: 70)
                    Circle()
                        .stroke(.white, lineWidth: 2)
                        .frame(width: 74, height: 74)
                    if isRecording {
                        Image(systemName: "pause.fill")
                            .foregroundColor(.red)
                            .font(.title)
                    }
                }
                .onTapGesture {
                    onToggleRecording()
                }
                Spacer()
                Button {
                    onRemoveLastWord()
                } label: {
                    Image(systemName: "delete.left")
                        .foregroundColor(.white)
                        .font(.title)
                        .padding(12)
                        .background(Color.black.opacity(0.2))
                        .clipShape(Circle())
                        .offset(x: -2)
                }
                Spacer()
            }
            .padding(.bottom, 32)
        }
    }
}