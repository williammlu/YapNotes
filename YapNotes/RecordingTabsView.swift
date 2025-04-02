import SwiftUI

struct RecordingTabsView<Tab: Hashable & RawRepresentable & CaseIterable & Equatable>: View where Tab.RawValue == String {
    let tabs: [Tab]
    @Binding var selectedTab: Tab
    
    var body: some View {
        HStack {
            ForEach(tabs, id: \.self) { tab in
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
    }
}