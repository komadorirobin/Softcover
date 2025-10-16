import SwiftUI

struct EditionRow: View {
    let edition: Edition
    let isSelected: Bool
    let isCurrent: Bool
    let onTap: () -> Void
    
    private var cornerRadius: CGFloat { 14 }
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Selection indicator (vänster, som i bilden)
                selectionIndicator
                    .padding(.top, 2)
                
                // Cover
                coverView
                    .frame(width: 56, height: 84)
                    .clipped()
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                
                // Textinnehåll
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(edition.displayTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        if isCurrent {
                            Text("NUVARANDE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.18))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(edition.displayInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    if let isbn13 = edition.isbn13, !isbn13.isEmpty {
                        Text("ISBN: \(isbn13)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(UIColor.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var coverView: some View {
        if let imageUrl = edition.image?.url, let url = URL(string: imageUrl) {
            // Använder projektets cache
            AsyncCachedImage(url: url, maxPixel: 220) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                    .overlay(
                        Image(systemName: "book.closed")
                            .foregroundColor(.secondary)
                    )
            }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.15))
                .overlay(
                    Image(systemName: "book.closed")
                        .foregroundColor(.secondary)
                )
        }
    }
    
    private var selectionIndicator: some View {
        Group {
            if isSelected {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                }
            } else {
                Circle()
                    .stroke(Color.secondary, lineWidth: 2)
            }
        }
        .frame(width: 22, height: 22)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityHidden(true)
    }
}
