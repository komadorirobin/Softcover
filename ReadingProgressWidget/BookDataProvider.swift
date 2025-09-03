//
//  BookDataProvider.swift
//  Hardcover Reading WidgetExtension
//
//  Created by Robin Bolinsson on 2024-08-21.
//

import Foundation
import UIKit

struct BookDataProvider {
  static func getSampleBooks() -> [BookProgress] {
      return [
          BookProgress(
              id: "1",
              title: "The Great Gatsby",
              author: "F. Scott Fitzgerald",
              coverImageData: nil,
              progress: 0.75,
              totalPages: 180,
              currentPage: 135,
              bookId: nil,
              userBookId: nil,
              editionId: nil,
              originalTitle: "The Great Gatsby"
          ),
          BookProgress(
              id: "2",
              title: "To Kill a Mockingbird",
              author: "Harper Lee",
              coverImageData: nil,
              progress: 0.3,
              totalPages: 324,
              currentPage: 97,
              bookId: nil,
              userBookId: nil,
              editionId: nil,
              originalTitle: "To Kill a Mockingbird"
          )
      ]
  }
}
