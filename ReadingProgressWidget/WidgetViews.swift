import SwiftUI
import WidgetKit
import UIKit

// Accent color for progress elements
private let progressTint = Color(red: 181/255, green: 181/255, blue: 246/255)
// Shared corner radius for row cards
private let rowCornerRadius: CGFloat = 10

struct SmallWidgetView: View {
    let book: BookProgress?

    var body: some View {
        if let book = book {
            ZStack {
                // Removed subtle gradient background to avoid box effect
                
                VStack(spacing: 0) {
                    // Book cover only (no background)
                    if let imageData = book.coverImageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .widgetAccentedRenderingMode(.fullColor)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 65, height: 88)
                            .clipped()
                            .cornerRadius(5)
                            .shadow(
                                color: .black.opacity(0.2),
                                radius: 8,
                                x: 2,
                                y: 4
                            )
                            .padding(.top, 10)
                    } else {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.gray.opacity(0.25))
                            .frame(width: 65, height: 88)
                            .overlay(
                                Image(systemName: "book.closed")
                                    .font(.title3)
                                    .foregroundColor(.gray.opacity(0.5))
                            )
                            .shadow(
                                color: .black.opacity(0.2),
                                radius: 8,
                                x: 2,
                                y: 4
                            )
                            .padding(.top, 10)
                    }
                    
                    Spacer(minLength: 4)

                    // Title for active book
                    Text(book.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 12)

                    // Progress and page info
                    HStack(spacing: 10) {
                        // Circular progress
                        if book.progress > 0 {
                            ZStack {
                                CircularProgressView(
                                    progress: book.progress,
                                    color: progressTint
                                )
                                .frame(width: 32, height: 32)
                                
                                Text("\(Int(book.progress * 100))%")
                                    .font(.system(size: 9, weight: .semibold))
                                    .monospacedDigit()
                            }
                        }
                        
                        // Page info
                        if book.currentPage > 0 {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Page \(book.currentPage)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.primary)
                                if book.totalPages > 0 {
                                    Text("of \(book.totalPages)")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
            }
        } else {
            NoBooksView()
        }
    }
}

// Helper: circular ring progress
struct CircularProgressView: View {
    let progress: Double
    var color: Color = .white

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 3.5)
                .opacity(0.25)
                .foregroundColor(color)
            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(style: .init(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .foregroundColor(color)
                .rotationEffect(.degrees(-90))
        }
    }
}

// Helper: empty state
struct NoBooksView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("No Books")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            Text("Add books to read in Hardcover")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Restored styled Medium and Large widgets
struct MediumWidgetView: View {
    let books: [BookProgress]

    var body: some View {
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(books.prefix(2), id: \.id) { book in
                    MediumBookProgressRow(book: book)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .padding(.bottom, 16)
        } else {
            NoBooksView()
        }
    }
}

struct LargeWidgetView: View {
    let books: [BookProgress]
    let lastUpdated: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !books.isEmpty {
                // Slightly larger header with modest spacing when there is free space (fewer than 4 books)
                if books.count < 4 {
                    HStack {
                        Text("Reading Now")
                            .font(.headline.weight(.semibold)) // subtle increase
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4) // modest spacing before the book list
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(books.prefix(4), id: \.id) { book in
                        LargeBookProgressRow(book: book)
                    }
                }
            } else {
                Spacer()
                NoBooksView()
                Spacer()
            }

            HStack {
                Spacer()
                Text("Last updated: \(lastUpdated, style: .time)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
        }
        .padding(.top, 10) // keep near the top but not cramped
        .padding(.bottom, 6)
    }
}

// Styled rows
struct LargeBookProgressRow: View {
    let book: BookProgress

    var body: some View {
        HStack(spacing: 12) {
            // Book Cover
            if let imageData = book.coverImageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 45, height: 60)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 45, height: 60)
                    .cornerRadius(4)
                    .overlay(Image(systemName: "book.closed").font(.caption).foregroundColor(.gray))
            }

            // Details
            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 4) {
                    Text(book.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                Text(book.author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if book.progress > 0 {
                    HStack {
                        if book.isAudiobook {
                            if book.currentMinute > 0 {
                                let currentHours = book.currentMinute / 60
                                let currentMins = book.currentMinute % 60
                                let totalHours = book.totalMinutes / 60
                                let totalMins = book.totalMinutes % 60
                                
                                if book.totalMinutes > 0 {
                                    if totalHours > 0 {
                                        Text("\(currentHours)h \(currentMins)m of \(totalHours)h \(totalMins)m")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("\(currentMins)m of \(totalMins)m")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    let hours = book.currentMinute / 60
                                    let mins = book.currentMinute % 60
                                    if hours > 0 {
                                        Text("\(hours)h \(mins)m")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("\(mins)m")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        } else {
                            if book.currentPage > 0 {
                                if book.totalPages > 0 {
                                    Text("Page \(book.currentPage) of \(book.totalPages)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Page \(book.currentPage)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Text("\(Int(book.progress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: book.progress)
                        .progressViewStyle(.linear)
                        .tint(progressTint)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: rowCornerRadius)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: rowCornerRadius)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius))
    }
}

struct MediumBookProgressRow: View {
    let book: BookProgress

    var body: some View {
        HStack(spacing: 12) {
            // Book Cover
            if let imageData = book.coverImageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 66)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 48, height: 66)
                    .cornerRadius(4)
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.caption)
                            .foregroundColor(.gray)
                    )
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(book.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(book.author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if book.progress > 0 {
                    HStack {
                        if book.isAudiobook {
                            if book.currentMinute > 0 {
                                let currentHours = book.currentMinute / 60
                                let currentMins = book.currentMinute % 60
                                let totalHours = book.totalMinutes / 60
                                let totalMins = book.totalMinutes % 60
                                
                                if book.totalMinutes > 0 {
                                    if totalHours > 0 {
                                        Text("\(currentHours)h \(currentMins)m of \(totalHours)h \(totalMins)m")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("\(currentMins)m of \(totalMins)m")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    let hours = book.currentMinute / 60
                                    let mins = book.currentMinute % 60
                                    if hours > 0 {
                                        Text("\(hours)h \(mins)m")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("\(mins)m")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        } else {
                            if book.currentPage > 0 {
                                if book.totalPages > 0 {
                                    Text("Page \(book.currentPage) of \(book.totalPages)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Page \(book.currentPage)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Text("\(Int(book.progress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: book.progress)
                        .progressViewStyle(.linear)
                        .tint(progressTint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: rowCornerRadius)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: rowCornerRadius)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius))
    }
}
