import SwiftUI

struct ExplorerView: View {
    @State private var selectedSection = 0
    @State private var showingApiSettings = false
    let onDone: (Bool) -> Void
    
    private var sectionInfoText: String {
        switch selectedSection {
        case 0:
            return "A list of what books are read the most on Hardcover."
        case 1:
            return "A list of what books are most anticipated on Hardcover."
        case 2:
            return "Lists are organized collections of books created by anyone. Create a list and maybe it'll get featured!"
        default:
            return ""
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segmented picker at the top
                Picker("Section", selection: $selectedSection) {
                    Text("Trending").tag(0)
                    Text("Upcoming").tag(1)
                    Text("Lists").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Info text based on selection
                VStack(spacing: 4) {
                    Text(sectionInfoText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                
                // Content based on selection
                switch selectedSection {
                case 0:
                    TrendingBooksView(onDone: onDone)
                case 1:
                    CommunityUpcomingView()
                case 2:
                    CommunityListsView()
                default:
                    EmptyView()
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { 
                        showingApiSettings = true 
                    } label: { 
                        Image(systemName: "gearshape") 
                    }
                }
            }
            .sheet(isPresented: $showingApiSettings) {
                ApiKeySettingsView { _ in
                    // Refresh if needed
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

#Preview {
    ExplorerView(onDone: { _ in })
}
