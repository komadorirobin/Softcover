import Foundation

enum BookDetailQueries {
    static let metadata = """
    query BookDetails($id: Int!) {
      books(where: {id: {_eq: $id}}, limit: 1) {
        id title description rating cached_tags cached_contributors release_date image { url }
      }
    }
    """
    static let reviews = """
    query BookReviews($bookID: Int!, $offset: Int!) {
      user_books(where: {book_id: {_eq: $bookID}, has_review: {_eq: true}, privacy_setting_id: {_eq: 1}},
        order_by: [{reviewed_at: desc_nulls_last}, {id: desc}], limit: 10, offset: $offset) {
        id rating reviewed_at review_raw user { username }
      }
    }
    """
    static let reviewLikes = """
    query BookReviewLikes($ids: [Int!], $userID: Int!) {
      likes(where: {likeable_id: {_in: $ids}, likeable_type: {_eq: "UserBook"}}) { likeable_id }
      mine: likes(where: {likeable_id: {_in: $ids}, likeable_type: {_eq: "UserBook"}, user_id: {_eq: $userID}}) { likeable_id }
    }
    """
    static let quotes = """
    query BookQuotes($bookID: Int!, $userID: Int!) {
      user_books(where: {book_id: {_eq: $bookID}, user_id: {_eq: $userID}}) {
        book { title }
        reading_journals(where: {event: {_eq: "quote"}}, order_by: {id: desc}) {
          id entry book_id created_at edition_id privacy_setting_id metadata
        }
      }
    }
    """
}
