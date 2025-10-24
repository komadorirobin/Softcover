import SwiftUI

struct StatsView: View {
    @State private var readingStats: HardcoverService.ReadingStats?
    @State private var readingGoals: [ReadingGoal] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadingTask: Task<Void, Never>?
    
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
                            Task { await loadData() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    // Reading Statistics Section
                    if let stats = readingStats {
                        VStack(alignment: .leading, spacing: 16) {
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 16) {
                                // Books Read
                                StatCard(
                                    icon: "checkmark.circle.fill",
                                    iconColor: .green,
                                    title: "Books Read",
                                    value: "\(stats.booksFinished)"
                                )
                                
                                // Pages Read
                                StatCard(
                                    icon: "doc.text.fill",
                                    iconColor: .purple,
                                    title: "Pages Read",
                                    value: "\(stats.estimatedPages)"
                                )
                                
                                // Average Rating
                                if let avgRating = stats.averageRating {
                                    StatCard(
                                        icon: "star.fill",
                                        iconColor: .yellow,
                                        title: "Average Rating",
                                        value: String(format: "%.1f", avgRating)
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Reading Goals Section
                    if !readingGoals.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "target")
                                    .foregroundColor(.blue)
                                Text("Reading Goals")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal)
                            
                            ForEach(readingGoals, id: \.id) { goal in
                                ReadingGoalCard(goal: goal)
                            }
                        }
                    }
                    
                    if readingGoals.isEmpty && readingStats == nil {
                        VStack(spacing: 20) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text("No statistics available")
                                .font(.headline)
                            Text("Start reading and setting goals to see your statistics here")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Reading Stats")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await loadData()
        }
        .onAppear {
            // Only load data if we don't have any yet or if not currently loading
            if readingGoals.isEmpty && readingStats == nil && loadingTask == nil {
                Task {
                    await loadData()
                }
            }
        }
    }
    
    private func loadData() async {
        // Cancel any existing loading task
        loadingTask?.cancel()
        
        loadingTask = Task {
            await MainActor.run {
                isLoading = true
                errorMessage = nil
            }
            
            do {
                // Load reading goals and stats in parallel
                async let goals = HardcoverService.fetchReadingGoals()
                async let stats = HardcoverService.fetchReadingStats(year: nil)
                
                let loadedGoals = await goals
                let loadedStats = await stats
                
                // Check if task was cancelled before updating UI
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    readingGoals = loadedGoals
                    readingStats = loadedStats
                    isLoading = false
                }
                
                print("✅ Loaded \(loadedGoals.count) reading goals and stats: \(loadedStats != nil)")
                // Debug: Print goal details
                for goal in loadedGoals {
                    print("📊 Goal ID \(goal.id): \(goal.goal) \(goal.metric), progress: \(goal.progress), description: \(goal.description ?? "nil")")
                }
                
            } catch {
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    errorMessage = "Failed to load reading data: \(error.localizedDescription)"
                    isLoading = false
                }
                print("❌ Error loading stats: \(error)")
            }
        }
        
        await loadingTask?.value
    }
}

struct ReadingGoalCard: View {
    let goal: ReadingGoal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(translatedGoalDescription)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 8) {
                        Image(systemName: goalIcon)
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text(String(format: NSLocalizedString("%lld of %lld %@s", comment: ""), goal.progress, goal.goal, NSLocalizedString("books", comment: "")))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(Int(goal.percentComplete * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(progressColor)
                        
                        // Show celebration emoji when goal is 100% complete
                        if goal.percentComplete >= 1.0 {
                            Text("🎉")
                                .font(.title2)
                                .scaleEffect(1.2)
                                .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: goal.percentComplete >= 1.0)
                        }
                    }
                    
                    Text(goal.percentComplete >= 1.0 ? "Completed!" : "Complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(progressColor)
                        .frame(width: geometry.size.width * goal.percentComplete, height: 8)
                        .cornerRadius(4)
                        .animation(.easeInOut(duration: 0.5), value: goal.percentComplete)
                }
            }
            .frame(height: 8)
            
            // Schedule status (ahead/behind)
            if let schedule = scheduleStatus() {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(schedule.color)
                        .font(.caption)
                    Text(schedule.text)
                        .font(.caption)
                        .foregroundColor(schedule.color)
                }
            }
            
            // Goal period
            HStack {
                Text(formatDate(goal.startDate))
                Text("to")
                Text(formatDate(goal.endDate))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
    }
    
    private var translatedGoalDescription: String {
        guard let description = goal.description else {
            return NSLocalizedString("Reading Goal", comment: "")
        }
        
        // Check if description matches pattern like "2025 Reading Goal"
        if let regex = try? NSRegularExpression(pattern: "^(\\d{4}) Reading Goal$", options: []) {
            let range = NSRange(location: 0, length: description.count)
            if let match = regex.firstMatch(in: description, options: [], range: range) {
                let yearRange = Range(match.range(at: 1), in: description)!
                let year = String(description[yearRange])
                
                // Return localized format
                if Locale.current.language.languageCode?.identifier == "sv" {
                    return "Läsmål för \(year)"
                } else {
                    return "\(year) Reading Goal"
                }
            }
        }
        
        // If no pattern match, return original description
        return description
    }
    
    private var goalIcon: String {
        switch goal.metric.lowercased() {
        case "book":
            return "book"
        case "page":
            return "doc.text"
        default:
            return "target"
        }
    }
    
    private var progressColor: Color {
        let percentage = goal.percentComplete
        if percentage >= 1.0 {
            return .green
        } else if percentage >= 0.75 {
            return .blue
        } else if percentage >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateString) {
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
        
        return dateString
    }
    
    // MARK: - Ahead/Behind schedule
    private func scheduleStatus() -> (text: String, color: Color)? {
        // Only show for known metrics (books/pages). If metric is something else, skip.
        let metric = goal.metric.lowercased()
        guard metric == "book" || metric == "page" else { return nil }
        
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        
        guard let start = df.date(from: goal.startDate),
              let end = df.date(from: goal.endDate) else {
            return nil
        }
        
        // Clamp "today" to [start, end]
        let now = Date()
        let today = min(max(now, start), end)
        
        let total = max(end.timeIntervalSince(start), 1) // avoid /0
        let elapsed = max(min(today.timeIntervalSince(start), total), 0)
        let fraction = elapsed / total
        
        let expected = Int((Double(goal.goal) * fraction).rounded())
        let finished = goal.progress
        let delta = finished - expected
        
        let unit = metric == "page" ? NSLocalizedString("pages", comment: "") : NSLocalizedString("books", comment: "")
        
        if delta > 0 {
            let text = String(format: NSLocalizedString("You're %d %@ ahead of schedule.", comment: ""), delta, unit)
            return (text, .green)
        } else if delta < 0 {
            let text = String(format: NSLocalizedString("You're %d %@ behind schedule.", comment: ""), abs(delta), unit)
            return (text, .red)
        } else {
            let text = NSLocalizedString("You're right on schedule.", comment: "")
            return (text, .secondary)
        }
    }
}

struct ReadingStatsCard: View {
    let stats: HardcoverService.ReadingStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                StatItem(
                    title: NSLocalizedString("Books Finished", comment: ""),
                    value: "\(stats.booksFinished)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                StatItem(
                    title: NSLocalizedString("Pages Read", comment: ""),
                    value: "\(stats.estimatedPages)",
                    icon: "doc.text.fill",
                    color: .blue
                )
            }
            
            if let avgRating = stats.averageRating {
                StatItem(
                    title: NSLocalizedString("Average Rating", comment: ""),
                    value: String(format: "%.1f", avgRating),
                    icon: "star.fill",
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    StatsView()
}
