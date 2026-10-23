import SwiftUI

extension Notification.Name {
    static let hardcoverAccountDidChange = Notification.Name("HardcoverAccountDidChange")
}

struct ExplorerView: View {
    @State private var selectedSection = 0
    @State private var showingApiSettings = false
    @State private var showingHiddenSuggestions = false
    let onDone: (Bool) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedSection) {
                    Text("Trending").tag(0)
                    Text("Upcoming").tag(1)
                    Text("Lists").tag(2)
                    Text("Series").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Preserve each section's results, filters and scroll position.
                ZStack {
                    TrendingBooksView(isActive: selectedSection == 0, onDone: onDone)
                        .opacity(selectedSection == 0 ? 1 : 0)
                        .allowsHitTesting(selectedSection == 0)
                        .accessibilityHidden(selectedSection != 0)
                    CommunityUpcomingView(isActive: selectedSection == 1)
                        .opacity(selectedSection == 1 ? 1 : 0)
                        .allowsHitTesting(selectedSection == 1)
                        .accessibilityHidden(selectedSection != 1)
                    CommunityListsView(isActive: selectedSection == 2)
                        .opacity(selectedSection == 2 ? 1 : 0)
                        .allowsHitTesting(selectedSection == 2)
                        .accessibilityHidden(selectedSection != 2)
                    SeriesSuggestionsView()
                        .opacity(selectedSection == 3 ? 1 : 0)
                        .allowsHitTesting(selectedSection == 3)
                        .accessibilityHidden(selectedSection != 3)
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedSection == 3 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Hidden", systemImage: "eye.slash") { showingHiddenSuggestions = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingApiSettings = true }
                }
            }
            .sheet(isPresented: $showingApiSettings) { ApiKeySettingsView() }
            .sheet(isPresented: $showingHiddenSuggestions) {
                NavigationStack {
                    HiddenSuggestionsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showingHiddenSuggestions = false }
                            }
                        }
                }
            }
        }
    }
}


struct ExploreLoadFeedback: View {
    let isLoading: Bool
    let error: String?
    let isEmpty: Bool
    let emptyTitle: LocalizedStringKey
    let retry: () -> Void

    var body: some View {
        if isLoading { ProgressView().frame(maxWidth: .infinity).padding() }
        if let error {
            InlineLoadError(message: error, retry: retry).padding()
        } else if isEmpty && !isLoading {
            ContentUnavailableView(emptyTitle, systemImage: "books.vertical")
        }
    }
}
