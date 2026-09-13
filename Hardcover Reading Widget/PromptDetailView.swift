import SwiftUI

struct PromptDetailView: View {
    let promptAnswer: PromptAnswer
    @State private var answers: [UserPromptAnswer] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var generation = UUID()
    @State private var retryTask: Task<Void, Never>?
    
    var body: some View {
        Group {
            if isLoading && answers.isEmpty {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading answers...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, answers.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Failed to load answers")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        retryTask?.cancel()
                        retryTask = Task { await loadAnswers() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Prompt header
                        VStack(alignment: .leading, spacing: 12) {
                            Text(promptAnswer.prompt.question ?? promptAnswer.prompt.slug.replacingOccurrences(of: "-", with: " ").capitalized)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            if let description = promptAnswer.prompt.description, !description.isEmpty {
                                Text(description)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        
                        Divider()
                        
                        // Answers
                        if answers.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)
                                Text("No answers yet")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(answers) { answer in
                                    PromptAnswerDetailCard(answer: answer)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .navigationTitle("Prompt Answers")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAnswers()
        }
        .refreshable { await loadAnswers() }
        .safeAreaInset(edge: .top) {
            if let errorMessage, !answers.isEmpty {
                InlineLoadError(message: errorMessage) {
                    retryTask?.cancel()
                    retryTask = Task { await loadAnswers() }
                }.padding().background(.regularMaterial)
            }
        }
        .onDisappear {
            retryTask?.cancel(); generation = UUID(); isLoading = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .hardcoverAccountDidChange)) { _ in
            retryTask?.cancel(); generation = UUID(); answers = []; errorMessage = nil
            retryTask = Task { await loadAnswers() }
        }
    }
    
    @MainActor private func loadAnswers() async {
        let request = UUID()
        let account = HardcoverConfig.authorizationHeaderValue
        generation = request
        isLoading = true; errorMessage = nil
        defer { if generation == request { isLoading = false } }
        do {
            try Task.checkCancellation()
            let username = try await HardcoverReadScope.checked {
                await HardcoverService.fetchUsername(forUserId: promptAnswer.userId)
            }
            try Task.checkCancellation()
            guard generation == request, account == HardcoverConfig.authorizationHeaderValue else { return }
            guard let username, !username.isEmpty else { throw HardcoverNetworkError.invalidResponse }
            let fetched = try await HardcoverReadScope.checked {
                await HardcoverService.fetchPromptAnswers(promptId: promptAnswer.prompt.id, userId: promptAnswer.userId,
                                                         username: username, slug: promptAnswer.prompt.slug)
            }
            try Task.checkCancellation()
            guard generation == request, account == HardcoverConfig.authorizationHeaderValue else { return }
            answers = fetched
        } catch {
            guard !Task.isCancelled, generation == request, account == HardcoverConfig.authorizationHeaderValue else { return }
            errorMessage = error.localizedDescription
        }
    }
}

struct PromptAnswerDetailCard: View {
    let answer: UserPromptAnswer
    @State private var selectedBook: PromptBook? = nil
    @State private var showDescription = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User info
            HStack {
                if let imageUrl = answer.user.image?.url, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 40, height: 40)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        case .failure:
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.gray)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                        )
                }
                
                Text("@\(answer.user.username)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
            }
            
            // Books
            if !answer.books.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(answer.books) { book in
                            VStack(alignment: .leading, spacing: 8) {
                                // Book cover - clickable to navigate to book detail
                                NavigationLink(destination: BookDetailView(
                                    book: BookProgress(
                                        id: "\(book.id)",
                                        title: book.title,
                                        author: "Unknown Author",
                                        coverImageData: nil,
                                        coverImageUrl: book.cachedImage?.url ?? book.image,
                                        progress: 0.0,
                                        totalPages: 0,
                                        currentPage: 0,
                                        bookId: book.id,
                                        userBookId: nil,
                                        editionId: nil,
                                        originalTitle: book.title,
                                        editionAverageRating: nil,
                                        userRating: nil,
                                        bookDescription: nil
                                    ),
                                    showFinishAction: false,
                                    allowStandaloneReviewButton: true,
                                    isOwnBook: false
                                )) {
                                    if let imageUrl = book.cachedImage?.url ?? book.image,
                                       let url = URL(string: imageUrl) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .empty:
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.2))
                                                    .frame(width: 120, height: 180)
                                                    .overlay(ProgressView())
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 120, height: 180)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            case .failure:
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.2))
                                                    .frame(width: 120, height: 180)
                                                    .overlay(
                                                        Image(systemName: "book.fill")
                                                            .foregroundColor(.gray)
                                                    )
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            @unknown default:
                                                EmptyView()
                                            }
                                        }
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 120, height: 180)
                                            .overlay(
                                                Image(systemName: "book.fill")
                                                    .foregroundColor(.gray)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                                
                                Text(book.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(2)
                                    .frame(width: 120)
                                    .foregroundColor(.primary)
                                
                                // Show description preview and info button
                                if let description = book.description, !description.isEmpty {
                                    HStack(alignment: .top, spacing: 4) {
                                        Text(description)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(3)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        Button(action: {
                                            selectedBook = book
                                            showDescription = true
                                        }) {
                                            Image(systemName: "info.circle")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .frame(width: 120)
                                }
                            }
                            .frame(width: 120)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showDescription) {
            if let book = selectedBook {
                BookDescriptionSheet(book: book)
            }
        }
    }
}

// New view for showing full description
struct BookDescriptionSheet: View {
    let book: PromptBook
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Book cover and title
                    HStack(alignment: .top, spacing: 16) {
                        if let imageUrl = book.cachedImage?.url ?? book.image,
                           let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                case .empty:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 80, height: 120)
                                        .overlay(ProgressView())
                                case .failure:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 80, height: 120)
                                        .overlay(
                                            Image(systemName: "book.fill")
                                                .foregroundColor(.gray)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    Divider()
                    
                    // Full description
                    if let description = book.description {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Why this book?")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Text(description)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Book Answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PromptDetailView(promptAnswer: PromptAnswer(
            id: 1,
            createdAt: "2025-09-25T09:09:04.766927+00:00",
            promptId: 1,
            userId: 35696,
            prompt: Prompt(
                id: 1,
                slug: "what-are-your-favorite-books-of-all-time",
                question: "What are your favorite books of all time?",
                description: "When you think back on every book you've ever read, what are some of your favorites?"
            )
        ))
    }
}
