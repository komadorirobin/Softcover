import SwiftUI
import UIKit

struct BookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var book: BookProgress
    let showFinishAction: Bool
    let allowStandaloneReviewButton: Bool
    let isOwnBook: Bool
    var onLibraryChange: ((BookProgress?) -> Void)?
    var onAddToWantToRead: ((Int?) -> Void)?
    @StateObject private var store: BookDetailStore
    @ObservedObject private var activity = ReadingActivityStore.shared
    @ObservedObject private var ownedEditions = OwnedEditionsStore.shared
    @AppStorage("HardcoverAuthRevision", store: AppGroup.defaults) private var authRevision = ""
    @AppStorage("SkipEditionPickerOnAdd", store: AppGroup.defaults) private var skipEditionPicker = false
    @State private var working = false
    @State private var actionError: String?
    @State private var progressBook: BookProgress?
    @State private var editionBook: BookProgress?
    @State private var datesBook: BookProgress?
    @State private var sessionBook: BookProgress?
    @State private var deadlineBook: BookProgress?
    @State private var reviewBook: BookProgress?
    @State private var finishing = false
    @State private var showQuotes = false
    @State var highlightQuoteId: Int? = nil
    @State private var showRemoveConfirmation = false
    @State private var pendingStatus: Int?
    @State private var editions: [Edition] = []
    @State private var showEditionSelection = false
    @State private var completedBook = false
    @State private var showShareCard = false
    @State private var showTags = false

    init(book: BookProgress, showFinishAction: Bool = true, allowStandaloneReviewButton: Bool = true,
         isOwnBook: Bool = true, onLibraryChange: ((BookProgress?) -> Void)? = nil,
         onAddToWantToRead: ((Int?) -> Void)? = nil) {
        _book = State(initialValue: book)
        _store = StateObject(wrappedValue: BookDetailStore(bookID: book.bookId))
        self.showFinishAction = showFinishAction
        self.allowStandaloneReviewButton = allowStandaloneReviewButton
        self.isOwnBook = isOwnBook
        self.onLibraryChange = onLibraryChange
        self.onAddToWantToRead = onAddToWantToRead
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                if let error = store.error {
                    InlineLoadError(message: error) { Task { await store.load(fresh: true) } }
                }
                editionSection
                Divider()
                readingSection
                descriptionSection
                quotesSection
                reviewsSection
                technicalDetails
            }
            .padding()
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Book Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Share book card", systemImage: "square.and.arrow.up") { showShareCard = true }
                    if book.bookId != nil {
                        Button("Edit tags", systemImage: "tag") { showTags = true }
                    }
                    if let editionID = store.ownBook?.editionId ?? book.editionId {
                        Button(ownedEditions.entry(editionID: editionID) == nil ? "Mark edition as owned" : "Unmark edition as owned",
                               systemImage: ownedEditions.entry(editionID: editionID) == nil ? "books.vertical" : "books.vertical.fill") {
                            Task { await toggleOwned(editionID: editionID) }
                        }.disabled(working)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                }
                .accessibilityLabel("More book actions")
            }
        }
        .catalogEditing(book: $book) { _ in Task { await store.load(fresh: true) } }
        .task(id: authRevision) {
            activity.reload()
            async let detailLoad: Void = store.load()
            async let ownedLoad: Void = ownedEditions.load()
            _ = await (detailLoad, ownedLoad)
            if highlightQuoteId != nil { showQuotes = true }
        }
        .onChange(of: authRevision) { _, _ in
            progressBook = nil
            editionBook = nil
            datesBook = nil
            sessionBook = nil
            deadlineBook = nil
            reviewBook = nil
            showQuotes = false
            showEditionSelection = false
            pendingStatus = nil
        }
        .onChange(of: store.ownBook) { _, own in
            if isOwnBook, let own { mergeOwnBook(own) }
        }
        .onChange(of: store.metadata) { _, metadata in
            guard let metadata else { return }
            book.bookDescription = metadata.description
            book.editionAverageRating = metadata.rating
            if book.userBookId == nil {
                if !metadata.title.isEmpty { book.title = metadata.title; book.originalTitle = metadata.title }
                if !metadata.author.isEmpty { book.author = metadata.author }
                book.coverImageUrl = book.coverImageUrl ?? metadata.coverURL
                book.releaseDate = book.releaseDate ?? metadata.releaseDate
                book.parsedReleaseDate = ReleaseDate.parse(book.releaseDate)
            }
        }
        .sheet(item: $progressBook) { own in
            ReadingProgressEditor(book: own) { updated in
                store.apply(updated)
                if isOwnBook { mergeOwnBook(updated) }
                onLibraryChange?(updated)
            }
        }
        .sheet(item: $editionBook) { own in
            EditionSelectionLoader(book: own) { updated in libraryChanged(updated) }
        }
        .sheet(item: $datesBook, onDismiss: { Task { await store.refreshOwnBook() } }) { own in
            if let userBookID = own.userBookId {
                ReadingDatesView(userBookId: userBookID, editionId: own.editionId)
            }
        }
        .sheet(item: $sessionBook) { own in
            ReadingSessionView(book: own) { updated in libraryChanged(updated) }
        }
        .sheet(item: $deadlineBook) { own in
            ReadingDeadlineView(book: own)
        }
        .sheet(item: $reviewBook) { own in
            FinishRateReviewSheet(book: own, markFinished: finishing) { updated in
                libraryChanged(updated)
                if finishing {
                    completedBook = true
                    if !reduceMotion { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
                Task { await store.loadReviews(fresh: true) }
            }
        }
        .sheet(isPresented: $showQuotes, onDismiss: { Task { await store.loadQuotes(fresh: true) } }) {
            if let id = book.bookId {
                BookQuotesView(bookId: id, bookTitle: book.title,
                    editionId: store.ownBook?.editionId ?? book.editionId,
                    totalPages: store.ownBook?.totalPages, highlightQuoteId: highlightQuoteId)
            }
        }
        .sheet(isPresented: $showEditionSelection, onDismiss: { pendingStatus = nil }) {
            EditionSelectionSheet(bookTitle: book.title, currentEditionId: nil, editions: editions,
                onCancel: { pendingStatus = nil }, onSave: { id in
                    guard let status = pendingStatus else { return }
                    pendingStatus = nil
                    Task { await changeStatus(status, editionID: id) }
                })
        }
        .sheet(isPresented: $showShareCard) {
            BookShareView(book: book, metadata: store.metadata)
        }
        .sheet(isPresented: $showTags) {
            if let id = book.bookId { BookTagsView(bookID: id) }
        }
        .confirmationDialog("Remove book?", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove from library", role: .destructive) { Task { await removeBook() } }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                BookCover(book: book)
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                    if book.originalTitle != book.title, !book.originalTitle.isEmpty {
                        Text("Original title: \(book.originalTitle)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let rating = store.metadata?.rating ?? book.editionAverageRating {
                        Label { Text("Average \(rating, specifier: "%.1f")") } icon: {
                            Image(systemName: "star.fill").foregroundStyle(.orange)
                        }.font(.subheadline)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let metadata = store.metadata {
                if !metadata.genres.isEmpty { WrapChipsView(items: metadata.genres) }
                if !metadata.moods.isEmpty { WrapChipsView(items: metadata.moods) }
            }
        }
    }

    private var editionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Edition").font(.headline)
                Spacer()
                if let own = store.ownBook, isOwnBook || own.editionId == book.editionId {
                    Button { Task { await openPersonalSheet(.edition) } } label: {
                        Image(systemName: "books.vertical").frame(width: 44, height: 44)
                    }.accessibilityLabel("Change Edition").help("Change Edition").disabled(working)
                }
            }
            Text(book.displayFormat).font(.subheadline)
            if book.totalUnits > 0 {
                if book.isAudiobook { Text(BookProgressPresentation.duration(book.totalUnits)).foregroundStyle(.secondary) }
                else { Text("\(book.totalUnits) pages").foregroundStyle(.secondary) }
            }
            if let date = book.parsedReleaseDate ?? ReleaseDate.parse(book.releaseDate) {
                LabeledContent("Release Date") { Text(date, format: .dateTime.year().month().day()) }.font(.subheadline)
            }
        }
    }

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your reading").font(.headline)
                Spacer()
                if working { ProgressView().controlSize(.small) }
                if store.ownBook != nil {
                    Menu {
                        Button("Dates Read", systemImage: "calendar") { Task { await openPersonalSheet(.dates) } }
                        if let own = store.ownBook, own.statusId == 2 {
                            Button("Reading session", systemImage: "timer") { sessionBook = own }
                            Button("Reading deadline", systemImage: "calendar.badge.clock") { deadlineBook = own }
                        }
                        if store.ownBook?.statusId != 1 {
                            Button("Want to Read", systemImage: "bookmark") { Task { await prepareStatus(1) } }
                        }
                        if store.ownBook?.statusId != 2 {
                            Button("Start Reading", systemImage: "book") { Task { await prepareStatus(2) } }
                        }
                        if store.ownBook?.statusId != 3 {
                            Button("Mark as finished", systemImage: "checkmark.circle") { Task { await prepareStatus(3) } }
                        }
                        Divider()
                        Button("Remove from library", systemImage: "trash", role: .destructive) { showRemoveConfirmation = true }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Reading actions").disabled(working)
                }
            }
            if let error = store.personalError {
                InlineLoadError(message: error) { Task { await store.refreshOwnBook() } }
            }
            if let own = store.ownBook {
                Label(statusTitle(own.statusId), systemImage: own.statusId == 3 ? "checkmark.circle" : own.statusId == 2 ? "book" : "bookmark")
                    .foregroundStyle(own.statusId == 3 ? Color.green : Color.secondary)
                if !isOwnBook && own.editionId != book.editionId {
                    Button { Task { await openPersonalSheet(.edition) } } label: {
                        Label(own.displayFormat, systemImage: "books.vertical").frame(minHeight: 44)
                    }.accessibilityLabel("Change Edition").disabled(working)
                }
                if own.statusId == 2 {
                    Text(BookProgressPresentation.summary(own)).font(.subheadline).monospacedDigit()
                    if own.totalUnits > 0 { ProgressView(value: min(1, max(0, own.progress))) }
                    if let pace = ReadingPacePresentation.summary(
                        book: own, deadline: activity.deadline(for: own.bookId)) {
                        Label(pace, systemImage: "calendar.badge.clock")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.tint)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { readingTools(for: own) }
                        VStack(alignment: .leading, spacing: 8) { readingTools(for: own) }
                    }
                    Button { Task { await openPersonalSheet(.progress) } } label: {
                        Label("Update progress", systemImage: "slider.horizontal.3").frame(minHeight: 32)
                    }.buttonStyle(.borderedProminent).disabled(working)
                    if showFinishAction {
                        Button { Task { await prepareStatus(3) } } label: {
                            Label("Mark as finished", systemImage: "checkmark.circle").frame(minHeight: 32)
                        }.buttonStyle(.bordered).disabled(working)
                    }
                } else if own.statusId == 1 {
                    Button { Task { await prepareStatus(2) } } label: {
                        Label("Start Reading", systemImage: "book").frame(minHeight: 32)
                    }.buttonStyle(.borderedProminent).disabled(working)
                }
                if let rating = own.userRating {
                    Label { Text("Your rating: \(rating, specifier: "%.1f")") } icon: { Image(systemName: "star.fill") }.font(.subheadline)
                }
                if allowStandaloneReviewButton {
                    Button { Task { await openPersonalSheet(.review) } } label: {
                        Label("Rate and review", systemImage: "square.and.pencil").frame(minHeight: 44)
                    }.disabled(working)
                }
            } else if store.hasLoadedOwnBook {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { addButtons }
                    VStack(alignment: .leading, spacing: 8) { addButtons }
                }
                Button("Mark as finished", systemImage: "checkmark.circle") { Task { await prepareStatus(3) } }
                    .frame(minHeight: 44).disabled(working)
            } else if store.personalError == nil { ProgressView("Loading status...") }
            if completedBook {
                Label("Marked as finished", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder private func readingTools(for own: BookProgress) -> some View {
        Button { sessionBook = own } label: {
            Label(activity.activeSession?.bookID == own.bookId ? "Open session" : "Reading session", systemImage: "timer")
                .frame(minHeight: 32)
        }.buttonStyle(.bordered).disabled(working)
        Button { deadlineBook = own } label: {
            Label(activity.deadline(for: own.bookId) == nil ? "Set deadline" : "Edit deadline",
                  systemImage: "calendar.badge.clock").frame(minHeight: 32)
        }.buttonStyle(.bordered).disabled(working)
    }

    @ViewBuilder private var addButtons: some View {
        Button { Task { await prepareStatus(2) } } label: {
            Label("Start Reading", systemImage: "book").frame(minHeight: 32)
        }.buttonStyle(.borderedProminent).disabled(working)
        Button { Task { await prepareStatus(1) } } label: {
            Label("Want to Read", systemImage: "bookmark").frame(minHeight: 32)
        }.buttonStyle(.bordered).disabled(working)
    }

    @ViewBuilder private var descriptionSection: some View {
        if let description = store.metadata?.description ?? book.bookDescription, !description.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Description").font(.headline)
                Text(description).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        } else if store.isLoading { ProgressView("Loading description...") }
    }

    private var quotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quotes").font(.headline)
                Spacer()
                Button { highlightQuoteId = nil; showQuotes = true } label: {
                    Image(systemName: "quote.opening").frame(width: 44, height: 44)
                }.accessibilityLabel("View All Quotes")
            }
            if let error = store.quotesError {
                InlineLoadError(message: error) { Task { await store.loadQuotes(fresh: true) } }
            }
            ForEach(store.quotes.prefix(3)) { quote in
                Button { highlightQuoteId = quote.id; showQuotes = true } label: {
                    Text(quote.entry).font(.subheadline).foregroundStyle(.primary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain)
                Divider()
            }
            if store.loadingQuotes { ProgressView() }
            else if store.quotes.isEmpty && store.quotesError == nil {
                Button("Add your first quote...", systemImage: "plus") { showQuotes = true }.frame(minHeight: 44)
            }
        }.task(id: authRevision) { await store.loadQuotes() }
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reviews").font(.headline)
            ForEach(store.reviews) { SearchReviewRow(review: $0) }
            if let error = store.reviewsError {
                InlineLoadError(message: error) { Task { await store.loadReviews(more: !store.reviews.isEmpty, fresh: true) } }
            }
            if store.loadingReviews { ProgressView() }
            else if store.reviews.isEmpty && store.reviewsError == nil { Text("No reviews found").foregroundStyle(.secondary) }
            else if store.hasMoreReviews {
                Button("Load more") { Task { await store.loadReviews(more: true) } }.frame(minHeight: 44)
            }
        }.task(id: authRevision) { await store.loadReviews() }
    }

    private var technicalDetails: some View {
        DisclosureGroup("Book information") {
            if let id = book.bookId { copyID("Book ID", id: id) }
            if let id = book.editionId { copyID("Edition ID", id: id) }
            if let id = store.ownBook?.userBookId { copyID("User Book ID", id: id) }
        }.font(.subheadline).foregroundStyle(.secondary)
    }

    private func copyID(_ title: LocalizedStringKey, id: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(String(id)).monospacedDigit().textSelection(.enabled)
            Button { UIPasteboard.general.string = String(id) } label: {
                Image(systemName: "doc.on.doc").frame(width: 44, height: 44)
            }.accessibilityLabel(Text("Copy \(Text(title))"))
        }
    }

    private func statusTitle(_ status: Int?) -> String {
        switch status {
        case 1: return NSLocalizedString("Want to Read", comment: "")
        case 2: return NSLocalizedString("Currently Reading", comment: "")
        case 3: return NSLocalizedString("Finished", comment: "")
        default: return NSLocalizedString("In your library", comment: "")
        }
    }

    private enum PersonalSheet { case progress, edition, dates, review }

    @MainActor private func openPersonalSheet(_ sheet: PersonalSheet) async {
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            let own = try await BookPersonalActions.requireOwnBook(bookID: book.bookId, authorization: HardcoverConfig.accountIdentifier)
            store.apply(own)
            switch sheet {
            case .progress: progressBook = own
            case .edition: editionBook = own
            case .dates: datesBook = own
            case .review: finishing = false; reviewBook = own
            }
        } catch { actionError = error.localizedDescription }
    }

    @MainActor private func prepareStatus(_ status: Int) async {
        guard !working, let bookID = book.bookId else { return }
        if OfflineWriteQueue.shared.isOffline {
            if status == 3 {
                presentFinish(store.ownBook, editionID: store.ownBook?.editionId ?? book.editionId)
            } else {
                await changeStatusOffline(status, editionID: store.ownBook?.editionId ?? book.editionId)
            }
            return
        }
        working = true
        let account = HardcoverConfig.accountIdentifier
        do {
            let own = try await LibraryAPI.ownBook(bookID: bookID, fresh: true)
            guard account == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
            if let own { store.apply(own) }
            if own == nil && !skipEditionPicker {
                let values = await HardcoverService.fetchEditions(for: bookID)
                guard account == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
                if values.count > 1 {
                    editions = values; pendingStatus = status; showEditionSelection = true; working = false
                    return
                }
                working = false
                await changeStatus(status, editionID: values.first?.id)
            } else {
                working = false
                await changeStatus(status, editionID: own?.editionId ?? book.editionId)
            }
        } catch { working = false; actionError = error.localizedDescription }
    }

    @MainActor private func changeStatus(_ status: Int, editionID: Int?) async {
        guard !working, let bookID = book.bookId else { return }
        working = true
        defer { working = false }
        let account = HardcoverConfig.accountIdentifier
        do {
            var own = try await LibraryAPI.ownBook(bookID: bookID, fresh: true)
            guard account == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
            if status == 1, let onAddToWantToRead, own == nil { onAddToWantToRead(editionID); return }
            if status == 3 {
                presentFinish(own, editionID: editionID)
                return
            }
            let success: Bool
            if let userBookID = own?.userBookId {
                success = await OfflineWriteQueue.shared.perform(.status(userBookID: userBookID, statusID: status, userDate: nil))
            } else {
                success = await OfflineWriteQueue.shared.perform(.add(bookID: bookID, editionID: editionID, statusID: status))
            }
            guard success else { throw BookPersonalActions.Failure.saveFailed }
            guard account == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
            WidgetSync.libraryChanged(statuses: [own?.statusId ?? 1, status])
            await store.refreshOwnBook()
            onLibraryChange?(store.ownBook)
        } catch { actionError = error.localizedDescription }
    }

    @MainActor private func presentFinish(_ own: BookProgress?, editionID: Int?) {
        if let own { store.apply(own) }
        var candidate = own ?? book
        if candidate.editionId == nil { candidate.editionId = editionID }
        finishing = true
        reviewBook = candidate
    }

    @MainActor private func changeStatusOffline(_ status: Int, editionID: Int?) async {
        guard let bookID = book.bookId else { return }
        let current = store.ownBook
        let operation: OfflineWriteOperation
        if let userBookID = current?.userBookId {
            operation = .status(userBookID: userBookID, statusID: status, userDate: nil)
        } else {
            operation = .add(bookID: bookID, editionID: editionID, statusID: status)
        }
        guard await OfflineWriteQueue.shared.perform(operation) else {
            actionError = BookPersonalActions.Failure.saveFailed.localizedDescription
            return
        }
        var updated = current ?? book
        if updated.editionId == nil { updated.editionId = editionID }
        let oldStatus = updated.statusId ?? 1
        updated.statusId = status
        store.apply(updated)
        WidgetSync.libraryChanged(statuses: [oldStatus, status])
        onLibraryChange?(updated)
    }

    @MainActor private func removeBook() async {
        guard !working else { return }
        working = true
        defer { working = false }
        let account = HardcoverConfig.accountIdentifier
        do {
            let own = try await BookPersonalActions.requireOwnBook(bookID: book.bookId, authorization: account)
            guard let id = own.userBookId, await OfflineWriteQueue.shared.perform(.delete(userBookID: id)) else { throw BookPersonalActions.Failure.saveFailed }
            guard account == HardcoverConfig.accountIdentifier else { throw HardcoverNetworkError.accountChanged }
            WidgetSync.libraryChanged(statuses: [own.statusId ?? 1])
            onLibraryChange?(nil)
            dismiss()
        } catch { actionError = error.localizedDescription }
    }

    private func libraryChanged(_ updated: BookProgress) {
        store.apply(updated)
        if isOwnBook { mergeOwnBook(updated) }
        onLibraryChange?(updated)
    }

    @MainActor private func toggleOwned(editionID: Int) async {
        guard !working else { return }; working = true; defer { working = false }
        do {
            if let entry = ownedEditions.entry(editionID: editionID) {
                guard await OfflineWriteQueue.shared.perform(.unown(listBookID: entry.id)) else { throw BookPersonalActions.Failure.saveFailed }
                ownedEditions.optimisticRemove(entry)
            } else {
                guard await OfflineWriteQueue.shared.perform(.own(editionID: editionID, book: book)) else { throw BookPersonalActions.Failure.saveFailed }
                ownedEditions.optimisticMark(editionID: editionID, book: book)
                if !OfflineWriteQueue.shared.isOffline { await ownedEditions.load(refresh: true) }
            }
        } catch { actionError = error.localizedDescription }
    }

    private func mergeOwnBook(_ own: BookProgress) {
        var updated = own
        updated.bookDescription = store.metadata?.description ?? book.bookDescription
        book = updated
    }
}

private struct EditionSelectionLoader: View {
    let book: BookProgress
    let onSaved: (BookProgress) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editions: [Edition] = []
    @State private var selectedID: Int?
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var authorization = HardcoverConfig.accountIdentifier

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView() }
                if let error { InlineLoadError(message: error) { Task { await load() } } }
                ForEach(editions) { edition in
                    EditionRow(edition: edition, isSelected: selectedID == edition.id, isCurrent: book.editionId == edition.id) { selectedID = edition.id }
                }
            }
            .navigationTitle("Change Edition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() } else { Text("Save") }
                    }.disabled(saving || selectedID == nil || selectedID == book.editionId)
                }
            }
            .task { selectedID = book.editionId; await load() }
            .interactiveDismissDisabled(saving)
        }
    }

    @MainActor private func load() async {
        guard let id = book.bookId else { loading = false; return }
        loading = true; error = nil
        editions = await HardcoverService.fetchEditions(for: id)
        loading = false
        if editions.isEmpty { error = NSLocalizedString("No editions available", comment: "") }
    }

    @MainActor private func save() async {
        guard !saving, let selectedID else { return }
        saving = true; error = nil
        defer { saving = false }
        do {
            let own = try await BookPersonalActions.requireOwnBook(bookID: book.bookId, authorization: authorization)
            guard let id = own.userBookId, await HardcoverService.updateEdition(userBookId: id, editionId: selectedID) else { throw BookPersonalActions.Failure.saveFailed }
            WidgetSync.libraryChanged(statuses: [own.statusId ?? 1])
            let updated = try await BookPersonalActions.requireOwnBook(bookID: book.bookId, authorization: authorization)
            onSaved(updated)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
