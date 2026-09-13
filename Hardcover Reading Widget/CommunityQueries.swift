import Foundation

enum CommunityQueries {
    struct UpcomingInterval: Equatable {
        let start: String
        let endExclusive: String
    }

    static func upcomingInterval(filter: String, now: Date = Date()) -> UpcomingInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: now)
        if filter == "recent" {
            return UpcomingInterval(
                start: communityUpcomingDateString(calendar.date(byAdding: .day, value: -30, to: today)!),
                endExclusive: communityUpcomingDateString(calendar.date(byAdding: .day, value: 1, to: today)!))
        }
        let months = filter == "quarter" ? 3 : (filter == "year" ? 12 : 1)
        return UpcomingInterval(
            start: communityUpcomingDateString(today),
            endExclusive: communityUpcomingDateString(calendar.date(byAdding: .month, value: months, to: today)!))
    }


    static let upcomingBooks = """
        query CommunityUpcomingBooks($start: date!, $end: date!, $limit: Int!) {
          books(
            where: {
              release_date: { _gte: $start, _lt: $end }
            },
            order_by: [{ users_count: desc }, { release_date: asc }],
            limit: $limit
          ) {
            id
            title
            release_date
            users_count
            users_read_count
            contributions(limit: 1) { author { name } }
            image { url }
          }
        }
        """

    static let upcomingEditions = """
        query CommunityUpcomingEditions($start: date!, $end: date!, $limit: Int!) {
          editions(
            where: {
              release_date: { _gte: $start, _lt: $end }
            },
            order_by: [{ users_count: desc }, { release_date: asc }],
            limit: $limit
          ) {
            id
            book_id
            title
            release_date
            users_count
            users_read_count
            contributions(limit: 1) { author { name } }
            image { url }
            book {
              id
              title
              release_date
              users_count
              users_read_count
              contributions(limit: 1) { author { name } }
              image { url }
            }
          }
        }
        """

    static let history = """
    query LibraryHistory($userId: Int!, $limit: Int!, $offset: Int!) {
      user_book_reads(
        where: {finished_at: {_is_null: false}, user_book: {user_id: {_eq: $userId}}},
        order_by: [{finished_at: desc}, {id: desc}], limit: $limit, offset: $offset
      ) {
        id finished_at
        user_book {
          id book_id rating
          book { id title contributions(limit: 1) { author { name } } image { url } }
          edition { id title image { url } }
        }
      }
    }
    """

    private static func communityUpcomingDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
