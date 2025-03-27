import SwiftUI

struct SettingsView: View {
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            Color(.systemGray6).edgesIgnoringSafeArea(.vertical)
            VStack(alignment: .leading) {
                HStack {
                    Text("Settings")
                        .font(.headline)
                    Spacer()
                    Button("Close") {
                        onClose()
                    }
                }
                .padding()

                // Insert your settings controls here
                Form {
                    Section(header: Text("General")) {
                        Toggle("Some Setting", isOn: .constant(true))
                        Toggle("Another Option", isOn: .constant(false))
                    }
                }

                Spacer()
            }
            .padding(.top, 20)
        }
    }
}