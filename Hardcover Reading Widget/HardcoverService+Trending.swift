import Foundation

extension HardcoverService {
    static func fetchTrendingBooks(timeFilter: String) async -> [TrendingBook] {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key configured for trending")
            return []
        }

        let limit = 25
        guard let since = trendingStartDate(for: timeFilter) else {
            return await fetchPopularBooksForTrending(limit: limit)
        }

        let activityBooks = await fetchTrendingBooksFromActivity(since: since, limit: limit)
        if !activityBooks.isEmpty {
            return activityBooks
        }

        let recentBooks = await fetchRecentlyAddedPopularBooksForTrending(since: since, limit: limit)
        if !recentBooks.isEmpty {
            return recentBooks
        }

        return await fetchPopularBooksForTrending(limit: limit)
    }

    private static func trendingStartDate(for timeFilter: String) -> Date? {
        let days: Int
        switch timeFilter {
        case "month":
            days = 30
        case "recent":
            days = 90
        case "year":
            days = 365
        default:
            return nil
        }

        return Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }

    private static func fetchTrendingBooksFromActivity(since: Date, limit: Int) async -> [TrendingBook] {
        let query = """
        query TrendingBooksFromActivity($since: timestamptz!, $limit: Int!) {
          activities(
            where: {
              book_id: { _is_null: false },
              created_at: { _gte: $since }
            },
            order_by: { created_at: desc },
            limit: $limit
          ) {
            book_id
            book {
              id
              title
              users_count
              users_read_count
              contributions(limit: 1) { author { name } }
              image { url }
            }
          }
        }
        """

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let fetchLimit = min(max(limit * 60, 600), 1000)

        guard let root = await performTrendingGraphQL(
            query: query,
            variables: [
                "since": formatter.string(from: since),
                "limit": fetchLimit
            ]
        ),
              let data = root["data"] as? [String: Any],
              let rows = data["activities"] as? [[String: Any]] else {
            return []
        }

        var grouped: [Int: (book: [String: Any], activityCount: Int)] = [:]

        for row in rows {
            guard let bookId = intValue(row["book_id"]),
                  let book = row["book"] as? [String: Any] else {
                continue
            }

            if let existing = grouped[bookId] {
                grouped[bookId] = (book: existing.book, activityCount: existing.activityCount + 1)
            } else {
                grouped[bookId] = (book: book, activityCount: 1)
            }
        }

        return grouped.values
            .sorted { lhs, rhs in
                if lhs.activityCount != rhs.activityCount {
                    return lhs.activityCount > rhs.activityCount
                }

                let lhsUsers = intValue(lhs.book["users_count"]) ?? intValue(lhs.book["users_read_count"]) ?? 0
                let rhsUsers = intValue(rhs.book["users_count"]) ?? intValue(rhs.book["users_read_count"]) ?? 0
                return lhsUsers > rhsUsers
            }
            .prefix(limit)
            .compactMap { makeTrendingBook(from: $0.book) }
    }

    private static func fetchRecentlyAddedPopularBooksForTrending(since: Date, limit: Int) async -> [TrendingBook] {
        let query = """
        query RecentPopularBooks($since: timestamp!, $limit: Int!) {
          books(
            where: { created_at: { _gte: $since } },
            order_by: { users_count: desc },
            limit: $limit
          ) {
            id
            title
            users_count
            users_read_count
            contributions(limit: 1) { author { name } }
            image { url }
          }
        }
        """

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        guard let root = await performTrendingGraphQL(
            query: query,
            variables: [
                "since": formatter.string(from: since),
                "limit": max(1, limit)
            ]
        ),
              let data = root["data"] as? [String: Any],
              let rows = data["books"] as? [[String: Any]] else {
            return []
        }

        return rows.compactMap { makeTrendingBook(from: $0) }
    }

    private static func fetchPopularBooksForTrending(limit: Int) async -> [TrendingBook] {
        let query = """
        query PopularBooks($limit: Int!) {
          books(
            order_by: { users_count: desc },
            limit: $limit
          ) {
            id
            title
            users_count
            users_read_count
            contributions(limit: 1) { author { name } }
            image { url }
          }
        }
        """

        guard let root = await performTrendingGraphQL(
            query: query,
            variables: ["limit": max(1, limit)]
        ),
              let data = root["data"] as? [String: Any],
              let rows = data["books"] as? [[String: Any]] else {
            return []
        }

        return rows.compactMap { makeTrendingBook(from: $0) }
    }

    private static func performTrendingGraphQL(query: String, variables: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: "https://api.hardcover.app/v1/graphql") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("Softcover iOS", forHTTPHeaderField: "User-Agent")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "query": query,
                "variables": variables
            ])

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("❌ Trending GraphQL HTTP \(http.statusCode)")
                return nil
            }

            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            if let error = root["error"] as? String, !error.isEmpty {
                print("❌ Trending GraphQL Error: \(error)")
                return nil
            }

            if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
                for error in errors {
                    if let message = error["message"] as? String {
                        print("❌ Trending GraphQL Error: \(message)")
                    }
                }
                return nil
            }

            return root
        } catch {
            print("❌ Trending GraphQL request failed: \(error)")
            return nil
        }
    }

    private static func makeTrendingBook(from dict: [String: Any]) -> TrendingBook? {
        guard let id = intValue(dict["id"]) else {
            return nil
        }

        let title = (dict["title"] as? String)?.decodedHTMLEntities ?? "Unknown Title"
        let author = authorName(from: dict["contributions"])
            ?? authorName(from: dict["cached_contributors"])
            ?? "Unknown Author"
        let imageUrl = imageUrl(from: dict["image"])
            ?? imageUrl(from: dict["cached_image"])
        let usersCount = intValue(dict["users_count"]) ?? intValue(dict["users_read_count"]) ?? 0

        return TrendingBook(
            id: id,
            title: title,
            author: author,
            coverImageUrl: imageUrl,
            usersCount: usersCount
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let string = value as? String {
            return Int(string)
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func imageUrl(from value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty {
            return string
        }

        guard let dict = value as? [String: Any] else {
            return nil
        }

        if let url = dict["url"] as? String, !url.isEmpty {
            return url
        }
        if let small = dict["small"] as? [String: Any],
           let url = small["url"] as? String,
           !url.isEmpty {
            return url
        }
        if let medium = dict["medium"] as? [String: Any],
           let url = medium["url"] as? String,
           !url.isEmpty {
            return url
        }

        return nil
    }

    private static func authorName(from value: Any?) -> String? {
        if let names = value as? [String] {
            return names.first { !$0.isEmpty }
        }

        if let contributors = value as? [[String: Any]] {
            for contributor in contributors {
                if let name = contributor["name"] as? String, !name.isEmpty {
                    return name
                }
                if let name = contributor["author_name"] as? String, !name.isEmpty {
                    return name
                }
                if let author = contributor["author"] as? [String: Any],
                   let name = author["name"] as? String,
                   !name.isEmpty {
                    return name
                }
            }
        }

        if let dict = value as? [String: Any] {
            if let name = dict["name"] as? String, !name.isEmpty {
                return name
            }
            if let name = dict["author_name"] as? String, !name.isEmpty {
                return name
            }
            if let authors = dict["authors"] as? [[String: Any]] {
                return authorName(from: authors)
            }
        }

        return nil
    }
}
