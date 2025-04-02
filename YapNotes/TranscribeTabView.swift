import SwiftUI

struct TranscribeTabView: View {
    let transcribedText: String
    
    var body: some View {
        ScrollView {
            Text(transcribedText)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.bottom, 16)
    }
}