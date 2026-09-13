import Foundation

// MARK: - User Stats Models
struct UserStats: Codable {
    let booksRead: Int?
    let pagesRead: Int?
    let currentlyReading: Int?
    let wantToRead: Int?
    let averageRating: Double?
    let totalRatings: Int?
    let authorsRead: Int?
    let reviewsWritten: Int?
    let hoursListened: Double?
    
    var hasData: Bool {
        booksRead != nil || pagesRead != nil || currentlyReading != nil || wantToRead != nil || authorsRead != nil || reviewsWritten != nil || hoursListened != nil
    }
}

extension HardcoverService {
    /// Fetch statistics for any user by parsing their stats page
    static func fetchUserStats(username: String) async -> UserStats? {
        guard !HardcoverConfig.apiKey.isEmpty else {
            print("❌ No API key available")
            return nil
        }
        
        // Fetch from stats page instead of profile page
        guard let url = URL(string: "https://hardcover.app/@\(username)/stats") else {
            print("❌ Invalid URL")
            return nil
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(HardcoverConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await HardcoverHTTP.shared.data(for: req)
            
            guard let html = String(data: data, encoding: .utf8) else {
                print("❌ Could not decode HTML")
                return nil
            }
            
            // Extract stats from HTML
            if let stats = extractStatsFromHTML(html) {
                print("✅ Fetched stats for @\(username)")
                return stats
            }
            
            return nil
        } catch {
            print("❌ Failed to fetch user stats: \(error)")
            return nil
        }
    }
    
    /// Extract stats from Inertia.js data-page attribute
    private static func extractStatsFromHTML(_ html: String) -> UserStats? {
        // Find data-page attribute
        guard let dataPageRange = html.range(of: "data-page=\"") else {
            print("❌ Could not find data-page attribute")
            print("📄 HTML preview: \(String(html.prefix(1000)))")
            return nil
        }
        
        let startIndex = dataPageRange.upperBound
        guard let endIndex = html[startIndex...].range(of: "\">")?.lowerBound else {
            print("❌ Could not find end of data-page attribute")
            return nil
        }
        
        let jsonString = String(html[startIndex..<endIndex])
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ Could not convert JSON string to data")
            return nil
        }
        
        print("📦 JSON preview: \(String(jsonString.prefix(1000)))")
        
        do {
        // First try to decode to see what structure we have
        if let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let props = jsonObject["props"] as? [String: Any] {
            print("📊 Props keys: \(props.keys.joined(separator: ", "))")
            
            if let stats = props["stats"] as? [String: Any] {
                print("📈 Stats keys: \(stats.keys.joined(separator: ", "))")
                
                // Check if there's a summary object
                if let summary = stats["summary"] as? [String: Any] {
                    print("� Summary keys: \(summary.keys.joined(separator: ", "))")
                }
                
                // Check authorsBreakdown
                if let authorsBreakdown = stats["authorsBreakdown"] as? [[String: Any]] {
                    let authorsRead = authorsBreakdown.count
                    print("✍️ Authors breakdown count: \(authorsRead)")
                }
            }
            
            if let user = props["user"] as? [String: Any] {
                print("👤 User keys: \(user.keys.joined(separator: ", "))")
            }
        }            // Try to decode as stats page first
            let userPageData = try? JSONDecoder().decode(InertiaUserPageData.self, from: jsonData)
            
            // Extract stats from the props
            var stats = UserStats(
                booksRead: nil,
                pagesRead: nil,
                currentlyReading: nil,
                wantToRead: nil,
                averageRating: nil,
                totalRatings: nil,
                authorsRead: nil,
                reviewsWritten: nil,
                hoursListened: nil
            )
            
            // Try to extract stats directly from JSON
            if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let props = jsonObject["props"] as? [String: Any],
               let statsDict = props["stats"] as? [String: Any] {
                
                print("✅ Found stats data in page")
                
                var booksRead: Int?
                var pagesRead: Int?
                var authorsRead: Int?
                var reviewsWritten: Int?
                var hoursListened: Double?
                
                // Try to get from top-level stats first
                booksRead = statsDict["booksRead"] as? Int
                pagesRead = statsDict["pagesRead"] as? Int
                
                // Get from summary object
                if let summary = statsDict["summary"] as? [String: Any] {
                    // Use summary values, they're more reliable
                    if let summaryBooksRead = summary["booksRead"] as? Int {
                        booksRead = summaryBooksRead
                        print("📚 Books read (from summary): \(summaryBooksRead)")
                    }
                    if let summaryPagesRead = summary["pagesRead"] as? Int {
                        pagesRead = summaryPagesRead
                        print("📄 Pages read (from summary): \(summaryPagesRead)")
                    }
                    if let authorsReadCount = summary["authorsReadCount"] as? Int {
                        authorsRead = authorsReadCount
                        print("✍️ Authors read: \(authorsReadCount)")
                    }
                    if let reviewsCount = summary["reviewsCount"] as? Int {
                        reviewsWritten = reviewsCount
                        print("✏️ Reviews written: \(reviewsCount)")
                    }
                    if let hours = summary["hoursListened"] as? Double {
                        hoursListened = hours
                        print("🎧 Hours listened: \(hours)")
                    }
                }
                
                stats = UserStats(
                    booksRead: booksRead,
                    pagesRead: pagesRead,
                    currentlyReading: stats.currentlyReading,
                    wantToRead: stats.wantToRead,
                    averageRating: stats.averageRating,
                    totalRatings: stats.totalRatings,
                    authorsRead: authorsRead,
                    reviewsWritten: reviewsWritten,
                    hoursListened: hoursListened
                )
            }
            // Fall back to user page data
            else if let user = userPageData?.props.user {
                print("✅ Found user in page data (fallback)")
                
                // Get stats from statusLists array
                if let statusLists = user.statusLists {
                    for statusList in statusLists {
                        if let status = statusList.status, let count = statusList.count {
                            print("� Status: \(status) = \(count)")
                            
                            switch status.lowercased() {
                            case "finished", "read":
                                stats = UserStats(
                                    booksRead: count,
                                    pagesRead: stats.pagesRead,
                                    currentlyReading: stats.currentlyReading,
                                    wantToRead: stats.wantToRead,
                                    averageRating: stats.averageRating,
                                    totalRatings: stats.totalRatings,
                                    authorsRead: stats.authorsRead,
                                    reviewsWritten: stats.reviewsWritten,
                                    hoursListened: stats.hoursListened
                                )
                            case "reading", "currently_reading":
                                stats = UserStats(
                                    booksRead: stats.booksRead,
                                    pagesRead: stats.pagesRead,
                                    currentlyReading: count,
                                    wantToRead: stats.wantToRead,
                                    averageRating: stats.averageRating,
                                    totalRatings: stats.totalRatings,
                                    authorsRead: stats.authorsRead,
                                    reviewsWritten: stats.reviewsWritten,
                                    hoursListened: stats.hoursListened
                                )
                            case "want_to_read", "wanttoread", "to_read":
                                stats = UserStats(
                                    booksRead: stats.booksRead,
                                    pagesRead: stats.pagesRead,
                                    currentlyReading: stats.currentlyReading,
                                    wantToRead: count,
                                    averageRating: stats.averageRating,
                                    totalRatings: stats.totalRatings,
                                    authorsRead: stats.authorsRead,
                                    reviewsWritten: stats.reviewsWritten,
                                    hoursListened: stats.hoursListened
                                )
                            default:
                                print("⚠️ Unknown status: \(status)")
                            }
                        }
                    }
                }
                
                // Fallback to booksCount if statusLists not available
                if stats.booksRead == nil, let booksCount = user.booksCount {
                    print("📚 Total books (fallback): \(booksCount)")
                    stats = UserStats(
                        booksRead: booksCount,
                        pagesRead: stats.pagesRead,
                        currentlyReading: stats.currentlyReading,
                        wantToRead: stats.wantToRead,
                        averageRating: stats.averageRating,
                        totalRatings: stats.totalRatings,
                        authorsRead: stats.authorsRead,
                        reviewsWritten: stats.reviewsWritten,
                        hoursListened: stats.hoursListened
                    )
                }
            } else {
                print("⚠️ No stats or user found in page data")
            }
            
            if stats.hasData {
                print("✅ Successfully extracted stats")
                return stats
            } else {
                print("⚠️ No stats data found")
                return nil
            }
            
        } catch {
            print("❌ Failed to decode page data: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("🔑 Missing key: \(key.stringValue) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .typeMismatch(let type, let context):
                    print("🔄 Type mismatch for type \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .valueNotFound(let type, let context):
                    print("❓ Value not found for type \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                case .dataCorrupted(let context):
                    print("💥 Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                @unknown default:
                    print("❓ Unknown decoding error")
                }
            }
            return nil
        }
    }
}

// MARK: - Inertia Page Data Models for User Stats
struct InertiaUserPageData: Codable {
    let props: InertiaUserProps
}

struct InertiaStatsPageData: Codable {
    let props: InertiaStatsProps
}

struct InertiaUserProps: Codable {
    let user: InertiaUser?
}

struct InertiaStatsProps: Codable {
    let stats: StatsData?
    let user: InertiaUser?
}

struct StatsData: Codable {
    let booksRead: Int?
    let pagesRead: Int?
    let authorsRead: Int?
    let reviewsWritten: Int?
    let hoursListened: Double?
    
    enum CodingKeys: String, CodingKey {
        case booksRead = "books_read"
        case pagesRead = "pages_read"
        case authorsRead = "authors_read"
        case reviewsWritten = "reviews_written"
        case hoursListened = "hours_listened"
    }
}

struct InertiaUser: Codable {
    let id: Int?
    let username: String?
    let bio: String?
    let booksCount: Int?
    let followersCount: Int?
    let followedUsersCount: Int?
    let statusLists: [StatusList]?
    let user_reads_aggregate: ReadAggregate?
    let currently_reading_aggregate: ReadAggregate?
    let want_to_read_aggregate: ReadAggregate?
}

struct StatusList: Codable {
    let status: String?
    let count: Int?
}

struct ReadAggregate: Codable {
    let aggregate: AggregateCount?
}

struct AggregateCount: Codable {
    let count: Int?
}
