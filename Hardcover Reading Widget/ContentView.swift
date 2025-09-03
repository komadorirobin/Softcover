//
//  Hardcover_Reading_WidgetApp.swift
//  Hardcover Reading Widget
//
//  Created by Robin Bolinsson on 2025-08-22.
//

import SwiftUI
import WidgetKit
import UIKit

struct ContentView: View {
    @State private var books: [BookProgress] = []
    @State private var isLoading = true
    @State private var lastUpdated = Date()
    @State private var errorMessage: String?
    @State private var selectedBookForEdition: BookProgress?
    @State private var showingApiSettings = false
    @State private var username: String = ""
    @State private var showGlobalConfetti = false
    @State private var showingSearch = false
    @State private var showingStats = false
    // NEW: history sheet
    @State private var showingHistory = false
    // NEW: finish banner
    @State private var showFinishBanner = false
    
    var body: some View {
        ZStack {
            // Add system background color that adapts to dark mode
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !username.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "person.circle")
                                    .foregroundColor(.secondary)
                                Text("Signed in as @\(username)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                        
                        // NEW: Success banner
                        if showFinishBanner {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text("Marked as finished")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(10)
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        if isLoading && books.isEmpty {
                            VStack(spacing: 20) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Loading your books...")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                        } else if let error = errorMessage {
                            VStack(spacing: 20) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 50))
                                    .foregroundColor(.orange)
                                Text("Failed to load books")
                                    .font(.headline)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Try Again") {
                                    Task { await loadBooks() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                            .padding(.horizontal)
                        } else if books.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "books.vertical")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)
                                Text("No books currently reading")
                                    .font(.headline)
                                Text("Start reading a book on Hardcover to see it here")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                            .padding(.horizontal)
                        } else {
                            ForEach(books) { book in
                                BookCardView(book: book, onEditionTap: {
                                    selectedBookForEdition = book
                                }, onProgressSaved: {
                                    Task {
                                        await loadBooks()
                                        WidgetCenter.shared.reloadAllTimelines()
                                    }
                                }, onCelebrate: {
                                    triggerConfetti()
                                }, onFinished: {
                                    // Show banner and confetti when a book is marked as finished
                                    showFinishFeedback()
                                })
                            }
                        }
                        
                        if !books.isEmpty && !isLoading {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption)
                                Text("Updated \(lastUpdated, style: .relative) ago")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }
                    }
                    .padding()
                }
                .background(Color(UIColor.systemBackground))
                .navigationTitle("Currently Reading")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { showingApiSettings = true } label: { Image(systemName: "gearshape") }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            // NEW: History button
                            Button(action: { showingHistory = true }) {
                                Image(systemName: "clock")
                            }
                            Button(action: { showingStats = true }) {
                                Image(systemName: "chart.bar")
                            }
                            Button(action: { showingSearch = true }) {
                                Image(systemName: "plus")
                            }
                            Button(action: { Task { await loadBooks() } }) {
                                Image(systemName: "arrow.clockwise")
                                    .rotationEffect(.degrees(isLoading ? 360 : 0))
                                    .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
                            }
                            .disabled(isLoading)
                        }
                    }
                    // Keyboard toolbar lives on the NavigationView for reliability
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { hideKeyboard() }
                    }
                }
                .refreshable { await refreshBooks() }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .task {
                await loadBooks()
                loadUsernameFromDefaults()
            }
            .sheet(item: $selectedBookForEdition) { book in
                EditionPickerView(book: book) { success in
                    if success {
                        Task {
                            await loadBooks()
                            WidgetCenter.shared.reloadAllTimelines()
                            print("✅ Widget timelines reloaded.")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingApiSettings) {
                ApiKeySettingsView { _ in
                    Task {
                        await loadBooks()
                        WidgetCenter.shared.reloadAllTimelines()
                        loadUsernameFromDefaults()
                    }
                }
            }
            .sheet(isPresented: $showingSearch) {
                SearchBooksView { didAdd in
                    if didAdd {
                        Task {
                            await loadBooks()
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingStats) {
                StatsView()
            }
            // NEW: History sheet
            .sheet(isPresented: $showingHistory) {
                HistoryView()
            }
            
            if showGlobalConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }
    
    private func hideKeyboard() {
#if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }
    
    private func triggerConfetti() {
        withAnimation(.easeIn(duration: 0.15)) { showGlobalConfetti = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.25)) { showGlobalConfetti = false }
        }
    }
    
    private func showFinishFeedback() {
        // Haptics + banner + confetti
#if os(iOS) && !targetEnvironment(macCatalyst)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            showFinishBanner = true
        }
        // Also trigger global confetti
        triggerConfetti()
        // Auto-hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.25)) {
                showFinishBanner = false
            }
        }
    }
    
    private func loadUsernameFromDefaults() {
        username = AppGroup.defaults.string(forKey: "HardcoverUsername") ?? ""
    }
    
    private func loadBooks() async {
        isLoading = true
        errorMessage = nil
        let fetchedBooks = await HardcoverService.fetchCurrentlyReading()
        await MainActor.run {
            self.books = fetchedBooks
            self.lastUpdated = Date()
            self.isLoading = false
            if fetchedBooks.isEmpty { errorMessage = nil }
            WidgetCenter.shared.reloadAllTimelines()
            print("✅ Widget timelines reloaded after manual refresh.")
            loadUsernameFromDefaults()
        }
    }
    
    private func refreshBooks() async {
        let fetchedBooks = await HardcoverService.fetchCurrentlyReading()
        await MainActor.run {
            self.books = fetchedBooks
            self.lastUpdated = Date()
            WidgetCenter.shared.reloadAllTimelines()
            print("✅ Widget timelines reloaded after pull-to-refresh.")
            loadUsernameFromDefaults()
        }
    }
}

struct BookCardView: View {
    let book: BookProgress
    let onEditionTap: () -> Void
    let onProgressSaved: () -> Void
    let onCelebrate: () -> Void
    // NEW: notify parent when finished
    let onFinished: () -> Void
    @State private var isExpanded = false
    @State private var editedPage: Int
    @State private var isUpdating = false
    @State private var showUpdateError = false
    @State private var isActionWorking = false
    @State private var showRemoveConfirm = false
    @State private var showActionError = false
    @FocusState private var pageFieldFocused: Bool
    @State private var isManualEditing = false
    
    // Rating flow
    @State private var showRatingSheet = false
    @State private var pendingFinishUserBookId: Int?
    @State private var selectedRating: Double? = 5.0 // default suggestion
    
    init(book: BookProgress, onEditionTap: @escaping () -> Void, onProgressSaved: @escaping () -> Void, onCelebrate: @escaping () -> Void, onFinished: @escaping () -> Void) {
        self.book = book
        self.onEditionTap = onEditionTap
        self.onProgressSaved = onProgressSaved
        self.onCelebrate = onCelebrate
        self.onFinished = onFinished
        _editedPage = State(initialValue: book.currentPage)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                if let imageData = book.coverImageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 120)
                        .clipped()
                        .cornerRadius(8)
                        .shadow(radius: 4)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [Color("CardBackground").opacity(0.6), Color("CardBackground").opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 120)
                        .overlay(Image(systemName: "book.closed").font(.largeTitle).foregroundColor(.secondary))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if book.bookId != nil && book.userBookId != nil {
                        Button(action: {
                            print("🔘 Change Edition tapped - BookId: \(book.bookId!), UserBookId: \(book.userBookId!), Current EditionId: \(book.editionId ?? -1)")
                            onEditionTap()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "books.vertical.fill").font(.caption)
                                Text("Change Edition").font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Spacer()
                    
                    if book.totalPages > 0 || book.currentPage > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                if book.currentPage > 0 && book.totalPages > 0 {
                                    Text("Page \(book.currentPage) of \(book.totalPages) pages")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if book.currentPage > 0 {
                                    Text("Page \(book.currentPage)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if book.totalPages > 0 {
                                    Text("\(book.totalPages) pages")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if book.progress > 0 {
                                    Text("\(Int(book.progress * 100))%")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4).fill(Color("BorderColor").opacity(0.3))
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: CGFloat(book.progress) * geometry.size.width)
                                }
                            }
                            .frame(height: 8)
                        }
                    } else {
                        Text("No progress information")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if book.userBookId != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            // Stepper with tappable label for manual input
                            HStack(spacing: 8) {
                                Stepper(value: $editedPage, in: 0...(book.totalPages > 0 ? book.totalPages : max(editedPage, 0) + 10000)) {
                                    if isManualEditing {
                                        HStack(spacing: 6) {
                                            TextField("Page", value: $editedPage, format: .number)
                                                .keyboardType(.numberPad)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(minWidth: 70, maxWidth: 100)
                                                .focused($pageFieldFocused)
                                                .onSubmit { isManualEditing = false }
#if targetEnvironment(macCatalyst)
                                            Button("Done") {
                                                isManualEditing = false
                                                pageFieldFocused = false
                                            }
                                            .buttonStyle(.bordered)
#endif
                                        }
                                    } else {
                                        Button {
                                            isManualEditing = true
                                            pageFieldFocused = true
                                        } label: {
                                            Text("Page \(editedPage)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .disabled(isUpdating)
                                if isUpdating {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Button("Update") { Task { await updateProgress() } }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(editedPage < 0 || (book.totalPages > 0 && editedPage > book.totalPages) || editedPage == book.currentPage)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    if book.title != book.originalTitle {
                        HStack {
                            Label("Original title", systemImage: "text.book.closed").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(book.originalTitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    HStack {
                        Label("Book ID", systemImage: "number").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(book.bookId != nil ? "\(book.bookId!)" : "N/A").font(.caption).foregroundColor(.secondary)
                    }
                    if book.progress > 0 && book.totalPages > 0 {
                        let remainingPages = book.totalPages - book.currentPage
                        HStack {
                            Label("Pages left", systemImage: "book").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text("\(remainingPages)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .contextMenu {
            if let userBookId = book.userBookId {
                Button {
                    pendingFinishUserBookId = userBookId
                    selectedRating = 5.0
                    showRatingSheet = true
                } label: {
                    Label("Mark as finished", systemImage: "checkmark.circle")
                }
                Button(role: .destructive) {
                    showRemoveConfirm = true
                } label: {
                    Label("Remove from Currently Reading", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Remove from Currently Reading?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let userBookId = book.userBookId {
                    Task { await removeCurrentlyReading(userBookId: userBookId) }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Action failed", isPresented: $showActionError) {
            Button("OK") { }
        } message: { Text("Please try again.") }
        .alert("Failed to update page", isPresented: $showUpdateError) {
            Button("OK") { }
        } message: { Text("Please try again.") }
        .onChange(of: editedPage) { _, newValue in
            // Clamp sensibly: never negative; cap to totalPages if known
            if newValue < 0 { editedPage = 0 }
            if book.totalPages > 0 && newValue > book.totalPages { editedPage = book.totalPages }
        }
        // NEW: sync editedPage forward when fetched data advances currentPage
        .onChange(of: book.currentPage) { _, newValue in
            if editedPage < newValue {
                editedPage = newValue
            }
        }
        // NEW: reclamp if totalPages changes from server
        .onChange(of: book.totalPages) { _, newTotal in
            if newTotal > 0 && editedPage > newTotal {
                editedPage = newTotal
            }
        }
        // Exit manual mode when keyboard hides (e.g., global Done tapped)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            if isManualEditing { isManualEditing = false }
        }
        .sheet(isPresented: $showRatingSheet) {
            RatingSheet(
                title: "Rate the book?",
                subtitle: "You can leave a rating when marking as finished. This is optional.",
                rating: $selectedRating,
                onSkip: {
                    print("ℹ️ RatingSheet: Skip tapped, sending rating=nil")
                    showRatingSheet = false
                    if let userBookId = pendingFinishUserBookId {
                        Task { await markAsFinished(userBookId: userBookId, rating: nil) }
                    }
                },
                onConfirm: {
                    // Defensive: always ensure a valid 0.5...5.0 value
                    let raw = selectedRating ?? 5.0
                    let clamped = max(0.5, min(5.0, (round(raw * 2) / 2)))
                    print("✅ RatingSheet: Confirm tapped, sending rating=\(clamped)")
                    showRatingSheet = false
                    if let userBookId = pendingFinishUserBookId {
                        Task { await markAsFinished(userBookId: userBookId, rating: clamped) }
                    }
                }
            )
            .presentationDetents([.height(300), .medium])
        }
    }
    
    private func updateProgress() async {
        guard let userBookId = book.userBookId else { return }
        let increased = editedPage > book.currentPage
        isUpdating = true
        let success = await HardcoverService.updateProgress(userBookId: userBookId, editionId: book.editionId, page: editedPage)
        await MainActor.run {
            isUpdating = false
            if success {
                if increased {
#if os(iOS) && !targetEnvironment(macCatalyst)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
                    onCelebrate()
                }
                onProgressSaved()
            } else {
                showUpdateError = true
            }
        }
    }
    
    private func markAsFinished(userBookId: Int, rating: Double?) async {
        guard !isActionWorking else { return }
        isActionWorking = true
        print("📗 BookCardView.markAsFinished: userBookId=\(userBookId), rating=\(String(describing: rating))")
        let ok = await HardcoverService.finishBook(
            userBookId: userBookId,
            editionId: book.editionId,
            totalPages: book.totalPages > 0 ? book.totalPages : nil,
            currentPage: book.currentPage > 0 ? book.currentPage : nil,
            rating: rating
        )
        await MainActor.run {
            isActionWorking = false
            if ok {
                // Haptics for success
#if os(iOS) && !targetEnvironment(macCatalyst)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
                // Notify parent to show banner & confetti and refresh
                onFinished()
                onProgressSaved()
            } else {
                showActionError = true
            }
        }
    }
    
    private func removeCurrentlyReading(userBookId: Int) async {
        guard !isActionWorking else { return }
        isActionWorking = true
        let ok = await HardcoverService.deleteUserBook(userBookId: userBookId)
        await MainActor.run {
            isActionWorking = false
            if ok { onProgressSaved() } else { showActionError = true }
        }
    }
}

// Full-screen confetti using CAEmitterLayer
private struct ConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> ConfettiContainerView {
        ConfettiContainerView()
    }
    func updateUIView(_ uiView: ConfettiContainerView, context: Context) {}
}

private final class ConfettiContainerView: UIView {
    private let emitter = CAEmitterLayer()
    private let colors: [UIColor] = [
        .systemPink, .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemYellow
    ]
    
    private enum ParticleShape: CaseIterable { case rectangle, circle, triangle }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        setup()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.emitterPosition = CGPoint(x: bounds.width / 2, y: -4)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
    }
    
    private func setup() {
        emitter.emitterShape = .line
        emitter.emitterMode = .surface
        emitter.renderMode = .oldestLast
        emitter.emitterPosition = CGPoint(x: bounds.width / 2, y: -4)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        emitter.emitterCells = makeCells()
        layer.addSublayer(emitter)
    }
    
    private func makeCells() -> [CAEmitterCell] {
        var cells: [CAEmitterCell] = []
        for color in colors {
            for shape in ParticleShape.allCases {
                let cell = CAEmitterCell()
                cell.birthRate = 3
                cell.lifetime = 4.0
                cell.lifetimeRange = 1.0
                cell.emissionLongitude = .pi / 2
                cell.emissionRange = 0.12
                cell.velocity = 200
                cell.velocityRange = 80
                cell.xAcceleration = 0
                cell.yAcceleration = 300
                cell.spin = 1.6
                cell.spinRange = 3.2
                cell.scale = 0.6
                cell.scaleRange = 0.3
                cell.scaleSpeed = -0.05
                cell.alphaRange = 0.2
                cell.alphaSpeed = -0.3
                cell.contents = makeConfettiImage(color: color, shape: shape).cgImage
                cells.append(cell)
            }
        }
        return cells
    }
    
    private func makeConfettiImage(color: UIColor, shape: ParticleShape) -> UIImage {
        let size: CGSize
        switch shape {
        case .rectangle: size = CGSize(width: 10, height: 14)
        case .circle: size = CGSize(width: 10, height: 10)
        case .triangle: size = CGSize(width: 12, height: 12)
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            color.setFill()
            switch shape {
            case .rectangle:
                let rectPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2)
                rectPath.fill()
            case .circle:
                let oval = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
                oval.fill()
            case .triangle:
                let path = UIBezierPath()
                path.move(to: CGPoint(x: size.width/2, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.close()
                path.fill()
            }
        }
    }
}

struct EditionPickerView: View {
    @StateObject private var viewModel: EditionPickerViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(book: BookProgress, onComplete: @escaping (Bool) -> Void) {
        _viewModel = StateObject(wrappedValue: EditionPickerViewModel(book: book, onComplete: onComplete))
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { dismiss() }.disabled(viewModel.isSaving)
                    Spacer()
                    Text("Select Edition").font(.headline)
                    Spacer()
                    if viewModel.isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Save") { Task { await viewModel.saveEdition(dismiss: { dismiss() }) } }
                            .disabled(viewModel.selectedEditionId == nil || viewModel.selectedEditionId == viewModel.book.editionId)
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                Divider()
                Group {
                    if viewModel.isLoading { loadingView }
                    else if viewModel.editions.isEmpty { emptyView }
                    else { contentView }
                }
            }
        }
        .task { await viewModel.loadEditions() }
        .alert("Error", isPresented: $viewModel.showError) { Button("OK") { } } message: { Text(viewModel.errorMessage) }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5)
            Text("Loading editions...").font(.headline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical.circle").font(.system(size: 60)).foregroundColor(.secondary)
            Text("No editions found").font(.headline)
            Text("This book might only have one edition").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.editions) { edition in
                    EditionRow(
                        edition: edition,
                        isSelected: viewModel.selectedEditionId == edition.id,
                        isCurrent: viewModel.book.editionId == edition.id
                    ) { viewModel.selectedEditionId = edition.id }
                }
            }
            .padding()
        }
    }
}

#Preview { ContentView() }

private struct RatingSheet: View {
    let title: String
    let subtitle: String
    @Binding var rating: Double?
    let onSkip: () -> Void
    let onConfirm: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 38, height: 5)
                .padding(.top, 8)
            
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            StarRatingView(rating: Binding(
                get: { rating ?? 0 },
                set: { rating = $0 }
            ))
            .padding(.horizontal)
            
            // Extra precise input and accessibility
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
            .padding(.horizontal)
            
            HStack {
                Button("Skip") {
                    onSkip()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Confirm") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled((rating ?? 0) < 0.5)
            }
            .padding(.horizontal)
            
            Spacer(minLength: 8)
        }
        .presentationDragIndicator(.visible)
    }
}

private struct StarRatingView: View {
    @Binding var rating: Double // 0.0–5.0, 0.5 steps
    
    private let maxRating: Double = 5.0
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                StarCell(
                    index: index,
                    currentRating: rating,
                    onChange: { newValue in
                        // Snap to 0.5 steps
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
            case .increment:
                rating = min(maxRating, rating + step)
            case .decrement:
                rating = max(0, rating - step)
            @unknown default:
                break
            }
        }
    }
}

private struct StarCell: View {
    let index: Int
    let currentRating: Double
    let onChange: (Double) -> Void
    
    @State private var width: CGFloat = 0
    
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
                    // Prefer the dedicated SF Symbol for a left half-filled star.
                    // If for any reason it isn't available, fall back to a left-anchored mask.
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
                                    .frame(maxWidth: .infinity, alignment: .leading) // ensure left-anchored mask
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
            .onAppear {
                width = geo.size.width
            }
        }
        .frame(width: 34, height: 34) // touch-friendly
    }
}

