import SwiftUI
import UIKit

struct UpcomingReleasesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var releases: [HardcoverService.UpcomingRelease] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var limit = 30
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading && releases.isEmpty {
                    ProgressView("Hämtar kommande släpp…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, releases.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundColor(.orange)
                        Text(err)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Försök igen") { Task { await load(reset: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if releases.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("Inga kommande släpp hittades")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(releases, id: \.id) { item in
                                ReleaseRow(item: item)
                            }
                        }
                        
                        if releases.count >= limit {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                } else {
                                    Button("Visa fler") {
                                        limit += 30
                                        Task { await load(reset: true) }
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Kommande släpp")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await load(reset: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Uppdatera")
                    }
                }
            }
            .task { await load(reset: true) }
            .refreshable { await load(reset: true) }
        }
    }
    
    private func load(reset: Bool) async {
        await MainActor.run {
            if reset { errorText = nil }
            isLoading = true
        }
        let list = await HardcoverService.fetchUpcomingReleasesFromWantToRead(limit: limit)
        await MainActor.run {
            releases = list
            isLoading = false
            if list.isEmpty {
                errorText = nil // tomtillstånd utan fel
            }
        }
    }
}

private struct ReleaseRow: View {
    let item: HardcoverService.UpcomingRelease
    
    var body: some View {
        HStack(spacing: 12) {
            cover
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(item.author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack {
                    let d = daysUntil(item.releaseDate)
                    Text(d <= 0 ? NSLocalizedString("Idag", comment: "") : String(format: NSLocalizedString("%d dagar kvar", comment: ""), d))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDate(item.releaseDate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
    
    private var cover: some View {
        Group {
            if let data = item.coverImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.gray.opacity(0.15)
                    Image(systemName: "book.closed")
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(width: 44, height: 62)
        .clipped()
        .cornerRadius(6)
    }
}

// Helpers
private func daysUntil(_ date: Date) -> Int {
    let cal = Calendar.current
    let startToday = cal.startOfDay(for: Date())
    let startTarget = cal.startOfDay(for: date)
    return cal.dateComponents([.day], from: startToday, to: startTarget).day ?? 0
}

private func formatDate(_ date: Date) -> String {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .none
    return df.string(from: date)
}
