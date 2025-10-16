import SwiftUI

struct OtherUserStatsView: View {
    let username: String
    @State private var stats: UserStats?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading statistics...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Failed to load statistics")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await loadStats() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else if let stats = stats {
                    VStack(alignment: .leading, spacing: 16) {
                        // Stats Grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            // Books Read
                            if let booksRead = stats.booksRead {
                                StatCard(
                                    icon: "checkmark.circle.fill",
                                    iconColor: .green,
                                    title: "Books Read",
                                    value: "\(booksRead)"
                                )
                            }
                            
                            // Pages Read
                            if let pagesRead = stats.pagesRead {
                                StatCard(
                                    icon: "doc.text.fill",
                                    iconColor: .purple,
                                    title: "Pages Read",
                                    value: "\(pagesRead)"
                                )
                            }
                            
                            // Authors Read
                            if let authorsRead = stats.authorsRead {
                                StatCard(
                                    icon: "person.fill",
                                    iconColor: .orange,
                                    title: "Authors Read",
                                    value: "\(authorsRead)"
                                )
                            }
                            
                            // Reviews Written
                            if let reviewsWritten = stats.reviewsWritten {
                                StatCard(
                                    icon: "pencil.line",
                                    iconColor: .blue,
                                    title: "Reviews Written",
                                    value: "\(reviewsWritten)"
                                )
                            }
                            
                            // Hours Listened
                            if let hoursListened = stats.hoursListened {
                                StatCard(
                                    icon: "headphones",
                                    iconColor: .pink,
                                    title: "Hours Listened",
                                    value: String(format: "%.1f", hoursListened)
                                )
                            }
                            
                            // Currently Reading
                            if let currentlyReading = stats.currentlyReading {
                                StatCard(
                                    icon: "book.fill",
                                    iconColor: .cyan,
                                    title: "Currently Reading",
                                    value: "\(currentlyReading)"
                                )
                            }
                            
                            // Want to Read
                            if let wantToRead = stats.wantToRead {
                                StatCard(
                                    icon: "bookmark.fill",
                                    iconColor: .yellow,
                                    title: "Want to Read",
                                    value: "\(wantToRead)"
                                )
                            }
                        }
                        .padding(.horizontal)
                        
                        // Average Rating
                        if let avgRating = stats.averageRating, let totalRatings = stats.totalRatings {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Average Rating")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                HStack(spacing: 12) {
                                    HStack(spacing: 4) {
                                        ForEach(0..<5) { index in
                                            Image(systemName: index < Int(avgRating.rounded()) ? "star.fill" : "star")
                                                .foregroundColor(.yellow)
                                        }
                                    }
                                    
                                    Text(String(format: "%.1f", avgRating))
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                    
                                    Text("(\(totalRatings) ratings)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No statistics available")
                            .font(.headline)
                        Text("This user hasn't shared any statistics yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("@\(username)'s Stats")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadStats()
        }
    }
    
    private func loadStats() async {
        isLoading = true
        errorMessage = nil
        
        if let fetchedStats = await HardcoverService.fetchUserStats(username: username) {
            stats = fetchedStats
        } else {
            errorMessage = "Could not load statistics"
        }
        
        isLoading = false
    }
}

struct StatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.title2)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 32, weight: .bold))
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        OtherUserStatsView(username: "example")
    }
}
