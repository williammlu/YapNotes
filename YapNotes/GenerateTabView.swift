import SwiftUI

struct GenerateTabView: View {
    let generateSummary: String
    let isGeneratingSummary: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Regenerate Summary") {
                // Hook up your generation logic here
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
}