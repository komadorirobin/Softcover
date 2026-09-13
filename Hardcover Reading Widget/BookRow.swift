import SwiftUI

struct BookRow: View {
    let book: BookProgress
    var subtitle: String? = nil
    var isWorking = false
    var actionIcon: String? = nil
    var actionLabel: LocalizedStringKey = ""
    var onAction: (() -> Void)? = nil
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    BookCover(book: book, width: 56, height: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                        if !book.author.isEmpty {
                            Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        }
                        if book.readingFormat != nil || book.isAudiobook {
                            Label(book.displayFormat, systemImage: book.isAudiobook ? "headphones" : "book.closed")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        } else if book.statusId == 2 || book.currentUnits > 0 {
                            Text(BookProgressPresentation.summary(book)).font(.caption)
                                .foregroundStyle(.secondary).monospacedDigit()
                            if book.totalUnits > 0 {
                                ProgressView(value: min(1, max(0, book.progress)))
                                    .accessibilityHidden(true)
                            }
                        } else if let date = book.parsedReleaseDate ?? ReleaseDate.parse(book.releaseDate) {
                            Text(date, format: .dateTime.year().month(.abbreviated).day())
                                .font(.caption).foregroundStyle(.secondary)
                        } else if let rating = book.editionAverageRating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel(Text("Average \(rating, specifier: "%.1f")"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            if let actionIcon, let onAction {
                Button(action: onAction) {
                    ZStack {
                        Image(systemName: actionIcon).opacity(isWorking ? 0 : 1)
                        if isWorking { ProgressView().controlSize(.small) }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .disabled(isWorking)
                .accessibilityLabel(actionLabel)
                .help(Text(actionLabel))
            }
        }
        .padding(.vertical, 8)
    }
}

struct BookCover: View {
    let book: BookProgress
    var width: CGFloat = 88
    var height: CGFloat = 132
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AsyncCachedImage(
            url: book.coverImageUrl.flatMap(URL.init(string:)), maxPixel: Int(height),
            dataFallback: book.coverImageData, fadeInDuration: reduceMotion ? 0 : 0.15
        ) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Rectangle().fill(Color.secondary.opacity(0.1))
                .overlay { Image(systemName: "book.closed").foregroundStyle(.secondary) }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}

enum BookProgressPresentation {
    static func summary(_ book: BookProgress) -> String {
        if book.isAudiobook {
            let current = duration(book.currentUnits)
            guard book.totalUnits > 0 else { return current }
            return String(format: NSLocalizedString("%@ of %@", comment: "Reading time progress"), current, duration(book.totalUnits))
        }
        if book.totalUnits > 0 {
            return String(format: NSLocalizedString("Page %d of %d", comment: ""), book.currentUnits, book.totalUnits)
        }
        return String(format: NSLocalizedString("Page %d", comment: ""), book.currentUnits)
    }

    static func duration(_ minutes: Int) -> String {
        Duration.seconds(max(0, minutes) * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
