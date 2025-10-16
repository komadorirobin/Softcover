import SwiftUI

struct SearchHeaderView: View {
    @Binding var query: String
    let isSearching: Bool
    let searchType: SearchBooksView.SearchType
    let onSearch: () -> Void
    
    var placeholderText: String {
        switch searchType {
        case .books:
            return "Title or author (tip: author:Herbert)"
        case .users:
            return "Username or name"
        }
    }
    
    var accessibilityLabel: String {
        switch searchType {
        case .books:
            return "Search books"
        case .users:
            return "Search users"
        }
    }
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(placeholderText, text: $query, onCommit: onSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .accessibilityLabel(accessibilityLabel)
            }
            .padding(10)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)

            Button(action: onSearch) {
                HStack {
                    if isSearching { ProgressView().scaleEffect(0.8) }
                    Text(isSearching ? "Searching…" : "Search")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSearching || query.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)
        }
    }
}

struct TrendingSectionView: View {
    let trending: [HardcoverService.TrendingBook]
    let trendingLoading: Bool
    let trendingError: String?
    let trendingAddInProgress: Int?
    @Binding var selectedTrending: HardcoverService.TrendingBook?
    let onAddTrending: (HardcoverService.TrendingBook) -> Void
    let onReloadTrending: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Trending this month")
                    .font(.system(size: 28, weight: .bold))
                Spacer()
                if trendingLoading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button(action: onReloadTrending) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Reload trending")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 0)
            
            if let tErr = trendingError, trending.isEmpty {
                Text(tErr)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    if trendingLoading && trending.isEmpty {
                        ForEach(0..<8, id: \.self) { _ in
                            TrendingSkeletonCell()
                        }
                    } else {
                        ForEach(trending) { item in
                            TrendingBookCell(
                                item: item,
                                isWorking: trendingAddInProgress == item.id,
                                onTap: { onAddTrending(item) },
                                onOpen: { selectedTrending = item }
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 0)
            .offset(y: 8)
        }
        .padding(.top, 24)
    }
}

struct SearchResultsListView: View {
    let results: [HydratedBook]
    let finishedBookIds: Set<Int>
    let readDates: [Int: Date]
    let rowAddInProgress: Int?
    let isLoadingQuickAddEditions: Bool
    let onQuickAdd: (HydratedBook) async -> Void
    let onTapResult: (HydratedBook) async -> Void
    
    var body: some View {
        List {
            ForEach(results, id: \.id) { book in
                SearchResultRowView(
                    book: book,
                    isFinished: finishedBookIds.contains(book.id),
                    finishedDate: readDates[book.id],
                    isAddingInProgress: rowAddInProgress == book.id,
                    isLoadingEditions: isLoadingQuickAddEditions,
                    onQuickAdd: { Task { await onQuickAdd(book) } },
                    onTap: { Task { await onTapResult(book) } }
                )
            }
        }
        .listStyle(.plain)
    }
}

struct SearchResultRowView: View {
    let book: HydratedBook
    let isFinished: Bool
    let finishedDate: Date? // Add parameter for finished date
    let isAddingInProgress: Bool
    let isLoadingEditions: Bool
    let onQuickAdd: () -> Void
    let onTap: () -> Void
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
    
    var body: some View {
        HStack(spacing: 12) {
            BookCoverView(book: book)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline)
                    .lineLimit(2)
                
                let author = book.contributions?.first?.author?.name ?? "Unknown Author"
                Text(author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if isFinished {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                            Text(NSLocalizedString("Read", comment: "already read badge"))
                        }
                        .font(.caption2)
                        .foregroundColor(.green)
                        
                        // Show read date if available, otherwise show placeholder
                        if let finishedDate = finishedDate {
                            Text(dateFormatter.string(from: finishedDate))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Only show Quick add button for books that aren't finished
            if !isFinished {
                Button(action: onQuickAdd) {
                    if isAddingInProgress || isLoadingEditions {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "bookmark")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.accentColor)
                .disabled(isAddingInProgress || isLoadingEditions)
                .accessibilityLabel(Text(NSLocalizedString("Add to Want to Read", comment: "")))
            }
            
            // Detail indicator
            Image(systemName: "chevron.right")
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct BookCoverView: View {
    let book: HydratedBook
    
    var body: some View {
        let url = URL(string: book.image?.url ?? "")
        
        Group {
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .default)) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color(UIColor.tertiarySystemFill)
                            ProgressView().scaleEffect(0.7)
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(_):
                        placeholderCover
                    @unknown default:
                        placeholderCover
                    }
                }
            } else {
                placeholderCover
            }
        }
        .frame(width: 36, height: 52)
        .clipped()
        .cornerRadius(6)
        .shadow(radius: 1)
    }
    
    private var placeholderCover: some View {
        ZStack {
            Color(UIColor.tertiarySystemFill)
            Image(systemName: "book.closed")
                .foregroundColor(.secondary)
        }
    }
}

struct EmptySearchStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Search Hardcover for books")
                .foregroundColor(.secondary)
                .font(.headline)
        }
    }
}

struct TrendingBookCell: View {
    let item: HardcoverService.TrendingBook
    let isWorking: Bool
    let onTap: () -> Void
    let onOpen: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            if let urlString = item.coverImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 112)
                            .clipped()
                            .cornerRadius(8)
                            .shadow(radius: 2)
                    case .empty, .failure:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(width: 80, height: 112)
                            .overlay(Image(systemName: "book.closed").foregroundColor(.secondary))
                    @unknown default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(width: 80, height: 112)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(width: 80, height: 112)
                    .overlay(Image(systemName: "book.closed").foregroundColor(.secondary))
            }
            Text(item.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
                .frame(width: 80, alignment: .leading)
            Text(item.author)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)
            
            Spacer(minLength: 0)
            
            Button(action: onTap) {
                if isWorking {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "plus.circle.fill")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(.accentColor)
        }
        .frame(width: 100, height: 190, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
    }
}

struct TrendingSkeletonCell: View {
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 80, height: 112)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 80, height: 10)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 40, height: 22)
        }
        .redacted(reason: .placeholder)
        .frame(width: 100, height: 190, alignment: .top)
    }
}

// Flow layout (stabil höjd för chips)
struct ChipsFlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                // ny rad
                x = 0
                y += rowSpacing + rowHeight
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + (x > 0 ? spacing : 0)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                // ny rad
                x = bounds.minX
                y += rowSpacing + rowHeight
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// Wrap chips for genres and moods – använder ChipsFlowLayout så innehåll trycks ned korrekt
struct WrapChipsView: View {
    let items: [String]
    var body: some View {
        ChipsFlowLayout(spacing: 6, rowSpacing: 6) {
            ForEach(items, id: \.self) { text in
                Text(text)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
            }
        }
    }
}


