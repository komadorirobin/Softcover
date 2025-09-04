import SwiftUI

struct UpcomingReleasesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var releases: [HardcoverService.UpcomingRelease] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(NSLocalizedString("Loading upcoming releases…", comment: "Loading state for upcoming releases"))
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text(NSLocalizedString("Failed to load upcoming releases", comment: "Title for error when loading upcoming releases fails"))
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button(NSLocalizedString("Try Again", comment: "Retry button")) {
                            Task { await loadReleases() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if releases.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("No upcoming releases found", comment: "Empty state title when no upcoming releases"))
                            .font(.headline)
                        Text(NSLocalizedString("We’ll show future editions from your Want to Read list here.", comment: "Empty state subtitle for upcoming releases"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(releases) { item in
                            HStack(spacing: 12) {
                                if let data = item.coverImageData, let ui = UIImage(data: data) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 72)
                                        .clipped()
                                        .cornerRadius(6)
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(UIColor.tertiarySystemFill))
                                        .frame(width: 48, height: 72)
                                        .overlay(Image(systemName: "book").foregroundColor(.secondary))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(2)

                                    Text(item.author)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)

                                    HStack(spacing: 6) {
                                        Image(systemName: "calendar")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(formatted(date: item.releaseDate))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        if let badge = daysBadge(for: item.releaseDate) {
                                            Text(badge.text)
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(badge.color.opacity(0.15))
                                                .foregroundColor(badge.color)
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(NSLocalizedString("Upcoming Releases", comment: "Navigation title for upcoming releases screen"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "Done button title")) { dismiss() }
                }
            }
        }
        .task { await loadReleases() }
    }

    private func loadReleases() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        let items = await HardcoverService.fetchUpcomingReleasesFromWantToRead(limit: 30)
        await MainActor.run {
            releases = items
            isLoading = false
            if items.isEmpty {
                errorMessage = nil
            }
        }
    }

    private func formatted(date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private func daysBadge(for date: Date) -> (text: String, color: Color)? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: date)
        guard let days = cal.dateComponents([.day], from: start, to: target).day else { return nil }
        if days < 0 {
            return (NSLocalizedString("Released", comment: "Badge for already released item"), .gray)
        } else if days == 0 {
            return (NSLocalizedString("Today", comment: "Badge for release happening today"), .green)
        } else if days == 1 {
            return (NSLocalizedString("Tomorrow", comment: "Badge for release happening tomorrow"), .green)
        } else {
            // Use pluralizable format key "In %d days"
            let text = String.localizedStringWithFormat(
                NSLocalizedString("In %d days", comment: "Badge for release happening in N days"),
                days
            )
            return (text, .blue)
        }
    }
}

#Preview {
    UpcomingReleasesView()
}
