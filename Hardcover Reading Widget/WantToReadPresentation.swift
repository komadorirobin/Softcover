import Foundation

enum WantToReadFilter: String, CaseIterable {
    case all = "All", upcoming = "Upcoming", recent = "Recent"
}

enum WantToReadSort: String, CaseIterable {
    case nearestRelease, newestRelease, oldestRelease, recentlyAdded

    var title: String {
        switch self {
        case .nearestRelease: "Nearest release"
        case .newestRelease: "Release date (newest first)"
        case .oldestRelease: "Release date (oldest first)"
        case .recentlyAdded: "Recently Added"
        }
    }
}

enum WantToReadPresentation {
    private static var dateCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    // Release dates are calendar dates encoded as UTC, not instants in the user's time zone.
    static func today(now: Date, timeZone: TimeZone = .current) -> Date {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        return dateCalendar.date(from: localCalendar.dateComponents([.year, .month, .day], from: now))!
    }

    static func daysUntil(_ release: Date, now: Date, timeZone: TimeZone = .current) -> Int {
        dateCalendar.dateComponents([.day], from: today(now: now, timeZone: timeZone),
                                    to: dateCalendar.startOfDay(for: release)).day!
    }

    static func books(_ books: [BookProgress], query: String, filter: WantToReadFilter,
                      sort: WantToReadSort, now: Date, timeZone: TimeZone = .current) -> [BookProgress] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let today = today(now: now, timeZone: timeZone)
        var rows = books.compactMap { book -> (book: BookProgress, date: Date?)? in
            guard query.isEmpty || book.title.localizedCaseInsensitiveContains(query)
                    || book.author.localizedCaseInsensitiveContains(query) else { return nil }
            let date = book.parsedReleaseDate ?? ReleaseDate.parse(book.releaseDate)
            if filter != .all {
                guard let date, filter == .upcoming ? date >= today : date < today else { return nil }
            }
            return (book, date)
        }
        guard sort != .recentlyAdded else { return rows.map(\.book) }
        rows.sort { lhs, rhs in
            if lhs.date == rhs.date { return lhs.book.id < rhs.book.id }
            guard let a = lhs.date else { return false }
            guard let b = rhs.date else { return true }
            switch sort {
            case .nearestRelease:
                if (a >= today) != (b >= today) { return a >= today }
                return a >= today ? a < b : a > b
            case .newestRelease: return a > b
            case .oldestRelease: return a < b
            case .recentlyAdded: return false
            }
        }
        return rows.map(\.book)
    }
}
