import SwiftUI

struct EditionRow: View {
    let edition: Edition
    let isSelected: Bool
    let isCurrent: Bool
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var cornerRadius: CGFloat { 8 }
    
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(edition.displayTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        
                        if isCurrent {
                            Label("Current edition", systemImage: "checkmark.circle")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.18))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text("Format: \(edition.displayFormat)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isSelected)
        .accessibilityHidden(true)
    }
}
