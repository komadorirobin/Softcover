import SwiftUI

struct BookCoverImage: View {
    let url: URL?
    
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fit)
            case .failure:
                Image(systemName: "book.closed")
            @unknown default:
                EmptyView()
            }
        }
    }
}
