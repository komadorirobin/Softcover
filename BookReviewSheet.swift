import SwiftUI

struct BookReviewSheet: View {
    let title: String
    let subtitle: String
    @Binding var rating: Double?
    @Binding var reviewText: String
    let onSkip: () -> Void
    let onConfirm: () -> Void
    
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Drag indicator
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 38, height: 5)
                    .padding(.top, 8)
                
                // Title and subtitle
                VStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Rating section
                VStack(spacing: 12) {
                    Text("Rating")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    BookReviewStarRatingView(rating: Binding(
                        get: { rating ?? 0 },
                        set: { rating = $0 }
                    ))
                    
                    VStack(spacing: 6) {
                        HStack {
                            Text("Rating: \(rating ?? 0, specifier: "%.1f")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        Slider(
                            value: Binding(
                                get: { rating ?? 0 },
                                set: { rating = round($0 * 2) / 2 }
                            ),
                            in: 0...5,
                            step: 0.5
                        )
                        .tint(.orange)
                    }
                }
                .padding(.horizontal)
                
                // Review text section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Review (optional)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(reviewText.count)/1000")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(UIColor.secondarySystemBackground))
                            .frame(minHeight: 120)
                        
                        if reviewText.isEmpty {
                            Text("Share your thoughts about this book...")
                                .foregroundColor(.secondary)
                                .font(.body)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        
                        TextEditor(text: $reviewText)
                            .focused($isTextFieldFocused)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 12) {
                    Button("Skip") { 
                        onSkip() 
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    
                    Button("Finish Book") { 
                        onConfirm() 
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled((rating ?? 0) < 0.5)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Review Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isTextFieldFocused = false
                    }
                    .opacity(isTextFieldFocused ? 1 : 0)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            // Scroll up when keyboard appears if needed
        }
        .onChange(of: reviewText) { oldValue, newValue in
            // Limit to 1000 characters
            if newValue.count > 1000 {
                reviewText = String(newValue.prefix(1000))
            }
        }
    }
}

// Custom star rating view for the review sheet
private struct BookReviewStarRatingView: View {
    @Binding var rating: Double // 0.0–5.0, 0.5 steps
    private let maxRating: Double = 5.0
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                BookReviewStarCell(
                    index: index,
                    currentRating: rating,
                    onChange: { newValue in
                        rating = max(0, min(maxRating, (round(newValue * 2) / 2)))
                    }
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating, specifier: "%.1f") of \(Int(maxRating))")
        .accessibilityAdjustableAction { direction in
            let step = 0.5
            switch direction {
            case .increment: rating = min(maxRating, rating + step)
            case .decrement: rating = max(0, rating - step)
            @unknown default: break
            }
        }
    }
}

// Individual star cell for rating interaction
private struct BookReviewStarCell: View {
    let index: Int
    let currentRating: Double
    let onChange: (Double) -> Void
    
    var body: some View {
        GeometryReader { geo in
            let starIndex = Double(index) + 1.0
            let fillAmount: Double = {
                if currentRating >= starIndex { return 1.0 }
                if currentRating + 0.5 >= starIndex { return 0.5 }
                return 0.0
            }()
            
            ZStack {
                Image(systemName: "star")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.orange.opacity(0.35))
                
                if fillAmount >= 1.0 {
                    Image(systemName: "star.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.orange)
                } else if fillAmount >= 0.5 {
                    if UIImage(systemName: "star.leadinghalf.filled") != nil {
                        Image(systemName: "star.leadinghalf.filled")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "star.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.orange)
                            .mask(
                                Rectangle()
                                    .frame(width: geo.size.width / 2, height: geo.size.height)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let localX = max(0, min(value.location.x, geo.size.width))
                        let half = localX < geo.size.width / 2 ? 0.5 : 1.0
                        let newRating = Double(index) + half
                        onChange(newRating)
                    }
                    .onEnded { value in
                        let localX = max(0, min(value.location.x, geo.size.width))
                        let half = localX < geo.size.width / 2 ? 0.5 : 1.0
                        let newRating = Double(index) + half
                        onChange(newRating)
                    }
            )
        }
        .frame(width: 34, height: 34)
    }
}

#Preview {
    @State var rating: Double? = 4.0
    @State var reviewText = ""
    
    return BookReviewSheet(
        title: "How did you like this book?",
        subtitle: "Rate and review this book to help other readers discover great books!",
        rating: $rating,
        reviewText: $reviewText,
        onSkip: { },
        onConfirm: { }
    )
}