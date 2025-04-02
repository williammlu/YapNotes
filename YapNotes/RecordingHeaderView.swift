import SwiftUI

struct RecordingHeaderView: View {
    var onLeftMenuTapped: () -> Void
    var onRightMenuTapped: () -> Void
    var doggyIconName: String
    
    var body: some View {
        ZStack(alignment: .top) {
            HStack {
                Button {
                    onLeftMenuTapped()
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
                Button {
                    onRightMenuTapped()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 56)
    }
}