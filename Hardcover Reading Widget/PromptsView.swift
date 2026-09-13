import SwiftUI

struct PromptsView: View {
    let username: String? // nil means current user
    @State private var prompts: [PromptAnswer] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var generation = UUID()
    @State private var retryTask: Task<Void, Never>?
    
    init(username: String? = nil) {
        self.username = username
    }
    
    var body: some View {
        Group {
            if isLoading && prompts.isEmpty {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(NSLocalizedString("Loading prompts...", comment: "Message while loading prompts"))
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, prompts.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("Failed to load prompts", comment: "Error message when prompts fail to load"))
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        retryTask?.cancel()
                        retryTask = Task { await loadPrompts() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if prompts.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "questionmark.bubble")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("No answered prompts", comment: "Message when user has no answered prompts"))
                        .font(.headline)
                    Text(NSLocalizedString("Answer prompts on Hardcover to see them here", comment: "Empty state message for prompts view"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(prompts) { promptAnswer in
                            NavigationLink {
                                PromptDetailView(promptAnswer: promptAnswer)
                            } label: {
                                PromptAnswerCard(promptAnswer: promptAnswer)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(NSLocalizedString("Answered Prompts", comment: "Title for answered prompts view"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadPrompts()
        }
        .refreshable { await loadPrompts() }
        .safeAreaInset(edge: .top) {
            if let errorMessage, !prompts.isEmpty {
                InlineLoadError(message: errorMessage) {
                    retryTask?.cancel()
                    retryTask = Task { await loadPrompts() }
                }.padding().background(.regularMaterial)
            }
        }
        .onDisappear {
            retryTask?.cancel(); generation = UUID(); isLoading = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .hardcoverAccountDidChange)) { _ in
            retryTask?.cancel(); generation = UUID(); prompts = []; errorMessage = nil
            retryTask = Task { await loadPrompts() }
        }
    }
    
    @MainActor private func loadPrompts() async {
        let request = UUID()
        let account = HardcoverConfig.authorizationHeaderValue
        generation = request
        isLoading = true; errorMessage = nil
        defer { if generation == request { isLoading = false } }

        let received: @MainActor (PromptAnswer) -> Void = { answer in
            guard !Task.isCancelled, generation == request, account == HardcoverConfig.authorizationHeaderValue else { return }
            if let index = prompts.firstIndex(where: { $0.id == answer.id }) { prompts[index] = answer }
            else { prompts.append(answer) }
        }
        do {
            try Task.checkCancellation()
            let fetched = try await HardcoverReadScope.checked {
                if let username {
                    return await HardcoverService.fetchAnsweredPrompts(forUsername: username, onPromptLoaded: received)
                }
                return await HardcoverService.fetchAnsweredPrompts(onPromptLoaded: received)
            }
            try Task.checkCancellation()
            guard generation == request, account == HardcoverConfig.authorizationHeaderValue else { return }
            prompts = fetched
        } catch {
            guard !Task.isCancelled, generation == request, account == HardcoverConfig.authorizationHeaderValue else { return }
            errorMessage = error.localizedDescription
        }
    }
}

struct PromptAnswerCard: View {
    let promptAnswer: PromptAnswer
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
    
    private var date: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: promptAnswer.createdAt)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Prompt Title - use question if available, otherwise slug
            Text(promptAnswer.prompt.question ?? promptAnswer.prompt.slug.replacingOccurrences(of: "-", with: " ").capitalized)
                .font(.headline)
                .foregroundColor(.primary)
            
            // Prompt Description
            if let description = promptAnswer.prompt.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            
            // Book Preview (first 3 books)
            if let books = promptAnswer.previewBooks, !books.isEmpty {
                HStack(spacing: -20) {
                    ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                        if let imageUrl = book.cachedImage?.url ?? book.image,
                           let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 90)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color(UIColor.secondarySystemGroupedBackground), lineWidth: 2)
                                        )
                                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                        .zIndex(Double(books.count - index))
                                case .failure, .empty:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 60, height: 90)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .zIndex(Double(books.count - index))
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            // Date
            if let date = date {
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(dateFormatter.string(from: date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        PromptsView()
    }
}
