import SwiftUI

struct CommunityListsView: View {
    @StateObject private var store = ExploreLoadState<CommunityList>()
    @State private var selectedFilter: ListFilter = .featured
    var isActive = true

    enum ListFilter: String, CaseIterable {
        case featured = "Featured"
        case popular = "Popular"
        var path: String { self == .featured ? "featured" : "popular" }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(ListFilter.allCases, id: \.self) { filter in
                        Text(LocalizedStringKey(filter.rawValue)).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                ExploreLoadFeedback(isLoading: store.isLoading, error: store.error,
                                    isEmpty: store.items.isEmpty, emptyTitle: "No lists found") {
                    Task { await load(refresh: true) }
                }
                ForEach(store.items) { list in
                    NavigationLink { CommunityListDetailView(list: list) } label: {
                        CommunityListCard(list: list)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .refreshable { await load(refresh: true) }
        .task(id: isActive ? selectedFilter.path : nil) { if isActive { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .hardcoverAccountDidChange)) { _ in
            store.reset()
            if isActive { Task { await load() } }
        }
    }

    @MainActor private func load(refresh: Bool = false) async {
        let filter = selectedFilter.path
        await store.load(key: filter, refresh: refresh) {
            try await HardcoverService.communityLists(filter: filter)
        }
    }
}


struct CommunityListCard: View {
    let list: CommunityList

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("@\(list.creatorUsername)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            if let description = list.description, !description.isEmpty {
                Text(description.decodedHTMLEntities).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 8) {
                ForEach(Array(list.bookCovers.prefix(3).enumerated()), id: \.offset) { _, cover in
                    AsyncCachedImage(url: URL(string: cover)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Rectangle().fill(.quaternary).overlay { Image(systemName: "book.closed") }
                    }
                    .frame(width: 44, height: 66).clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
                }
                Spacer()
                Text("\(list.bookCount) books").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CommunityListDetailView: View {
    let list: CommunityList
    @State private var selectedBook: BookProgress?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(list.name).font(.title2.bold())
                    NavigationLink { UserProfileView(username: list.creatorUsername) } label: {
                        Label("@\(list.creatorUsername)", systemImage: "person.crop.circle").frame(minHeight: 44)
                    }
                    if let description = list.description, !description.isEmpty {
                        Text(description.decodedHTMLEntities).foregroundStyle(.secondary)
                    }
                    Text("\(list.bookCount) books").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal)
                if list.books.isEmpty {
                    ContentUnavailableView("No books found in this list", systemImage: "books.vertical")
                }
                ForEach(list.books) { book in
                    BookRow(book: book.toBookProgress()) { selectedBook = book.toBookProgress() }
                        .padding(.horizontal)
                    Divider().padding(.leading, 88)
                }
            }.padding(.vertical)
        }
        .navigationTitle("List")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(get: { selectedBook != nil }, set: { if !$0 { selectedBook = nil } })) {
            if let selectedBook { BookDetailView(book: selectedBook, isOwnBook: false) }
        }
    }
}
