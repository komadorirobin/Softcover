import SwiftUI
import WidgetKit

struct WidgetView : View {
    let entry: SimpleEntry

    var body: some View {
        VStack(spacing: 6) {
            // Header
            HStack {
                Text("Currently Reading")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // Show all books (up to 5)
            if !entry.books.isEmpty {
                ForEach(entry.books.prefix(5), id: \.id) { book in
                    HStack(spacing: 8) {
                        // Book cover (smaller for multiple books)
                        if let imageData = book.coverImageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 55)
                                .clipped()
                                .cornerRadius(4)
                        } else {
                            // Placeholder when no image is available
                            Rectangle()
                                .fill(Color("WidgetBackground").opacity(0.3))
                                .frame(width: 40, height: 55)
                                .cornerRadius(4)
                        }
                        
                        // Book info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(2)
                            
                            Text(book.author)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            // Progress information
                            if book.currentPage > 0 {
                                HStack {
                                    Text("Page \(book.currentPage)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    if book.totalPages > 0 {
                                        Text("\(Int(book.progress * 100))%")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                    }
                                }
                            } else if book.progress > 0 {
                                Text("\(Int(book.progress * 100))% complete")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            } else {
                // Fallback when no books
                Text("No books found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Last updated time
            Text("Updated: \(entry.date, style: .time)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
        .padding(8)
    }
}
