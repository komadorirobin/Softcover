import SwiftUI
import Foundation

// File-scoped convenience to satisfy any call sites expecting `extractGenres(...)`.
// It reuses the robust cached_tags parsing logic (array/dictionary/mixed shapes).
fileprivate func extractGenres(_ value: Any?) -> [String]? {
    guard let value else { return nil }

    func isGenreContext(_ v: Any?) -> Bool {
        guard let s = (v as? String)?.lowercased() else { return false }
        return s == "genre" || s == "genres"
    }

    func nameFrom(_ dict: [String: Any]) -> String? {
        for key in ["name", "label", "title", "tag"] {
            if let s = dict[key] as? String, !s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                return s
            }
        }
        return nil
    }

    // 1) Already an array of strings
    if let arr = value as? [String] {
        return arr
    }
    // 2) Array of mixed items
    if let arrAny = value as? [Any] {
        var out: [String] = []
        for el in arrAny {
            if let s = el as? String { out.append(s); continue }
            if let d = el as? [String: Any] {
                if isGenreContext(d["context"]) || isGenreContext(d["type"]) || isGenreContext(d["kind"]) || isGenreContext(d["category"]) || isGenreContext(d["group"]) {
                    if let n = nameFrom(d) { out.append(n) }
                    continue
                }
                if let t = d["tag"] as? [String: Any] {
                    if isGenreContext(t["context"]) || isGenreContext(t["type"]) || isGenreContext(t["kind"]) || isGenreContext(t["category"]) || isGenreContext(t["group"]) {
                        if let n = nameFrom(t) { out.append(n) }
                        continue
                    }
                }
            }
        }
        return out.isEmpty ? nil : out
    }
    // 3) Dictionary shapes
    if let dict = value as? [String: Any] {
        // 3a) Uppercase bucket sometimes seen in curated payloads
        if let gAny = dict["Genre"] as? [Any] {
            var out: [String] = []
            for el in gAny {
                if let s = el as? String {
                    out.append(s)
                } else if let d = el as? [String: Any] {
                    if let cat = (d["categorySlug"] as? String)?.lowercased(), cat == "genre",
                       let tag = d["tag"] as? String, !tag.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                        out.append(tag)
                    } else if let tag = d["tag"] as? String, !tag.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                        out.append(tag)
                    }
                }
            }
            if !out.isEmpty { return out }
        }
        // 3b) Lowercase "genres" bucket or similar
        if let g = dict["genres"] {
            if let arr = g as? [String] { return arr }
            if let arrAny = g as? [Any] {
                var out: [String] = []
                for el in arrAny {
                    if let s = el as? String { out.append(s); continue }
                    if let d = el as? [String: Any] {
                        if let n = nameFrom(d) { out.append(n); continue }
                        if let t = d["tag"] as? [String: Any], let n = nameFrom(t) { out.append(n); continue }
                    }
                }
                return out.isEmpty ? nil : out
            }
        }
        // 3c) Generic "tags" bucket with genre context
        if let tags = dict["tags"] as? [Any] {
            var out: [String] = []
            for el in tags {
                if let d = el as? [String: Any] {
                    if isGenreContext(d["context"]) || isGenreContext(d["type"]) || isGenreContext(d["kind"]) || isGenreContext(d["category"]) || isGenreContext(d["group"]) {
                        if let n = nameFrom(d) { out.append(n) }
                        continue
                    }
                    if let t = d["tag"] as? [String: Any] {
                        if isGenreContext(t["context"]) || isGenreContext(t["type"]) || isGenreContext(t["kind"]) || isGenreContext(t["category"]) || isGenreContext(t["group"]) {
                            if let n = nameFrom(t) { out.append(n) }
                            continue
                        }
                    }
                }
            }
            return out.isEmpty ? nil : out
        }
    }
    return nil
}

// Adapter to accept the external label used at some call sites.
fileprivate func extractGenres(fromCachedTags value: Any?) -> [String]? {
    extractGenres(value)
}

// File-scoped robust parser for cached_tags -> [mood names], plus adapter with external label.
fileprivate func extractMoods(_ value: Any?) -> [String]? {
    guard let value else { return nil }

    func isMoodContext(_ v: Any?) -> Bool {
        guard let s = (v as? String)?.lowercased() else { return false }
        return s == "mood" || s == "moods"
    }

    func nameFrom(_ dict: [String: Any]) -> String? {
        for key in ["name", "label", "title", "tag"] {
            if let s = dict[key] as? String, !s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                return s
            }
        }
        return nil
    }

    if let arr = value as? [String] {
        return arr
    }
    if let arrAny = value as? [Any] {
        var out: [String] = []
        for el in arrAny {
            if let s = el as? String { out.append(s); continue }
            if let d = el as? [String: Any] {
                if isMoodContext(d["context"]) || isMoodContext(d["type"]) || isMoodContext(d["kind"]) || isMoodContext(d["category"]) || isMoodContext(d["group"]) {
                    if let n = nameFrom(d) { out.append(n) }
                    continue
                }
                if let t = d["tag"] as? [String: Any] {
                    if isMoodContext(t["context"]) || isMoodContext(t["type"]) || isMoodContext(t["kind"]) || isMoodContext(t["category"]) || isMoodContext(t["group"]) {
                        if let n = nameFrom(t) { out.append(n) }
                        continue
                    }
                }
            }
        }
        return out.isEmpty ? nil : out
    }
    if let dict = value as? [String: Any] {
        if let m = dict["moods"] {
            if let arr = m as? [String] { return arr }
            if let arrAny = m as? [Any] {
                var out: [String] = []
                for el in arrAny {
                    if let s = el as? String { out.append(s); continue }
                    if let d = el as? [String: Any] {
                        if let n = nameFrom(d) { out.append(n); continue }
                        if let t = d["tag"] as? [String: Any], let n = nameFrom(t) { out.append(n); continue }
                    }
                }
                return out.isEmpty ? nil : out
            }
        }
        if let tags = dict["tags"] as? [Any] {
            var out: [String] = []
            for el in tags {
                if let d = el as? [String: Any] {
                    if isMoodContext(d["context"]) || isMoodContext(d["type"]) || isMoodContext(d["kind"]) || isMoodContext(d["category"]) || isMoodContext(d["group"]) {
                        if let n = nameFrom(d) { out.append(n) }
                        continue
                    }
                    if let t = d["tag"] as? [String: Any] {
                        if isMoodContext(t["context"]) || isMoodContext(t["type"]) || isMoodContext(t["kind"]) || isMoodContext(t["category"]) || isMoodContext(t["group"]) {
                            if let n = nameFrom(t) { out.append(n) }
                            continue
                        }
                    }
                }
            }
            return out.isEmpty ? nil : out
        }
    }
    return nil
}

fileprivate func extractMoods(fromCachedTags value: Any?) -> [String]? {
    extractMoods(value)
}

// MARK: - File-scoped query helpers (so nested views can call them)

// Genres via cached_tags (book)
fileprivate func queryBookCachedGenres(url: URL, bookId: Int) async -> [String]? {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    let query = """
    query ($id: Int!) {
      books(where: { id: { _eq: $id }}) {
        id
        cached_tags
      }
    }
    """
    let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
            return nil
        }
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataDict = root["data"] as? [String: Any],
           let books = dataDict["books"] as? [[String: Any]],
           let first = books.first {
            return extractGenres(fromCachedTags: first["cached_tags"])
        }
    } catch {
        return nil
    }
    return nil
}

// Genres via cached_tags (user_book -> book)
fileprivate func queryUserBookCachedGenres(url: URL, userBookId: Int) async -> [String]? {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    let query = """
    query ($id: Int!) {
      user_books(where: { id: { _eq: $id }}) {
        id
        book { id cached_tags }
      }
    }
    """
    let body: [String: Any] = ["query": query, "variables": ["id": userBookId]]
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
            return nil
        }
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataDict = root["data"] as? [String: Any],
           let rows = dataDict["user_books"] as? [[String: Any]],
           let first = rows.first,
           let book = first["book"] as? [String: Any] {
            return extractGenres(fromCachedTags: book["cached_tags"])
        }
    } catch {
        return nil
    }
    return nil
}

// Moods via taggings (book)
fileprivate func queryBookMoodsViaTaggings(url: URL, bookId: Int) async -> [String]? {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    let query = """
    query ($id: Int!) {
      books(where: { id: { _eq: $id }}) {
        id
        taggings(limit: 200) { tag { tag tag_category { slug } } }
      }
    }
    """
    let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
            return nil
        }
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataDict = root["data"] as? [String: Any],
           let books = dataDict["books"] as? [[String: Any]],
           let first = books.first {
            return extractMoodsFromTaggings(first["taggings"])
        }
    } catch {
        return nil
    }
    return nil
}

// Moods via taggings (edition -> book)
fileprivate func queryEditionBookMoodsViaTaggings(url: URL, editionId: Int) async -> [String]? {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    let query = """
    query ($id: Int!) {
      editions(where: { id: { _eq: $id }}) {
        id
        book { id taggings(limit: 200) { tag { tag tag_category { slug } } } }
      }
    }
    """
    let body = ["query": query, "variables": ["id": editionId]] as [String : Any]
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
            return nil
        }
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataDict = root["data"] as? [String: Any],
           let editions = dataDict["editions"] as? [[String: Any]],
           let first = editions.first,
           let book = first["book"] as? [String: Any] {
            return extractMoodsFromTaggings(book["taggings"])
        }
    } catch {
        return nil
    }
    return nil
}

// Moods via taggings (user_book -> book or edition.book)
fileprivate func queryUserBookMoodsViaTaggings(url: URL, userBookId: Int) async -> [String]? {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    let query = """
    query ($id: Int!) {
      user_books(where: { id: { _eq: $id }}) {
        id
        book { id taggings(limit: 200) { tag { tag tag_category { slug } } } }
        edition { id book { id taggings(limit: 200) { tag { tag tag_category { slug } } } } }
      }
    }
    """
    let body = ["query": query, "variables": ["id": userBookId]] as [String : Any]
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
            return nil
        }
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataDict = root["data"] as? [String: Any],
           let rows = dataDict["user_books"] as? [[String: Any]],
           let first = rows.first {
            if let book = first["book"] as? [String: Any],
               let arr = extractMoodsFromTaggings(book["taggings"]),
               !arr.isEmpty { return arr }
            if let ed = first["edition"] as? [String: Any],
               let b = ed["book"] as? [String: Any],
               let arr = extractMoodsFromTaggings(b["taggings"]),
               !arr.isEmpty { return arr }
        }
    } catch {
        return nil
    }
    return nil
}

// cached_tags -> moods (book)
fileprivate func queryBookCachedMoods(url: URL, bookId: Int) async -> [String]? {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    let query = """
    query ($id: Int!) {
      books(where: { id: { _eq: $id }}) {
        id
        cached_tags
      }
    }
    """
    let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
            return nil
        }
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataDict = root["data"] as? [String: Any],
           let books = dataDict["books"] as? [[String: Any]],
           let first = books.first {
            return extractMoods(fromCachedTags: first["cached_tags"])
        }
    } catch {
        return nil
    }
    return nil
}

// cached_tags -> moods (edition -> book)
fileprivate func queryEditionBookCachedMoods(url: URL, editionId: Int) async -> [String]? {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    let query = """
    query ($id: Int!) {
      editions(where: { id: { _eq: $id }}) {
        id
        book { id cached_tags }
      }
    }
    """
    let body: [String: Any] = ["query": query, "variables": ["id": editionId]]
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
            return nil
        }
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataDict = root["data"] as? [String: Any],
           let editions = dataDict["editions"] as? [[String: Any]],
           let first = editions.first,
           let book = first["book"] as? [String: Any] {
            return extractMoods(fromCachedTags: book["cached_tags"])
        }
    } catch {
        return nil
    }
    return nil
}

// cached_tags -> moods (user_book -> book or edition.book)
fileprivate func queryUserBookCachedMoods(url: URL, userBookId: Int) async -> [String]? {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    let query = """
    query ($id: Int!) {
      user_books(where: { id: { _eq: $id }}) {
        id
        book { id cached_tags }
        edition { id book { id cached_tags } }
      }
    }
    """
    let body: [String: Any] = ["query": query, "variables": ["id": userBookId]]
    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
            return nil
        }
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataDict = root["data"] as? [String: Any],
           let rows = dataDict["user_books"] as? [[String: Any]],
           let first = rows.first {
            if let book = first["book"] as? [String: Any],
                let arr = extractMoods(fromCachedTags: book["cached_tags"]),
                !arr.isEmpty { return arr }
            if let ed = first["edition"] as? [String: Any],
                let b = ed["book"] as? [String: Any],
                let arr = extractMoods(fromCachedTags: b["cached_tags"]),
                !arr.isEmpty { return arr }
        }
    } catch {
        return nil
    }
    return nil
}

// Extractors for taggings used by the file-scoped helpers above
fileprivate func extractGenresFromTaggings(_ value: Any?) -> [String]? {
    guard let list = value as? [Any] else { return nil }
    var out: [String] = []
    for el in list {
        guard let row = el as? [String: Any],
              let tag = row["tag"] as? [String: Any],
              let name = tag["tag"] as? String,
              let category = tag["tag_category"] as? [String: Any],
              let slug = category["slug"] as? String else { continue }
        if slug.lowercased() == "genre" && !name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            out.append(name)
        }
    }
    return out.isEmpty ? nil : out
}

fileprivate func extractMoodsFromTaggings(_ value: Any?) -> [String]? {
    guard let list = value as? [Any] else { return nil }
    var out: [String] = []
    for el in list {
        guard let row = el as? [String: Any],
              let tag = row["tag"] as? [String: Any],
              let name = tag["tag"] as? String,
              let category = tag["tag_category"] as? [String: Any],
              let slug = category["slug"] as? String else { continue }
        if slug.lowercased() == "mood" && !name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            out.append(name)
        }
    }
    return out.isEmpty ? nil : out
}

struct SearchBooksView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var isSearching = false
    @State private var results: [HydratedBook] = []
    @State private var errorMessage: String?
    
    // Mark: Read flags for search results
    @State private var finishedBookIds: Set<Int> = []
    
    // Trending state
    @State private var trending: [HardcoverService.TrendingBook] = []
    @State private var trendingLoading = false
    @State private var trendingError: String?
    @State private var trendingAddInProgress: Int?
    // Vald trending-bok för detaljvy
    @State private var selectedTrending: HardcoverService.TrendingBook?
    
    // NYTT: vald sökträff som BookProgress för detaljark
    @State private var selectedSearchDetail: BookProgress?
    
    // NYTT: per-rad add-state för sökresultatens snabbknapp
    @State private var rowAddInProgress: Int?
    
    // NYTT: Quick-add editionsflöde för sökträffens snabbknapp
    @State private var quickAddPendingBook: HydratedBook?
    @State private var quickAddEditions: [Edition] = []
    @State private var quickAddSelectedEditionId: Int?
    @State private var showingQuickAddEditionSheet = false
    @State private var isLoadingQuickAddEditions = false

    // NEW: Preference to skip edition picker on add
    @AppStorage("SkipEditionPickerOnAdd", store: AppGroup.defaults) private var skipEditionPickerOnAdd: Bool = false

    let onDone: (Bool) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Title or author (tip: author:Herbert)", text: $query, onCommit: { Task { await runSearch() } })
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .accessibilityLabel("Search books")
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)

                    Button(action: { Task { await runSearch() } }) {
                        HStack {
                            if isSearching { ProgressView().scaleEffect(0.8) }
                            Text(isSearching ? "Searching…" : "Search")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSearching || query.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                .padding(.top)

                // Trending section – visa bara när det inte finns några sökresultat
                if results.isEmpty {
                    VStack(spacing: 0) { // Ingen extra vertikal spacing mellan rubriken och böckerna
                        HStack {
                            Text("Trending this month")
                                .font(.system(size: 28, weight: .bold)) // Stor rubrik
                            Spacer()
                            IfTrendingLoadingView(trendingLoading: trendingLoading) {
                                Task { await loadTrending(force: true) }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 0) // Ingen bottenmarginal under rubriken
                        
                        // Visa ev. fel endast när listan är tom (då finns inga böcker under rubriken)
                        if let tErr = trendingError, trending.isEmpty {
                            Text(tErr)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 6)
                        }
                        
                        // Böcker direkt under rubriken med top-alignment så omslagen linjerar i toppen
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) { // Viktigt: alignment: .top
                                if trendingLoading && trending.isEmpty {
                                    ForEach(0..<8, id: \.self) { _ in
                                        TrendingSkeletonCell()
                                    }
                                } else {
                                    ForEach(trending) { item in
                                        TrendingBookCell(
                                            item: item,
                                            isWorking: trendingAddInProgress == item.id,
                                            onTap: {
                                                Task { await addTrendingBook(item) }
                                            },
                                            onOpen: {
                                                selectedTrending = item
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top, 0)   // Ingen toppmarginal
                        .offset(y: 8)      // Dra upp innehållet lite för att minska upplevt mellanrum
                    }
                    .padding(.top, 24) // Större avstånd från sökfältet ovanför
                }

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                if results.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical").font(.system(size: 48)).foregroundColor(.secondary)
                        Text("Search Hardcover for books")
                            .foregroundColor(.secondary)
                            .font(.headline)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach($results, id: \.id) { book in
                            HStack(spacing: 12) {
                                cover(for: book)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.wrappedValue.title).font(.subheadline).lineLimit(2)
                                    let author = book.wrappedValue.contributions?.first?.author?.name ?? "Unknown Author"
                                    Text(author).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                    
                                    if finishedBookIds.contains(book.wrappedValue.id) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark")
                                            Text(NSLocalizedString("Read", comment: "already read badge"))
                                        }
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                        .padding(.top, 2)
                                    }
                                }
                                Spacer()
                                
                                // NYTT: Snabbknapp för "Vill läsa" på varje rad – nu med "Välj utgåva"-flöde
                                Button {
                                    Task { await quickAddWantToReadFlow(book.wrappedValue) }
                                } label: {
                                    if rowAddInProgress == book.wrappedValue.id || isLoadingQuickAddEditions {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "bookmark")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(.accentColor)
                                .disabled(rowAddInProgress != nil || isLoadingQuickAddEditions)
                                .accessibilityLabel(Text(NSLocalizedString("Add to Want to Read", comment: "")))
                                
                                // Diskret chevron för att indikera detaljer
                                Image(systemName: "chevron.right")
                                    .foregroundColor(Color(UIColor.tertiaryLabel))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task { await openDetails(for: book.wrappedValue) }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await loadTrending(force: false) }
        // Detaljvy för trending-bok
        .sheet(item: $selectedTrending) { item in
            TrendingBookDetailSheet(
                item: item,
                isWorking: trendingAddInProgress == item.id,
                onAdd: {
                    Task { await addTrendingBook(item) }
                }
            )
        }
        // NYTT: Detaljvy för sökträff – med genrer och moods och NU knappar för att lägga till
        .sheet(item: $selectedSearchDetail) { book in
            SearchResultDetailSheet(
                book: book,
                onAddComplete: { success in
                    if success {
                        onDone(true)
                        dismiss()
                    }
                }
            )
        }
        // NYTT: “Välj utgåva”-sheet för snabbknappen i sökresultatlistan
        .sheet(isPresented: $showingQuickAddEditionSheet) {
            if let pending = quickAddPendingBook {
                EditionSelectionSheet(
                    bookTitle: pending.title,
                    currentEditionId: quickAddSelectedEditionId,
                    editions: quickAddEditions,
                    onCancel: {
                        // Återställ state
                        quickAddPendingBook = nil
                        quickAddEditions = []
                        quickAddSelectedEditionId = nil
                    },
                    onSave: { chosenId in
                        // Kör själva “lägg till” efter att användaren valt utgåva
                        Task {
                            await addSearchResultToWantToRead(pending, editionId: chosenId)
                        }
                    }
                )
            }
        }
    }
    
    // MARK: - Cover helper
    private func cover(for book: HydratedBook) -> some View {
        let url = URL(string: book.image?.url ?? "")
        return Group {
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
                        ZStack {
                            Color(UIColor.tertiarySystemFill)
                            Image(systemName: "book.closed").foregroundColor(.secondary)
                        }
                    @unknown default:
                        ZStack {
                            Color(UIColor.tertiarySystemFill)
                            Image(systemName: "book.closed").foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                ZStack {
                    Color(UIColor.tertiarySystemFill)
                    Image(systemName: "book.closed").foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 36, height: 52)
        .clipped()
        .cornerRadius(6)
        .shadow(radius: 1)
    }
    // Overload to accept a Binding<HydratedBook> defensively (unwraps and forwards to the value-based helper)
    private func cover(for book: Binding<HydratedBook>) -> some View {
        cover(for: book.wrappedValue)
    }

    private func runSearch() async {
        errorMessage = nil
        let raw = query.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let (titlePart, authorPart) = parseQuery(raw)
        
        isSearching = true
        let list = await HardcoverService.searchBooks(
            title: titlePart,
            author: authorPart?.isEmpty == false ? authorPart : nil
        )
        await MainActor.run {
            self.results = list
            self.isSearching = false
            if list.isEmpty {
                self.errorMessage = "No results. Try another search."
            }
        }
        // Efter att resultaten är satta, hämta vilka som redan är lästa (Finished)
        await refreshFinishedFlags()
    }
    
    private func parseQuery(_ q: String) -> (title: String, author: String?) {
        let lower = q.lowercased()
        guard let range = lower.range(of: "author:") else {
            return (q, nil)
        }
        let authorStartIndex = range.upperBound
        let titlePart = q[..<range.lowerBound].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let authorRaw = q[authorStartIndex...].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        if authorRaw.hasPrefix("\"") {
            if let endQuote = authorRaw.dropFirst().firstIndex(of: "\"") {
                let name = authorRaw[authorRaw.index(after: authorRaw.startIndex)..<endQuote]
                return (titlePart, String(name).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
            } else {
                return (titlePart, String(authorRaw.dropFirst()).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
            }
        } else {
            return (titlePart, authorRaw)
        }
    }
    
    // NYTT: Open details for a search result
    private func openDetails(for book: HydratedBook) async {
        // Försök hämta en BookProgress med beskrivning (om möjligt) för en rik detaljvy
        let detail = await HardcoverService.fetchBookDetailsById(bookId: book.id, userBookId: nil, imageMaxPixel: 360, compression: 0.8)
        await MainActor.run {
            if let detail {
                selectedSearchDetail = detail
            } else {
                // Fallback: minimalt objekt om hämtning misslyckas
                let author = book.contributions?.first?.author?.name ?? "Unknown Author"
                let minimal = BookProgress(
                    id: "search-\(book.id)",
                    title: book.title,
                    author: author,
                    coverImageData: nil,
                    progress: 0.0,
                    totalPages: 0,
                    currentPage: 0,
                    bookId: book.id,
                    userBookId: nil,
                    editionId: nil,
                    originalTitle: book.title,
                    editionAverageRating: nil,
                    userRating: nil,
                    bookDescription: nil
                )
                selectedSearchDetail = minimal
            }
        }
    }
    
    private func loadTrending(force: Bool) async {
        guard force || trending.isEmpty else { return }
        await MainActor.run {
            trendingLoading = true
            trendingError = nil
        }
        // Endast månadens trending. Ingen fallback till all-time här.
        let list = await HardcoverService.fetchTrendingBooksMonthly(limit: 20, imageMaxPixel: 280, compression: 0.75)
        await MainActor.run {
            trendingLoading = false
            trending = list
            if list.isEmpty {
                trendingError = NSLocalizedString("Trending is not available right now.", comment: "")
            }
        }
    }
    
    private func addTrendingBook(_ item: HardcoverService.TrendingBook) async {
        await MainActor.run { trendingAddInProgress = item.id }
        // Plus-knappen i Trending lägger alltid till i "Want to Read"
        let ok = await HardcoverService.addBookToWantToRead(bookId: item.id, editionId: nil)
        await MainActor.run {
            trendingAddInProgress = nil
            if ok {
                onDone(true)
                dismiss()
            } else {
#if os(iOS) && !targetEnvironment(macCatalyst)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
            }
        }
    }
    
    // MARK: - NYTT: Snabb-add med editionsflöde
    private func quickAddWantToReadFlow(_ book: HydratedBook) async {
        // If user prefers to skip edition selection, add immediately with default (nil editionId)
        if skipEditionPickerOnAdd {
            await MainActor.run { rowAddInProgress = book.id }
            await addSearchResultToWantToRead(book, editionId: nil)
            await MainActor.run {
                isLoadingQuickAddEditions = false
                rowAddInProgress = nil
            }
            return
        }
        
        await MainActor.run {
            rowAddInProgress = book.id
            isLoadingQuickAddEditions = true
            quickAddPendingBook = nil
            quickAddEditions = []
            quickAddSelectedEditionId = nil
        }
        // Hämta utgåvor
        let editions = await HardcoverService.fetchEditions(for: book.id)
        // Om 0–1 utgåvor -> lägg till direkt
        if editions.count <= 1 {
            let eid = editions.first?.id
            await addSearchResultToWantToRead(book, editionId: eid)
            await MainActor.run {
                isLoadingQuickAddEditions = false
                rowAddInProgress = nil
            }
            return
        }
        // Fler än en utgåva -> öppna väljare
        await MainActor.run {
            isLoadingQuickAddEditions = false
            rowAddInProgress = nil
            quickAddPendingBook = book
            quickAddEditions = editions
            quickAddSelectedEditionId = nil
            showingQuickAddEditionSheet = true
        }
    }
    
    // Ursprungliga snabb-add funktionen – nu återanvänd med explicit editionId
    private func addSearchResultToWantToRead(_ book: HydratedBook, editionId: Int?) async {
        await MainActor.run { rowAddInProgress = book.id }
        let ok = await HardcoverService.addBookToWantToRead(bookId: book.id, editionId: editionId)
        await MainActor.run {
            rowAddInProgress = nil
            if ok {
                onDone(true)
                dismiss()
            } else {
#if os(iOS) && !targetEnvironment(macCatalyst)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
            }
            // Stäng ev. quick-add-sheet state
            showingQuickAddEditionSheet = false
            quickAddPendingBook = nil
            quickAddEditions = []
            quickAddSelectedEditionId = nil
        }
    }
    
    // MARK: - Read flags loading
    private func refreshFinishedFlags() async {
        let ids = results.map { $0.id }
        guard !ids.isEmpty else {
            await MainActor.run { finishedBookIds = [] }
            return
        }
        let set = await queryFinishedBookIds(for: ids)
        await MainActor.run { finishedBookIds = set }
    }
    
    // Hämta aktuellt userId via GraphQL me
    private func fetchCurrentUserId() async -> Int? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let body = [
            "query": "{ me { id username } }"
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let meArr = dataDict["me"] as? [[String: Any]],
               let first = meArr.first,
               let id = first["id"] as? Int {
                return id
            }
        } catch {
            return nil
        }
        return nil
    }
    
    // Batcha user_books för aktuella sökresultat och hämta de som är Finished (status_id == 3) FÖR INLOGGAD ANVÄNDARE.
    // Viktigt: matcha både direkt book_id och edition.book.id så vi inte missar poster där book_id är null.
    private func queryFinishedBookIds(for bookIds: [Int]) async -> Set<Int> {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let userId = await fetchCurrentUserId() else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($userId: Int!, $ids: [Int!]) {
          user_books(
            where: {
              user_id: { _eq: $userId },
              status_id: { _eq: 3 },
              _or: [
                { book_id: { _in: $ids } },
                { edition: { book: { id: { _in: $ids } } } }
              ]
            },
            limit: 500
          ) {
            book_id
            edition { book { id } }
          }
        }
        """
        let body: [String: Any] = [
            "query": query,
            "variables": ["userId": userId, "ids": bookIds]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return []
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]] {
                var out = Set<Int>()
                for row in rows {
                    if let bid = row["book_id"] as? Int {
                        out.insert(bid)
                        continue
                    }
                    if let ed = row["edition"] as? [String: Any],
                       let b = ed["book"] as? [String: Any],
                       let bid = b["id"] as? Int {
                        out.insert(bid)
                    }
                }
                return out
            }
        } catch {
            return []
        }
        return []
    }
    
    // MARK: Taggings-vägen (Genres) — added here to fix scope error
    private func queryBookGenresViaTaggings(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            taggings(limit: 200) { tag { tag tag_category { slug } } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let books = dataDict["books"] as? [[String: Any]],
               let first = books.first {
                return extractGenresFromTaggings(first["taggings"])
            }
        } catch { return nil }
        return nil
    }
    
    private func queryUserBookGenresViaTaggings(url: URL, userBookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        // OBS: Hämtar endast via user_books.book.taggings (inte edition.book)
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id }}) {
            id
            book { id taggings(limit: 200) { tag { tag tag_category { slug } } } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": userBookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]],
               let first = rows.first,
               let book = first["book"] as? [String: Any] {
                return extractGenresFromTaggings(book["taggings"])
            }
        } catch { return nil }
        return nil
    }
    
    private func extractGenresFromTaggings(_ value: Any?) -> [String]? {
        guard let list = value as? [Any] else { return nil }
        var out: [String] = []
        for el in list {
            guard let row = el as? [String: Any],
                  let tag = row["tag"] as? [String: Any],
                  let name = tag["tag"] as? String,
                  let category = tag["tag_category"] as? [String: Any],
                  let slug = category["slug"] as? String else { continue }
            if slug.lowercased() == "genre" && !name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                out.append(name)
            }
        }
        return out.isEmpty ? nil : out
    }
    
    // MARK: Taggings-vägen (Moods)
    private func queryBookMoodsViaTaggings(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            taggings(limit: 200) { tag { tag tag_category { slug } } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                print("❌ books.taggings error: \(errs)")
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let books = dataDict["books"] as? [[String: Any]],
               let first = books.first {
                return extractMoodsFromTaggings(first["taggings"])
            }
        } catch {
            print("❌ books.taggings exception: \(error)")
            return nil
        }
        return nil
    }
    
    private func queryEditionBookMoodsViaTaggings(url: URL, editionId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          editions(where: { id: { _eq: $id }}) {
            id
            book { id taggings(limit: 200) { tag { tag tag_category { slug } } } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": editionId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                print("❌ edition.book.taggings error: \(errs)")
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let editions = dataDict["editions"] as? [[String: Any]],
               let first = editions.first,
               let book = first["book"] as? [String: Any] {
                return extractMoodsFromTaggings(book["taggings"])
            }
        } catch {
            print("❌ edition.book.taggings exception: \(error)")
            return nil
        }
        return nil
    }
    
    private func queryUserBookMoodsViaTaggings(url: URL, userBookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id }}) {
            id
            book { id taggings(limit: 200) { tag { tag tag_category { slug } } } }
            edition { id book { id taggings(limit: 200) { tag { tag tag_category { slug } } } } }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": userBookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                print("❌ user_books moods error: \(errs)")
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]],
               let first = rows.first {
                if let book = first["book"] as? [String: Any],
                   let arr = extractMoodsFromTaggings(book["taggings"]),
                   !arr.isEmpty { return arr }
                if let ed = first["edition"] as? [String: Any],
                   let b = ed["book"] as? [String: Any],
                   let arr = extractMoodsFromTaggings(b["taggings"]),
                   !arr.isEmpty { return arr }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private func extractMoodsFromTaggings(_ value: Any?) -> [String]? {
        guard let list = value as? [Any] else { return nil }
        var out: [String] = []
        for el in list {
            guard let row = el as? [String: Any],
                  let tag = row["tag"] as? [String: Any],
                  let name = tag["tag"] as? String,
                  let category = row["tag"] as? [String: Any] ?? (row["tag"] as? [String: Any])?["tag_category"] as? [String: Any],
                  let slug = (row["tag"] as? [String: Any])?["tag_category"] as? [String: Any]? != nil ? (((row["tag"] as? [String: Any])?["tag_category"] as? [String: Any])?["slug"] as? String) : nil else { continue }
            // Note: above defensive unwrap is not used; see global version below for correctness.
            // Keep local helper for symmetry but unused.
            if slug?.lowercased() == "mood", !name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                out.append(name)
            }
        }
        return out.isEmpty ? nil : out
    }
    
    // MARK: cached_tags-vägen (Genres)
    private func queryBookCachedGenres(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            cached_tags
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                print("❌ books.cached_tags error: \(errs)")
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let books = dataDict["books"] as? [[String: Any]],
               let first = books.first {
                return extractGenres(fromCachedTags: first["cached_tags"])
            }
        } catch {
            print("❌ books.cached_tags exception: \(error)")
            return nil
        }
        return nil
    }
    
    private func queryEditionBookCachedGenres(url: URL, editionId: Int) async -> [String]? {
        // OBS: Lämnas kvar men ANVÄNDS INTE för genrer längre.
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          editions(where: { id: { _eq: $id }}) {
            id
            book { id cached_tags }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": editionId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                print("❌ edition.book.cached_tags error: \(errs)")
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let editions = dataDict["editions"] as? [[String: Any]],
               let first = editions.first,
               let book = first["book"] as? [String: Any] {
                return extractGenres(fromCachedTags: book["cached_tags"])
            }
        } catch {
            print("❌ edition.book.cached_tags exception: \(error)")
            return nil
        }
        return nil
    }
    
    private func queryUserBookCachedGenres(url: URL, userBookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id }}) {
            id
            book { id cached_tags }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": userBookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                print("❌ user_books.cached_tags error: \(errs)")
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]],
               let first = rows.first,
               let book = first["book"] as? [String: Any] {
                return extractGenres(fromCachedTags: book["cached_tags"])
            }
        } catch {
            print("❌ user_books.cached_tags exception: \(error)")
            return nil
        }
        return nil
    }
    
    // MARK: cached_tags-vägen (Moods) — ADDED to fix missing member errors
    private func queryBookCachedMoods(url: URL, bookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          books(where: { id: { _eq: $id }}) {
            id
            cached_tags
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": bookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let books = dataDict["books"] as? [[String: Any]],
               let first = books.first {
                return extractMoods(fromCachedTags: first["cached_tags"])
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private func queryEditionBookCachedMoods(url: URL, editionId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          editions(where: { id: { _eq: $id }}) {
            id
            book { id cached_tags }
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": editionId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let editions = dataDict["editions"] as? [[String: Any]],
               let first = editions.first,
               let book = first["book"] as? [String: Any] {
                return extractMoods(fromCachedTags: book["cached_tags"])
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private func queryUserBookCachedMoods(url: URL, userBookId: Int) async -> [String]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($id: Int!) {
          user_books(where: { id: { _eq: $id }}) {
            id
            book { id cached_tags }
            edition { id book { id cached_tags } }
          }
        """
        let body: [String: Any] = ["query": query, "variables": ["id": userBookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty {
                return nil
            }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]],
               let first = rows.first {
                if let book = first["book"] as? [String: Any],
                    let arr = extractMoods(fromCachedTags: book["cached_tags"]),
                    !arr.isEmpty { return arr }
                if let ed = first["edition"] as? [String: Any],
                    let b = ed["book"] as? [String: Any],
                    let arr = extractMoods(fromCachedTags: b["cached_tags"]),
                    !arr.isEmpty { return arr }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    // Robust parser för cached_tags -> [genre-namn]
    private func extractGenres(fromCachedTags value: Any?) -> [String]? {
        guard let value else { return nil }
        
        func isGenreContext(_ v: Any?) -> Bool {
            guard let s = (v as? String)?.lowercased() else { return false }
            return s == "genre" || s == "genres"
        }
        
        func nameFrom(_ dict: [String: Any]) -> String? {
            for key in ["name", "label", "title", "tag"] {
                if let s = dict[key] as? String, !s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                    return s
                }
            }
            return nil
        }
        
        // 1) Already an array of strings
        if let arr = value as? [String] {
            return arr
        }
        // 2) Array of mixed items
        if let arrAny = value as? [Any] {
            var out: [String] = []
            for el in arrAny {
                if let s = el as? String { out.append(s); continue }
                if let d = el as? [String: Any] {
                    if isGenreContext(d["context"]) || isGenreContext(d["type"]) || isGenreContext(d["kind"]) || isGenreContext(d["category"]) || isGenreContext(d["group"]) {
                        if let n = nameFrom(d) { out.append(n) }
                        continue
                    }
                    if let t = d["tag"] as? [String: Any] {
                        if isGenreContext(t["context"]) || isGenreContext(t["type"]) || isGenreContext(t["kind"]) || isGenreContext(t["category"]) || isGenreContext(t["group"]) {
                            if let n = nameFrom(t) { out.append(n) }
                            continue
                        }
                    }
                }
            }
            return out.isEmpty ? nil : out
        }
        // 3) Dictionary shapes
        if let dict = value as? [String: Any] {
            // 3a) Your posted curated shape: top-level "Genre": [ { tag: "...", categorySlug: "genre", ... } ]
            if let gAny = dict["Genre"] as? [Any] {
                var out: [String] = []
                for el in gAny {
                    if let s = el as? String {
                        out.append(s)
                    } else if let d = el as? [String: Any] {
                        if let cat = (d["categorySlug"] as? String)?.lowercased(), cat == "genre",
                           let tag = d["tag"] as? String, !tag.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                            out.append(tag)
                        } else if let tag = d["tag"] as? String, !tag.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                            // Fallback: accept tag if present
                            out.append(tag)
                        }
                    }
                }
                if !out.isEmpty { return out }
            }
            // 3b) Lowercase "genres" bucket or similar
            if let g = dict["genres"] {
                if let arr = g as? [String] { return arr }
                if let arrAny = g as? [Any] {
                    var out: [String] = []
                    for el in arrAny {
                        if let s = el as? String { out.append(s); continue }
                        if let d = el as? [String: Any] {
                            if let n = nameFrom(d) { out.append(n); continue }
                            if let t = d["tag"] as? [String: Any], let n = nameFrom(t) { out.append(n); continue }
                        }
                    }
                    return out.isEmpty ? nil : out
                }
            }
            // 3c) Generic "tags" bucket with genre context
            if let tags = dict["tags"] as? [Any] {
                var out: [String] = []
                for el in tags {
                    if let d = el as? [String: Any] {
                        if isGenreContext(d["context"]) || isGenreContext(d["type"]) || isGenreContext(d["kind"]) || isGenreContext(d["category"]) || isGenreContext(d["group"]) {
                            if let n = nameFrom(d) { out.append(n) }
                            continue
                        }
                        if let t = d["tag"] as? [String: Any] {
                            if isGenreContext(t["context"]) || isGenreContext(t["type"]) || isGenreContext(t["kind"]) || isGenreContext(t["category"]) || isGenreContext(t["group"]) {
                                if let n = nameFrom(t) { out.append(n) }
                                continue
                            }
                        }
                    }
                }
                return out.isEmpty ? nil : out
            }
        }
        return nil
    }
    
    // Robust parser för cached_tags -> [mood-namn]
    private func extractMoods(fromCachedTags value: Any?) -> [String]? {
        guard let value else { return nil }
        
        func isMoodContext(_ v: Any?) -> Bool {
            guard let s = (v as? String)?.lowercased() else { return false }
            return s == "mood" || s == "moods"
        }
        
        func nameFrom(_ dict: [String: Any]) -> String? {
            for key in ["name", "label", "title", "tag"] {
                if let s = dict[key] as? String, !s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                    return s
                }
            }
            return nil
        }
        
        if let arr = value as? [String] {
            return arr
        }
        if let arrAny = value as? [Any] {
            var out: [String] = []
            for el in arrAny {
                if let s = el as? String { out.append(s); continue }
                if let d = el as? [String: Any] {
                    if isMoodContext(d["context"]) || isMoodContext(d["type"]) || isMoodContext(d["kind"]) || isMoodContext(d["category"]) || isMoodContext(d["group"]) {
                        if let n = nameFrom(d) { out.append(n) }
                        continue
                    }
                    if let t = d["tag"] as? [String: Any] {
                        if isMoodContext(t["context"]) || isMoodContext(t["type"]) || isMoodContext(t["kind"]) || isMoodContext(t["category"]) || isMoodContext(t["group"]) {
                            if let n = nameFrom(t) { out.append(n) }
                            continue
                        }
                    }
                }
            }
            return out.isEmpty ? nil : out
        }
        if let dict = value as? [String: Any] {
            if let m = dict["moods"] {
                if let arr = m as? [String] { return arr }
                if let arrAny = m as? [Any] {
                    var out: [String] = []
                    for el in arrAny {
                        if let s = el as? String { out.append(s); continue }
                        if let d = el as? [String: Any] {
                            if let n = nameFrom(d) { out.append(n); continue }
                            if let t = d["tag"] as? [String: Any], let n = nameFrom(t) { out.append(n); continue }
                        }
                    }
                    return out.isEmpty ? nil : out
                }
            }
            if let tags = dict["tags"] as? [Any] {
                var out: [String] = []
                for el in tags {
                    if let d = el as? [String: Any] {
                        if isMoodContext(d["context"]) || isMoodContext(d["type"]) || isMoodContext(d["kind"]) || isMoodContext(d["category"]) || isMoodContext(d["group"]) {
                            if let n = nameFrom(d) { out.append(n) }
                            continue
                        }
                        if let t = d["tag"] as? [String: Any] {
                            if isMoodContext(t["context"]) || isMoodContext(t["type"]) || isMoodContext(t["kind"]) || isMoodContext(t["category"]) || isMoodContext(t["group"]) {
                                if let n = nameFrom(t) { out.append(n) }
                                continue
                            }
                        }
                    }
                }
                return out.isEmpty ? nil : out
            }
        }
        return nil
    }
}

// Small helper view for the refresh icon/loader in Trending header
private struct IfTrendingLoadingView: View {
    let trendingLoading: Bool
    let onReload: () -> Void
    var body: some View {
        if trendingLoading {
            ProgressView().scaleEffect(0.8)
        } else {
            Button(action: onReload) {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Reload trending")
        }
    }
}

// MARK: - UI Components (Trending)
private struct TrendingBookCell: View {
    let item: HardcoverService.TrendingBook
    let isWorking: Bool
    let onTap: () -> Void
    let onOpen: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            if let data = item.coverImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 112)
                    .clipped()
                    .cornerRadius(8)
                    .shadow(radius: 2)
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
            
            Spacer(minLength: 0) // Tryck ner plus-knappen till botten
            
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
        .frame(width: 100, height: 190, alignment: .top) // Fast höjd så alla celler får samma botten
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
    }
}

private struct TrendingSkeletonCell: View {
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

// Inline review row used in TrendingBookDetailSheet
private struct TrendingInlineReviewRow: View {
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
                TrendingReadOnlyStars(rating: r)
            }
            if let text = review.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Like row
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
        guard !isLiking else { return }
        let wasLiked = userHasLiked
        let newLikeState = !wasLiked
        
        await MainActor.run {
            isLiking = true
            // Optimistic update
            userHasLiked = newLikeState
            if newLikeState {
                likesCount += 1
            } else {
                likesCount = max(0, likesCount - 1)
            }
        }
        
        // Local helper to avoid cross-target dependency on HardcoverService extension
        let result = await setLike(likeableId: review.id, like: newLikeState, likeableType: "UserBook")
        
        await MainActor.run {
            if let result {
                // Update with confirmed state from server
                likesCount = max(0, result.likesCount)
                userHasLiked = result.didLike
#if os(iOS) && !targetEnvironment(macCatalyst)
                if userHasLiked {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
#endif
            } else {
                // Rollback on failure
                userHasLiked = wasLiked
                if wasLiked {
                    likesCount += 1
                } else {
                    likesCount = max(0, likesCount - 1)
                }
            }
            isLiking = false
        }
    }
    
    // MARK: - Local like helpers (mirrors HardcoverService+LikesToggle)
    private func setLike(likeableId: Int, like: Bool, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        if like {
            return await upsertLike(likeableId: likeableId, likeableType: likeableType)
        } else {
            return await deleteLike(likeableId: likeableId, likeableType: likeableType)
        }
    }
    
    private func upsertLike(likeableId: Int, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let mutation = """
        mutation UpsertLike($likeableId: Int!, $likeableType: String!) {
          likeResult: upsert_like(likeable_id: $likeableId, likeable_type: $likeableType) {
            likesCount: likes_count
            __typename
          }
        }
        """
        let vars: [String: Any] = ["likeableId": likeableId, "likeableType": likeableType]
        let body: [String: Any] = ["query": mutation, "variables": vars]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["errors"] as? [[String: Any]])?.isEmpty != false,
                  let dataDict = root["data"] as? [String: Any],
                  let likeResult = dataDict["likeResult"] as? [String: Any],
                  let likesCount = likeResult["likesCount"] as? Int else { return nil }
            return (max(0, likesCount), true)
        } catch { return nil }
    }
    
    private func deleteLike(likeableId: Int, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let mutation = """
        mutation DeleteLike($likeableId: Int!, $likeableType: String!) {
          likeResult: delete_like(likeable_id: $likeableId, likeable_type: $likeableType) {
            likesCount: likes_count
            __typename
          }
        }
        """
        let vars: [String: Any] = ["likeableId": likeableId, "likeableType": likeableType]
        let body: [String: Any] = ["query": mutation, "variables": vars]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["errors"] as? [[String: Any]])?.isEmpty != false,
                  let dataDict = root["data"] as? [String: Any],
                  let likeResult = dataDict["likeResult"] as? [String: Any],
                  let likesCount = likeResult["likesCount"] as? Int else { return nil }
            return (max(0, likesCount), false)
        } catch { return nil }
    }
    
    // Small, read-only stars just for this inline row
    private struct TrendingReadOnlyStars: View {
        let rating: Double // 0…5
        var body: some View {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let threshold = Double(i) + 1.0
                    if rating >= threshold {
                        Image(systemName: "star.fill")
                            .foregroundColor(.orange)
                    } else if rating + 0.5 >= threshold {
                        Image(systemName: "star.leadinghalf.filled")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "star")
                            .foregroundColor(.orange.opacity(0.35))
                    }
                }
            }
            .font(.caption)
            .accessibilityLabel("Rating")
            .accessibilityValue("\(rating, specifier: "%.1f") of 5")
        }
    }
}

// MARK: - Flow layout (stabil höjd för chips)
private struct ChipsFlowLayout: Layout {
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
private struct WrapChipsView: View {
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

// MARK: - Rik detaljvy för Trendande (med Genres, Moods och Reviews)
private struct TrendingBookDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: HardcoverService.TrendingBook
    let isWorking: Bool
    let onAdd: () -> Void
    
    // Genres & Moods state
    @State private var genres: [String] = []
    @State private var moods: [String] = []
    @State private var isLoadingGenres = false
    @State private var isLoadingMoods = false
    
    // Reviews state
    @State private var isLoadingReviews = false
    @State private var reviewsError: String?
    @State private var reviews: [HardcoverService.PublicReview] = []
    @State private var reviewsPage = 0
    private let reviewsPageSize = 10
    @State private var canLoadMoreReviews = true
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        if let data = item.coverImageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 140)
                                .clipped()
                                .cornerRadius(8)
                                .shadow(radius: 3)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(UIColor.tertiarySystemFill))
                                .frame(width: 100, height: 140)
                                .overlay(Image(systemName: "book.closed").foregroundColor(.secondary))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title)
                                .font(.headline)
                                .lineLimit(3)
                            Text(item.author)
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
                    
                    // Quick action
                    Button(action: onAdd) {
                        if isWorking {
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
                    .disabled(isWorking)
                    
                    // Reviews
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
                                ForEach(reviews) { r in
                                    TrendingInlineReviewRow(review: r)
                                }
                                if canLoadMoreReviews {
                                    HStack {
                                        Spacer()
                                        Button {
                                            Task { await loadMoreReviews(for: item.id) }
                                        } label: {
                                            if isLoadingReviews {
                                                ProgressView().scaleEffect(0.9)
                                            } else {
                                                Text("Load more")
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        Spacer()
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            // Ladda genrer/moods + första sidan recensioner
            await reloadTaxonomies()
            await reloadReviews(for: item.id)
        }
    }
    
    // MARK: Reviews loading
    private func reloadReviews(for bookId: Int) async {
        await MainActor.run {
            isLoadingReviews = true
            reviewsError = nil
            reviewsPage = 0
            canLoadMoreReviews = true
            reviews = []
        }
        let list = await HardcoverService.fetchPublicReviewsForBook(bookId: bookId, limit: reviewsPageSize, offset: 0)
        await MainActor.run {
            isLoadingReviews = false
            reviews = list
            canLoadMoreReviews = list.count == reviewsPageSize
            reviewsPage = 1
        }
    }
    
    private func loadMoreReviews(for bookId: Int) async {
        guard !isLoadingReviews, canLoadMoreReviews else { return }
        await MainActor.run { isLoadingReviews = true }
        let offset = reviewsPage * reviewsPageSize
        let list = await HardcoverService.fetchPublicReviewsForBook(bookId: bookId, limit: reviewsPageSize, offset: offset)
        await MainActor.run {
            isLoadingReviews = false
            if list.isEmpty {
                canLoadMoreReviews = false
            } else {
                reviews.append(contentsOf: list)
                reviewsPage += 1
                if list.count < reviewsPageSize { canLoadMoreReviews = false }
            }
        }
    }
    
    // MARK: Genres & Moods loading (samma logik som i sök-detaljvyn)
    private func reloadTaxonomies() async {
        await MainActor.run {
            if genres.isEmpty { isLoadingGenres = true }
            if moods.isEmpty { isLoadingMoods = true }
        }
        async let g = fetchGenresPreferred(bookId: item.id, editionId: nil, userBookId: nil)
        async let m = fetchMoodsPreferred(bookId: item.id, editionId: nil, userBookId: nil)
        let (gList, mList) = await (g, m)
        await MainActor.run {
            self.genres = gList
            self.moods = mList
            self.isLoadingGenres = false
            self.isLoadingMoods = false
        }
    }
    
    private func fetchGenresPreferred(bookId: Int?, editionId: Int?, userBookId: Int?) async -> [String] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        func normalize(_ arr: [String]) -> [String] {
            let cleaned = arr
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            // Bevara ordningen; deduplicera case-insensitivt
            var seen = Set<String>()
            var out: [String] = []
            for s in cleaned {
                let key = s.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    out.append(s)
                }
            }
            return out
        }
        
        // 1) via cached_tags (book) – curated only
        if let bid = bookId {
            if let arr = await queryBookCachedGenres(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        // 2) via cached_tags (user_book -> book) – curated only
        if let ubid = userBookId {
            if let arr = await queryUserBookCachedGenres(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        // Only curated; do not fall back to taggings
        return []
    }
    
    private func fetchMoodsPreferred(bookId: Int?, editionId: Int?, userBookId: Int?) async -> [String] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        func normalize(_ arr: [String]) -> [String] {
            let cleaned = arr
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var seen = Set<String>()
            var out: [String] = []
            for s in cleaned {
                let key = s.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    out.append(s)
                }
            }
            return out
        }
        
        // Taggings path (OK för moods)
        if let bid = bookId {
            if let arr = await queryBookMoodsViaTaggings(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let eid = editionId {
            if let arr = await queryEditionBookMoodsViaTaggings(url: url, editionId: eid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await queryUserBookMoodsViaTaggings(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        // cached_tags path (OK för moods)
        if let bid = bookId {
            if let arr = await queryBookCachedMoods(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let eid = editionId {
            if let arr = await queryEditionBookCachedMoods(url: url, editionId: eid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await queryUserBookCachedMoods(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        return []
    }
}

// MARK: - NYTT: Detaljvy för sökträff (med genrer/moods och lägg-till-knapp)
private struct SearchResultDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let book: BookProgress
    let onAddComplete: (Bool) -> Void
    
    // UI state
    @State private var isWorking = false
    // NYTT: separat state för “Läs nu”
    @State private var isWorkingReading = false
    // NYTT: separat state för "Markera som läst"
    @State private var isWorkingFinished = false
    
    // NYTT: editionsval
    private enum PendingAction { case wantToRead, readNow, markAsRead }
    @State private var pendingAction: PendingAction?
    @State private var editions: [Edition] = []
    @State private var isLoadingEditions = false
    @State private var selectedEditionId: Int?
    @State private var showingEditionSheet = false
    
    // Taxonomies
    @State private var genres: [String] = []
    @State private var moods: [String] = []
    @State private var isLoadingGenres = false
    @State private var isLoadingMoods = false
    
    // Reviews state
    @State private var isLoadingReviews = false
    @State private var reviewsError: String?
    @State private var reviews: [HardcoverService.PublicReview] = []
    @State private var reviewsPage = 0
    private let reviewsPageSize = 10
    @State private var canLoadMoreReviews = true

    // NEW: Preference to skip edition picker on add
    @AppStorage("SkipEditionPickerOnAdd", store: AppGroup.defaults) private var skipEditionPickerOnAdd: Bool = false
    
    // NEW: My rating/review state
    @State private var myRating: Double? = nil
    @State private var reviewText: String = ""
    @State private var hasSpoilers: Bool = false
    @State private var isSubmittingReview: Bool = false
    @State private var submitMessage: String? = nil
    @State private var submitError: String? = nil
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        if let data = book.coverImageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 140)
                                .clipped()
                                .cornerRadius(8)
                                .shadow(radius: 3)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(UIColor.tertiarySystemFill))
                                .frame(width: 100, height: 140)
                                .overlay(Image(systemName: "book.closed").foregroundColor(.secondary))
                        }
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
                    
                    // Quick actions: Add to Want to Read + Läs nu + Markera som läst
                    VStack(spacing: 10) {
                        Button {
                            Task { await ensureEditionThenPerform(.wantToRead) }
                        } label: {
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
                            Button {
                                Task { await ensureEditionThenPerform(.readNow) }
                            } label: {
                                if isWorkingReading || isLoadingEditions {
                                    HStack {
                                        Spacer()
                                        ProgressView().scaleEffect(0.9)
                                        Spacer()
                                    }
                                } else {
                                    // Icke-brytande mellanrum för snyggare text
                                    Label(NSLocalizedString("Läs\u{00A0}nu", comment: "Start reading now"), systemImage: "book.fill")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.accentColor)
                            .disabled(isWorkingReading || isLoadingEditions || book.bookId == nil)
                            
                            Button {
                                Task { await ensureEditionThenPerform(.markAsRead) }
                            } label: {
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
                    
                    // Description (om tillgänglig)
                    if let desc = normalizedDescription(book.bookDescription) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            Text(desc)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    
                    // MARK: Your rating & review (NEW)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your rating & review")
                            .font(.headline)
                        
                        // Star picker (0…5 in 0.5 steps)
                        StarRatingPicker(rating: $myRating)
                        
                        // Review text
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Write a review (optional)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $reviewText)
                                    .frame(minHeight: 100)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(UIColor.separator), lineWidth: 1)
                                    )
                                if reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Share your thoughts…")
                                        .foregroundColor(.secondary)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                }
                            }
                            Toggle("Contains spoilers", isOn: $hasSpoilers)
                                .toggleStyle(SwitchToggleStyle(tint: .red))
                                .accessibilityLabel("Contains spoilers")
                        }
                        
                        // Submit row
                        if let msg = submitMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        if let err = submitError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        Button {
                            Task { await submitRatingAndOrReview() }
                        } label: {
                            if isSubmittingReview {
                                HStack { Spacer(); ProgressView().scaleEffect(0.9); Spacer() }
                            } else {
                                Label("Submit", systemImage: "paperplane.fill")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSubmittingReview || (myRating == nil && reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || book.bookId == nil)
                    }
                    .padding(.top, 4)
                    
                    // Reviews
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
                                ForEach(reviews) { r in
                                    SearchReviewRow(review: r)
                                }
                                if canLoadMoreReviews, let id = book.bookId {
                                    HStack {
                                        Spacer()
                                        Button {
                                            Task { await loadMoreReviews(for: id) }
                                        } label: {
                                            if isLoadingReviews {
                                                ProgressView().scaleEffect(0.9)
                                            } else {
                                                Text("Load more")
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        Spacer()
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            await reloadTaxonomies()
            if let id = book.bookId {
                await reloadReviews(for: id)
            }
        }
        // NYTT: editionsval-sheet
        .sheet(isPresented: $showingEditionSheet) {
            EditionSelectionSheet(
                bookTitle: book.title,
                currentEditionId: selectedEditionId ?? book.editionId,
                editions: editions,
                onCancel: {
                    // Avbryt: nollställ pendingAction men gör inget mer
                    pendingAction = nil
                },
                onSave: { chosenId in
                    selectedEditionId = chosenId
                    let action = pendingAction
                    pendingAction = nil
                    Task { await performAction(using: chosenId, action: action) }
                }
            )
        }
    }
    
    private func normalizedDescription(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !s.isEmpty else { return nil }
        let withoutTags = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return withoutTags.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
    
    // MARK: - Editions flow
    private func fetchEditionsIfNeeded() async -> [Edition] {
        guard editions.isEmpty, let bookId = book.bookId else { return editions }
        await MainActor.run { isLoadingEditions = true }
        let list = await HardcoverService.fetchEditions(for: bookId)
        await MainActor.run {
            editions = list
            isLoadingEditions = false
        }
        return list
    }
    
    private func ensureEditionThenPerform(_ action: PendingAction) async {
        guard let _ = book.bookId else { return }
        
        // Snabbspår: hoppa över väljare om användaren valt det (gäller ej när flera utgåvor finns)
        if skipEditionPickerOnAdd && action != .markAsRead {
            await performAction(using: selectedEditionId ?? book.editionId, action: action)
            return
        }
        
        // Om vi redan har en vald edition, använd den direkt (för markAsRead också – ingen anledning att tvinga väljare om vi redan vet)
        if let eid = selectedEditionId ?? book.editionId {
            await performAction(using: eid, action: action)
            return
        }
        
        // Hämta lista
        let list = await fetchEditionsIfNeeded()
        
        // 0 utgåvor: fortsätt utan edition
        if list.isEmpty {
            await performAction(using: nil, action: action)
            return
        }
        // 1 utgåva: auto-välj
        if list.count == 1, let only = list.first {
            await performAction(using: only.id, action: action)
            return
        }
        // Flera utgåvor: visa väljare
        await MainActor.run {
            pendingAction = action
            showingEditionSheet = true
        }
    }
    
    private func performAction(using editionId: Int?, action: PendingAction?) async {
        guard let action else { return }
        switch action {
        case .wantToRead:
            await addToWantToRead(editionId: editionId)
        case .readNow:
            await startReadingNow(editionId: editionId)
        case .markAsRead:
            await markAsRead(editionId: editionId)
        }
    }
    
    private func addToWantToRead(editionId: Int?) async {
        guard let id = book.bookId else { return }
        await MainActor.run { isWorking = true }
        let ok = await HardcoverService.addBookToWantToRead(bookId: id, editionId: editionId)
        await MainActor.run {
            isWorking = false
            onAddComplete(ok)
            if ok { dismiss() }
        }
    }
    
    // “Läs nu” – lägg direkt till i Currently Reading
    private func startReadingNow(editionId: Int?) async {
        guard let id = book.bookId else { return }
        await MainActor.run { isWorkingReading = true }
        let ok = await HardcoverService.addBookToCurrentlyReading(bookId: id, editionId: editionId)
        await MainActor.run {
            isWorkingReading = false
            onAddComplete(ok)
            if ok { dismiss() }
        }
    }
    
    // "Markera som läst" – lägg direkt till som Finished
    private func markAsRead(editionId: Int?) async {
        guard let id = book.bookId else { return }
        await MainActor.run { isWorkingFinished = true }
        let ok = await HardcoverService.finishBookByBookId(bookId: id, editionId: editionId, pages: nil, rating: nil)
        await MainActor.run {
            isWorkingFinished = false
            onAddComplete(ok)
            if ok { dismiss() }
        }
    }
    
    // MARK: Reviews loading (added for SearchResultDetailSheet)
    private func reloadReviews(for bookId: Int) async {
        await MainActor.run {
            isLoadingReviews = true
            reviewsError = nil
            reviewsPage = 0
            canLoadMoreReviews = true
            reviews = []
        }
        let list = await HardcoverService.fetchPublicReviewsForBook(bookId: bookId, limit: reviewsPageSize, offset: 0)
        await MainActor.run {
            isLoadingReviews = false
            reviews = list
            canLoadMoreReviews = list.count == reviewsPageSize
            reviewsPage = 1
        }
    }
    
    private func loadMoreReviews(for bookId: Int) async {
        guard !isLoadingReviews, canLoadMoreReviews else { return }
        await MainActor.run { isLoadingReviews = true }
        let offset = reviewsPage * reviewsPageSize
        let list = await HardcoverService.fetchPublicReviewsForBook(bookId: bookId, limit: reviewsPageSize, offset: offset)
        await MainActor.run {
            isLoadingReviews = false
            if list.isEmpty {
                canLoadMoreReviews = false
            } else {
                reviews.append(contentsOf: list)
                reviewsPage += 1
                if list.count < reviewsPageSize { canLoadMoreReviews = false }
            }
        }
    }
    
    // MARK: Taxonomies
    private func reloadTaxonomies() async {
        await MainActor.run {
            if genres.isEmpty { isLoadingGenres = true }
            if moods.isEmpty { isLoadingMoods = true }
        }
        async let g = self.fetchGenresPreferred(bookId: book.bookId, editionId: book.editionId, userBookId: book.userBookId)
        async let m = self.fetchMoodsPreferred(bookId: book.bookId, editionId: book.editionId, userBookId: book.userBookId)
        let (gList, mList) = await (g, m)
        await MainActor.run {
            self.genres = gList
            self.moods = mList
            self.isLoadingGenres = false
            self.isLoadingMoods = false
        }
    }
    
    private func fetchGenresPreferred(bookId: Int?, editionId: Int?, userBookId: Int?) async -> [String] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        func normalize(_ arr: [String]) -> [String] {
            let cleaned = arr
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(cleaned)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        
        // Curated only: cached_tags paths
        if let bid = bookId {
            if let arr = await queryBookCachedGenres(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await queryUserBookCachedGenres(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        // No fallback to taggings to ensure only curated genres are shown
        return []
    }
    
    private func fetchMoodsPreferred(bookId: Int?, editionId: Int?, userBookId: Int?) async -> [String] {
        guard !HardcoverConfig.apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return [] }
        
        func normalize(_ arr: [String]) -> [String] {
            let cleaned = arr
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(Set(cleaned)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        
        // 1) Taggings path
        if let bid = bookId {
            if let arr = await queryBookMoodsViaTaggings(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let eid = editionId {
            if let arr = await queryEditionBookMoodsViaTaggings(url: url, editionId: eid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await queryUserBookMoodsViaTaggings(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        
        // 2) cached_tags path
        if let bid = bookId {
            if let arr = await queryBookCachedMoods(url: url, bookId: bid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let eid = editionId {
            if let arr = await queryEditionBookCachedMoods(url: url, editionId: eid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        if let ubid = userBookId {
            if let arr = await queryUserBookCachedMoods(url: url, userBookId: ubid), !arr.isEmpty {
                return normalize(arr)
            }
        }
        return []
    }
    
    // MARK: - Rating/Review submission helpers
    private func submitRatingAndOrReview() async {
        guard let bookId = book.bookId else { return }
        let trimmed = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard myRating != nil || !trimmed.isEmpty else { return }
        
        await MainActor.run {
            isSubmittingReview = true
            submitMessage = nil
            submitError = nil
        }
        
        // 1) Ensure we have a user_book id for this book (create Finished if missing)
        var userBookId = book.userBookId
        if userBookId == nil {
            // Try to find an existing one for this user/book
            userBookId = await fetchLatestUserBookIdForBook(bookId: bookId)
        }
        if userBookId == nil {
            // Create a Finished row (optionally include edition + rating if set)
            let ok = await HardcoverService.finishBookByBookId(bookId: bookId, editionId: selectedEditionId ?? book.editionId, pages: nil, rating: myRating)
            if ok {
                userBookId = await fetchLatestUserBookIdForBook(bookId: bookId)
            }
        }
        guard let ubid = userBookId else {
            await MainActor.run {
                isSubmittingReview = false
                submitError = NSLocalizedString("Could not create an entry to attach your review.", comment: "")
            }
            return
        }
        
        // 2) Update rating if provided
        var didAny = false
        if let rating = myRating {
            let ok = await HardcoverService.updateUserBookRating(userBookId: ubid, rating: rating)
            didAny = didAny || ok
        }
        // 3) Publish review if provided
        if !trimmed.isEmpty {
            let ok = await HardcoverService.publishReview(userBookId: ubid, text: trimmed, hasSpoilers: hasSpoilers)
            didAny = didAny || ok
        }
        
        // 4) Refresh public reviews list
        if let id = book.bookId {
            await reloadReviews(for: id)
        }
        
        await MainActor.run {
            isSubmittingReview = false
            if didAny {
                submitMessage = NSLocalizedString("Thanks for your review!", comment: "")
#if os(iOS) && !targetEnvironment(macCatalyst)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
            } else {
                submitError = NSLocalizedString("Could not submit your rating/review. Please try again.", comment: "")
#if os(iOS) && !targetEnvironment(macCatalyst)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
            }
        }
    }
    
    // Find the most recent user_book id for the current user and given book
    private func fetchLatestUserBookIdForBook(bookId: Int) async -> Int? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let query = """
        query ($bookId: Int!) {
          user_books(
            where: { book_id: { _eq: $bookId } },
            order_by: { id: desc },
            limit: 1
          ) {
            id
          }
        }
        """
        let body: [String: Any] = ["query": query, "variables": ["bookId": bookId]]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errs = root["errors"] as? [[String: Any]], !errs.isEmpty { return nil }
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = root["data"] as? [String: Any],
               let rows = dataDict["user_books"] as? [[String: Any]],
               let first = rows.first,
               let id = first["id"] as? Int {
                return id
            }
        } catch { return nil }
        return nil
    }
}

// A small star rating control with 0.5 increments (tap/long-press to toggle halves)
private struct StarRatingPicker: View {
    @Binding var rating: Double?
    
    private func starSymbol(for index: Int) -> String {
        guard let r = rating else { return "star" }
        let threshold = Double(index) + 1.0
        if r >= threshold {
            return "star.fill"
        } else if r + 0.5 >= threshold {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
    
    private func setRating(for index: Int) {
        // Toggle in 0.5 steps. Tap cycles: empty -> .5 -> 1.0 for the first star, etc.
        let base = Double(index) + 1.0
        if let r = rating {
            if r >= base {
                // currently full -> clear to nil if last star tapped, else drop to half
                rating = (abs(r - base) < 0.001) ? nil : (base - 0.5)
            } else if r + 0.5 >= base {
                // currently half -> bump to full
                rating = base
            } else {
                // below -> set to half
                rating = base - 0.5
            }
        } else {
            rating = base - 0.5
        }
        // Clamp 0…5
        if let r = rating {
            rating = min(5.0, max(0.5, (round(r * 2) / 2)))
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { idx in
                Image(systemName: starSymbol(for: idx))
                    .foregroundColor(.orange)
                    .font(.title3)
                    .onTapGesture {
                        setRating(for: idx)
                    }
                    .accessibilityLabel("Rate")
            }
            if let r = rating {
                Text("\(r, specifier: "%.1f")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.leading, 6)
            } else {
                Text("No rating")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.leading, 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your rating")
        .accessibilityValue(rating != nil ? "\(rating!, specifier: "%.1f") of 5" : "No rating")
    }
}

// MARK: - Review row with like/unlike for SearchResultDetailSheet
private struct SearchReviewRow: View {
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
                // Small stars, same look as Trending’s inline
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        let threshold = Double(i) + 1.0
                        if r >= threshold {
                            Image(systemName: "star.fill").foregroundColor(.orange)
                        } else if r + 0.5 >= threshold {
                            Image(systemName: "star.leadinghalf.filled").foregroundColor(.orange)
                        } else {
                            Image(systemName: "star").foregroundColor(.orange.opacity(0.35))
                        }
                    }
                }
                .font(.caption)
                .accessibilityLabel("Rating")
                .accessibilityValue("\(r, specifier: "%.1f") of 5")
            }
            if let text = review.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Like row
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
        guard !isLiking else { return }
        let wasLiked = userHasLiked
        let newLikeState = !wasLiked
        
        await MainActor.run {
            isLiking = true
            // Optimistic update
            userHasLiked = newLikeState
            if newLikeState {
                likesCount += 1
            } else {
                likesCount = max(0, likesCount - 1)
            }
        }
        
        // Local helper to avoid cross-target dependency on HardcoverService extension
        let result = await setLike(likeableId: review.id, like: newLikeState, likeableType: "UserBook")
        
        await MainActor.run {
            if let result {
                // Update with confirmed state from server
                likesCount = max(0, result.likesCount)
                userHasLiked = result.didLike
#if os(iOS) && !targetEnvironment(macCatalyst)
                if userHasLiked {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
#endif
            } else {
                // Rollback on failure
                userHasLiked = wasLiked
                if wasLiked {
                    likesCount += 1
                } else {
                    likesCount = max(0, likesCount - 1)
                }
            }
            isLiking = false
        }
    }
    
    // MARK: - Local like helpers (mirrors HardcoverService+LikesToggle)
    private func setLike(likeableId: Int, like: Bool, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        if like {
            return await upsertLike(likeableId: likeableId, likeableType: likeableType)
        } else {
            return await deleteLike(likeableId: likeableId, likeableType: likeableType)
        }
    }
    
    private func upsertLike(likeableId: Int, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let mutation = """
        mutation UpsertLike($likeableId: Int!, $likeableType: String!) {
          likeResult: upsert_like(likeable_id: $likeableId, likeable_type: $likeableType) {
            likesCount: likes_count
            __typename
          }
        }
        """
        let vars: [String: Any] = ["likeableId": likeableId, "likeableType": likeableType]
        let body: [String: Any] = ["query": mutation, "variables": vars]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["errors"] as? [[String: Any]])?.isEmpty != false,
                  let dataDict = root["data"] as? [String: Any],
                  let likeResult = dataDict["likeResult"] as? [String: Any],
                  let likesCount = likeResult["likesCount"] as? Int else { return nil }
            return (max(0, likesCount), true)
        } catch { return nil }
    }
    
    private func deleteLike(likeableId: Int, likeableType: String = "UserBook") async -> (likesCount: Int, didLike: Bool)? {
        guard !HardcoverConfig.apiKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let mutation = """
        mutation DeleteLike($likeableId: Int!, $likeableType: String!) {
          likeResult: delete_like(likeable_id: $likeableId, likeable_type: $likeableType) {
            likesCount: likes_count
            __typename
          }
        }
        """
        let vars: [String: Any] = ["likeableId": likeableId, "likeableType": likeableType]
        let body: [String: Any] = ["query": mutation, "variables": vars]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["errors"] as? [[String: Any]])?.isEmpty != false,
                  let dataDict = root["data"] as? [String: Any],
                  let likeResult = dataDict["likeResult"] as? [String: Any],
                  let likesCount = likeResult["likesCount"] as? Int else { return nil }
            return (max(0, likesCount), false)
        } catch { return nil }
    }
}

// MARK: - UI helper for Trending header
private struct IfTrendingLoadingView_Previews: PreviewProvider {
    static var previews: some View {
        IfTrendingLoadingView(trendingLoading: true, onReload: {})
    }
}

#Preview { SearchBooksView { _ in } }
