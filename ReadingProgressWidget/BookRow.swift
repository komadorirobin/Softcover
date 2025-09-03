import SwiftUI

struct BookRow: View {
    var book: BookProgress

    var body: some View {
        HStack {
            // Use the image data if available
            if let imageData = book.coverImageData, 
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 70)
                    .clipped()
            } else {
                // Placeholder when no image is available
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 70)
            }

            VStack(alignment: .leading) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Progress information
                if book.totalPages > 0 {
                    HStack {
                        Text("Page \(book.currentPage) of \(book.totalPages)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(book.progress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                            
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: CGFloat(book.progress) * geometry.size.width)
                        }
                        .cornerRadius(2)
                    }
                    .frame(height: 4)
                } else if book.progress > 0 {
                    Text("Progress: \(Int(book.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No progress info")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}