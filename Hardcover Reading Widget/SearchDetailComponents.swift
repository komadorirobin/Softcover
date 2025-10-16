import SwiftUI
import UIKit
import Foundation

struct BookHeaderView: View {
    let book: BookProgress
    let genres: [String]
    let moods: [String]
    let isLoadingGenres: Bool
    let isLoadingMoods: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Book cover - increased size for better resolution
            if let data = book.coverImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 180)
                    .clipped()
                    .cornerRadius(8)
                    .shadow(radius: 3)
            } else if let coverUrlString = book.coverImageUrl, let url = URL(string: coverUrlString) {
                // Use AsyncImage for URL-based covers
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 120, height: 180)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 180)
                            .clipped()
                            .cornerRadius(8)
                            .shadow(radius: 3)
                    case .failure:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(width: 120, height: 180)
                            .overlay(Image(systemName: "book.closed").foregroundColor(.secondary))
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(width: 120, height: 180)
                    .overlay(Image(systemName: "book.closed").foregroundColor(.secondary))
            }
            
            // Book metadata
            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(3)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // Genres chips
                if !genres.isEmpty {
                    WrapChipsView(items: genres)
                        .padding(.top, 2)
                } else if isLoadingGenres {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text(NSLocalizedString("Loading genres…", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
                
                // Separator if both exist
                if !genres.isEmpty && !moods.isEmpty {
                    Divider().padding(.vertical, 2)
                }
                
                // Moods chips
                if !moods.isEmpty {
                    WrapChipsView(items: moods)
                } else if isLoadingMoods {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text(NSLocalizedString("Loading moods…", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BookActionsView: View {
    let book: BookProgress
    let isWorking: Bool
    let isWorkingReading: Bool
    let isWorkingFinished: Bool
    let isLoadingEditions: Bool
    let onWantToRead: () -> Void
    let onReadNow: () -> Void
    let onMarkAsRead: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            Button(action: onWantToRead) {
                if isWorking || isLoadingEditions {
                    HStack {
                        Spacer()
                        ProgressView().scaleEffect(0.9)
                        Spacer()
                    }
                } else {
                    Label(NSLocalizedString("Add to Want to Read", comment: ""), systemImage: "bookmark.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || isLoadingEditions || book.bookId == nil)
            
            HStack(spacing: 10) {
                Button(action: onReadNow) {
                    if isWorkingReading || isLoadingEditions {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(0.9)
                            Spacer()
                        }
                    } else {
                        Label(NSLocalizedString("Läs\u{00A0}nu", comment: "Start reading now"), systemImage: "book.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .disabled(isWorkingReading || isLoadingEditions || book.bookId == nil)
                
                Button(action: onMarkAsRead) {
                    if isWorkingFinished || isLoadingEditions {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(0.9)
                            Spacer()
                        }
                    } else {
                        Label(NSLocalizedString("Markera som läst", comment: "Mark as read"), systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(isWorkingFinished || isLoadingEditions || book.bookId == nil)
            }
        }
    }
}

struct RateReviewSection: View {
    let book: BookProgress
    let selectedEditionId: Int?
    let isCreatingUserBook: Bool
    @Binding var ratingSheetUserBookId: Int?
    @Binding var showingRatingSheet: Bool
    let onCreateEntry: () async -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rate & Review")
                .font(.headline)
            
            Button {
                if let userBookId = book.userBookId {
                    ratingSheetUserBookId = userBookId
                    showingRatingSheet = true
                } else {
                    Task { await onCreateEntry() }
                }
            } label: {
                if isCreatingUserBook {
                    HStack {
                        Spacer()
                        ProgressView().scaleEffect(0.9)
                        Text("Creating entry...")
                            .font(.subheadline)
                        Spacer()
                    }
                } else {
                    Label("Rate & Review", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(book.bookId == nil || isCreatingUserBook)
        }
        .padding(.top, 4)
    }
}

struct BookDescriptionView: View {
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            Text(description)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

struct ReviewsSection: View {
    let reviews: [HardcoverService.PublicReview]
    let isLoadingReviews: Bool
    let reviewsError: String?
    let canLoadMoreReviews: Bool
    let onLoadMore: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reviews")
                    .font(.headline)
                Spacer()
                if isLoadingReviews {
                    ProgressView().scaleEffect(0.9)
                }
            }
            
            if let err = reviewsError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if reviews.isEmpty && !isLoadingReviews {
                Text("No reviews found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(reviews) { review in
                        SearchReviewRow(review: review)
                    }
                    
                    if canLoadMoreReviews && !isLoadingReviews {
                        Button("Load More Reviews", action: onLoadMore)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

struct SearchReviewRow: View {
    let review: HardcoverService.PublicReview
    
    @State private var likesCount: Int
    @State private var userHasLiked: Bool
    @State private var isLiking: Bool = false
    
    init(review: HardcoverService.PublicReview) {
        self.review = review
        _likesCount = State(initialValue: review.likesCount)
        _userHasLiked = State(initialValue: review.userHasLiked)
    }
    
    private func formattedDate(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let name = review.username, !name.isEmpty {
                    Text("@\(name)")
                        .font(.caption)
                        .fontWeight(.semibold)
                } else {
                    Text("Review")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                Spacer()
                Text(formattedDate(review.reviewedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if let r = review.rating {
                // Star rating display
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: Double(star) <= r ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                }
            }
            
            if let text = review.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Like button
            HStack(spacing: 8) {
                Spacer()
                Button {
                    Task { await toggleLike() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: userHasLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .imageScale(.small)
                        Text("\(likesCount)")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isLiking)
                .accessibilityLabel(userHasLiked ? Text("Unlike review") : Text("Like review"))
                .accessibilityValue(Text("\(likesCount)"))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
    
    private func toggleLike() async {
        // TODO: hook up to your like/unlike implementation (see other files for reference)
    }
}

// Shared read-only star view (module-wide)
struct ReadOnlyStars: View {
    let rating: Double // 0…5
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let threshold = Double(i) + 1.0
                if rating >= threshold {
                    Image(systemName: "star.fill")
                        .foregroundColor(.orange)
                } else if rating + 0.5 >= threshold {
                    if UIImage(systemName: "star.leadinghalf.filled") != nil {
                        Image(systemName: "star.leadinghalf.filled")
                            .foregroundColor(.orange)
                    } else {
                        ZStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.orange)
                                .mask(
                                    Rectangle()
                                        .frame(width: 6, height: 12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                )
                            Image(systemName: "star")
                                .foregroundColor(.orange)
                        }
                    }
                } else {
                    Image(systemName: "star")
                        .foregroundColor(.orange)
                }
            }
        }
        .font(.caption)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating, specifier: "%.1f") of 5")
    }
}

struct BookReadStatusView: View {
    let finishedDate: Date?
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                Text(NSLocalizedString("Läst", comment: "Book read status (headline, Swedish)"))
                    .font(.headline)
                    .foregroundColor(.green)
                Spacer()
            }
            
            if let finishedDate = finishedDate {
                HStack {
                    Text(NSLocalizedString("Avslutad:", comment: "Read date prefix (Swedish)"))
                        .foregroundColor(.secondary)
                    Text(dateFormatter.string(from: finishedDate))
                        .fontWeight(.medium)
                    Spacer()
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Läst"))
        .accessibilityValue(Text(finishedDate != nil ? dateFormatter.string(from: finishedDate!) : ""))
    }
}
