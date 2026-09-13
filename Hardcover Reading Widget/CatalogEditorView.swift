import SwiftUI
import WidgetKit

extension CatalogService {
    static func live() -> CatalogService {
        let authorization = HardcoverConfig.authorizationHeaderValue
        return CatalogService(authorization: authorization,
                       currentAuthorization: { HardcoverConfig.authorizationHeaderValue },
                       beforeRequest: { query in
                           let cost = query == editionEditingQuery ? 3 : ([overviewQuery, lookupsQuery].contains(query) ? 2 : 1)
                           try await HardcoverRequestScheduler.shared.acquire(authorization: authorization, cost: cost)
                       },
                       afterResponse: { await HardcoverRequestScheduler.shared.observe($0, authorization: authorization) },
                       afterMutation: { await HardcoverHTTP.shared.invalidateReads(authorization: authorization) })
    }
}

private struct CatalogAccessRequest: Hashable {
    let bookID: Int?
    let apiKey: String
}

private struct CatalogEditingModifier: ViewModifier {
    let bookID: Int?
    let currentEditionID: Int?
    let onSaved: () -> Void
    @AppStorage("HardcoverAPIKey", store: AppGroup.defaults) private var apiKey = ""
    @State private var checkingAccess = true
    @State private var allowed = false
    @State private var accessError: String?
    @State private var showingError = false
    @State private var showingEditor = false
    @State private var changed = false

    private var accessRequest: CatalogAccessRequest {
        CatalogAccessRequest(bookID: bookID, apiKey: apiKey)
    }

    func body(content: Content) -> some View {
        content
        .toolbar {
            if bookID != nil {
                if checkingAccess {
                    ToolbarItem(placement: .primaryAction) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Catalog editing access")
                    }
                } else if allowed {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            changed = false
                            showingEditor = true
                        } label: { Image(systemName: "pencil") }
                        .accessibilityLabel("Edit on Hardcover")
                        .help("Edit on Hardcover")
                    }
                } else if accessError != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingError = true } label: { Image(systemName: "lock") }
                            .accessibilityLabel("Catalog editing access")
                            .help("Catalog editing access")
                    }
                }
            }
        }
        // The detail view owns the task; a hidden toolbar item has no view lifetime.
        .task(id: accessRequest) { await checkAccess() }
        .alert("Catalog editing access", isPresented: $showingError) {
            Button("Retry") { Task { await checkAccess() } }
            Button("Cancel", role: .cancel) { }
        } message: { Text(accessError ?? "") }
        .sheet(isPresented: $showingEditor, onDismiss: {
            if changed { onSaved() }
        }) {
            if let bookID { CatalogEditorHub(bookID: bookID, currentEditionID: currentEditionID) { changed = true } }
        }
    }

    @MainActor private func checkAccess() async {
        let request = accessRequest
        checkingAccess = true
        allowed = false
        accessError = nil
        defer {
            if !Task.isCancelled, accessRequest == request { checkingAccess = false }
        }
        guard bookID != nil, !apiKey.isEmpty else { return }
        do {
            let granted = try await CatalogService.live().canEdit()
            guard !Task.isCancelled, accessRequest == request else { return }
            allowed = granted
        }
        catch {
            guard !Task.isCancelled, accessRequest == request else { return }
            accessError = error.localizedDescription
        }
    }
}

private struct CatalogBookEditingModifier: ViewModifier {
    @Binding var book: BookProgress
    var onUpdated: (BookProgress) -> Void
    @State private var refreshFailed = false

    func body(content: Content) -> some View {
        content
        .catalogEditing(bookID: book.bookId, currentEditionID: book.editionId) {
            Task {
                do {
                    book = try await book.refreshingCatalogMetadata()
                    onUpdated(book)
                } catch { refreshFailed = true }
            }
        }
        .catalogRefreshError($refreshFailed)
    }
}

extension View {
    func catalogEditing(bookID: Int?, currentEditionID: Int? = nil, onSaved: @escaping () -> Void) -> some View {
        modifier(CatalogEditingModifier(bookID: bookID, currentEditionID: currentEditionID, onSaved: onSaved))
    }

    func catalogEditing(book: Binding<BookProgress>, onUpdated: @escaping (BookProgress) -> Void) -> some View {
        modifier(CatalogBookEditingModifier(book: book, onUpdated: onUpdated))
    }
}

struct CatalogEditorHub: View {
    let bookID: Int
    let currentEditionID: Int?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var service = CatalogService.live()
    @State private var book: CatalogBook?
    @State private var editions: [CatalogEditionSummary] = []
    @State private var error: String?
    @State private var retryAt: Date?
    @State private var loading = false
    @State private var hasMore = false
    @State private var editionOffset = 0

    var body: some View {
        NavigationStack {
            List {
                if let book {
                    Section {
                        NavigationLink {
                            CatalogBookEditor(original: book, service: service, onSaved: saved)
                        } label: { Label("Edit Book", systemImage: "book.closed") }
                        .disabled(book.locked)
                        if book.locked { Label("Locked on Hardcover", systemImage: "lock") }
                        if let currentEditionID {
                            NavigationLink {
                                CatalogEditionLoader(id: currentEditionID, bookID: bookID, service: service, onSaved: saved)
                            } label: { Label("Edit current edition", systemImage: "book.pages") }
                        }
                    } header: { Text(book.title ?? "") }

                    Section("Edit Editions") {
                        ForEach(editions) { edition in
                            NavigationLink {
                                CatalogEditionLoader(id: edition.id, bookID: bookID, service: service, onSaved: saved)
                            } label: { CatalogEditionLabel(edition: edition) }
                        }
                        if hasMore {
                            Button("Load more") { Task { await loadMore() } }.disabled(loading)
                        }
                    }
                }
                if loading { CatalogLoadingIndicator(retryAt: retryAt) }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                        CatalogRetryButton(retryAt: retryAt, disabled: loading) { await load() }
                    }
                }
            }
            .navigationTitle("Edit on Hardcover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { if book == nil { await load() } }
        }
    }

    @MainActor private func load() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            var loader = service
            loader.onRateLimit = { date in await MainActor.run { retryAt = date } }
            let overview = try await loader.editorOverview(bookID: bookID)
            book = overview.book
            editions = overview.editions
            editionOffset = editions.count
            hasMore = editions.count == 50
            retryAt = nil
        } catch is CancellationError { }
        catch {
            self.error = error.localizedDescription
            if case CatalogError.rateLimited(let date) = error { retryAt = date }
        }
    }

    @MainActor private func loadMore() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            var loader = service
            loader.onRateLimit = { date in await MainActor.run { retryAt = date } }
            let page = try await loader.editions(bookID: bookID, offset: editionOffset)
            let existing = Set(editions.map(\.id))
            editions += page.filter { !existing.contains($0.id) }
            editionOffset += page.count
            hasMore = page.count == 50
            retryAt = nil
        } catch is CancellationError { }
        catch {
            self.error = error.localizedDescription
            if case CatalogError.rateLimited(let date) = error { retryAt = date }
        }
    }

    private func saved() {
        onSaved()
        WidgetSync.libraryChanged(statuses: [1, 2, 3])
        WidgetSync.quotesChanged()
        Task { await load() }
    }
}

private struct CatalogLoadingIndicator: View {
    let retryAt: Date?
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
            if let retryAt {
                Text("Hardcover is temporarily limiting requests. Retrying automatically.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(timerInterval: Date()...max(Date(), retryAt), countsDown: true)
                    .monospacedDigit().font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CatalogRetryButton: View {
    let retryAt: Date?
    let disabled: Bool
    let action: () async -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Button("Retry") { Task { await action() } }
                .disabled(disabled || (retryAt.map { $0 > context.date } ?? false))
        }
    }
}

struct CatalogEditionLabel: View {
    let edition: CatalogEditionSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CatalogCoverPreview(url: edition.image?.url)
                .frame(width: 44, height: 66)
            VStack(alignment: .leading, spacing: 4) {
                Text(edition.title ?? "#\(edition.id)").lineLimit(3)
                Text(edition.readingFormat?.displayName ?? NSLocalizedString("Unknown format", comment: ""))
                    .font(.caption.weight(.semibold))
                if let isbn = edition.isbn13 { Text(isbn).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct CatalogCoverPreview: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "book.closed").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.1))
            }
        }
        .accessibilityHidden(true)
    }
}

struct CatalogEditionLoader: View {
    let id: Int
    let bookID: Int
    let service: CatalogService
    let onSaved: () -> Void
    @State private var edition: CatalogEdition?
    @State private var lookups: CatalogLookups?
    @State private var error: String?
    @State private var retryAt: Date?
    @State private var loading = false

    var body: some View {
        Group {
            if let edition, let lookups {
                CatalogEditionEditor(original: edition, service: service, lookups: lookups, onSaved: onSaved)
            } else if let error {
                ContentUnavailableView {
                    Label("Could not load edition", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    CatalogRetryButton(retryAt: retryAt, disabled: loading) { await load() }
                }
            } else { CatalogLoadingIndicator(retryAt: retryAt) }
        }
        .task { if edition == nil { await load() } }
    }

    @MainActor private func load() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            var loader = service
            loader.onRateLimit = { date in await MainActor.run { retryAt = date } }
            let data = try await loader.editionEditingData(id: id)
            guard data.edition.bookID == bookID else { throw CatalogError.invalidResponse }
            edition = data.edition
            lookups = data.lookups
            retryAt = nil
        } catch is CancellationError { }
        catch {
            self.error = error.localizedDescription
            if case CatalogError.rateLimited(let date) = error { retryAt = date }
        }
    }
}

struct CatalogBookEditor: View {
    let original: CatalogBook
    let service: CatalogService
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CatalogBookDraft
    @State private var showingSeriesSearch = false
    @State private var showingCoverPicker = false
    @State private var cover: CatalogEditionSummary?
    @State private var saving = false
    @State private var confirmSave = false
    @State private var confirmDiscard = false
    @State private var error: String?
    @State private var warnings: String?

    init(original: CatalogBook, service: CatalogService, onSaved: @escaping () -> Void) {
        self.original = original
        self.service = service
        self.onSaved = onSaved
        _draft = State(initialValue: CatalogBookDraft(original))
        _cover = State(initialValue: original.defaultCoverEdition)
    }

    private var dirty: Bool { draft != CatalogBookDraft(original) }

    var body: some View {
        Form {
            Section("Book") {
                CatalogTextField("Title", text: $draft.title)
                CatalogDateField(value: $draft.releaseDate)
            }
            Section("Description") {
                TextField("Description", text: $draft.description, axis: .vertical).lineLimit(5...14)
            }
            Section("Cover") {
                CatalogCoverPreview(url: cover?.image?.url ?? original.image?.url)
                    .frame(width: 94, height: 140).frame(maxWidth: .infinity)
                Button { showingCoverPicker = true } label: { Label("Choose cover edition", systemImage: "photo") }
            }
            Section("Series") {
                ForEach($draft.series) { $series in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(series.series.displayName).font(.headline)
                            Spacer()
                            Button(role: .destructive) {
                                let id = series.id
                                draft.series.removeAll { $0.id == id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }.accessibilityLabel("Remove series")
                                .buttonStyle(.borderless)
                        }
                        CatalogTextField("Position in series", text: $series.position).keyboardType(.decimalPad)
                        Toggle("Featured series", isOn: $series.featured)
                    }
                    .padding(.vertical, 4)
                }
                Button { showingSeriesSearch = true } label: { Label("Add series", systemImage: "plus") }
            }
        }
        .disabled(saving || original.locked)
        .navigationTitle("Edit Book")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(dirty || saving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if dirty { confirmDiscard = true } else { dismiss() } }.disabled(saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() }
                else { Button("Save") { confirmSave = true }.disabled(!dirty || original.locked) }
            }
        }
        .catalogSaveConfirmation(isPresented: $confirmSave) { Task { await save() } }
        .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
        }
        .catalogError($error)
        .alert("Saved with warnings", isPresented: Binding(get: { warnings != nil }, set: { if !$0 { warnings = nil } })) {
            Button("OK") { dismiss() }
        } message: { Text(warnings ?? "") }
        .sheet(isPresented: $showingSeriesSearch) {
            CatalogEntitySearch(kind: .series, service: service, excluded: Set(draft.series.map(\.id))) { entity in
                draft.series.append(CatalogSeriesDraft(series: entity, position: "", featured: false, compilation: false))
            }
        }
        .sheet(isPresented: $showingCoverPicker) {
            CatalogCoverEditionPicker(bookID: original.id, currentID: draft.coverEditionID, service: service) { edition in
                cover = edition
                draft.coverEditionID = edition.id
            }
        }
    }

    @MainActor private func save() async {
        saving = true
        defer { saving = false }
        do {
            let messages = try await service.saveBook(original: original, draft: draft)
            onSaved()
            if messages.isEmpty { dismiss() } else { warnings = messages.joined(separator: "\n") }
        } catch { self.error = error.localizedDescription }
    }
}

struct CatalogEditionEditor: View {
    let original: CatalogEdition
    let service: CatalogService
    let lookups: CatalogLookups
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CatalogEditionDraft
    @State private var searchKind: CatalogService.EntityKind?
    @State private var saving = false
    @State private var confirmSave = false
    @State private var confirmDiscard = false
    @State private var error: String?
    @State private var warnings: String?
    @State private var importedCover: (url: String, id: Int)?

    init(original: CatalogEdition, service: CatalogService, lookups: CatalogLookups, onSaved: @escaping () -> Void) {
        self.original = original
        self.service = service
        self.lookups = lookups
        self.onSaved = onSaved
        _draft = State(initialValue: CatalogEditionDraft(original))
    }

    private var dirty: Bool {
        !draft.coverURL.isEmpty || (try? draft.patch(from: original).isEmpty) != true
    }

    var body: some View {
        Form {
            if original.locked { Label("Locked on Hardcover", systemImage: "lock") }
            Section("Edition") {
                CatalogTextField("Title", text: $draft.title)
                CatalogTextField("Subtitle", text: $draft.subtitle)
                Picker("Format", selection: $draft.readingFormatID) {
                    ForEach(lookups.formats) { Text($0.displayName).tag($0.id) }
                    if !lookups.formats.contains(where: { $0.id == draft.readingFormatID }) {
                        Text("Unknown format").tag(draft.readingFormatID)
                    }
                }
                CatalogTextField("Binding / edition format", text: $draft.editionFormat)
                CatalogDateField(value: $draft.releaseDate)
                CatalogTextField("Pages", text: $draft.pages).keyboardType(.numberPad)
                if draft.isAudiobook {
                    CatalogTextField("Audio length (seconds)", text: $draft.audioSeconds).keyboardType(.numberPad)
                }
                CatalogTextField("ISBN-10", text: $draft.isbn10).textInputAutocapitalization(.characters).autocorrectionDisabled()
                CatalogTextField("ISBN-13", text: $draft.isbn13).keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
            }
            Section("Publisher") {
                Button { searchKind = .publisher } label: {
                    HStack {
                        Text(draft.publisher?.displayName ?? NSLocalizedString("Select publisher", comment: ""))
                        Spacer()
                        Image(systemName: "magnifyingglass")
                    }
                }
                if draft.publisher != nil {
                    Button("Remove publisher", role: .destructive) { draft.publisher = nil }
                }
            }
            contributorsSection
            coverSection
        }
        .disabled(saving || original.locked)
        .navigationTitle("Edit Edition")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(dirty || saving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if dirty { confirmDiscard = true } else { dismiss() } }.disabled(saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() }
                else { Button("Save") { confirmSave = true }.disabled(!dirty || original.locked) }
            }
        }
        .catalogSaveConfirmation(isPresented: $confirmSave) { Task { await save() } }
        .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
        }
        .catalogError($error)
        .alert("Saved with warnings", isPresented: Binding(get: { warnings != nil }, set: { if !$0 { warnings = nil } })) {
            Button("OK") { dismiss() }
        } message: { Text(warnings ?? "") }
        .sheet(item: $searchKind) { kind in
            CatalogEntitySearch(kind: kind, service: service, excluded: []) { entity in
                if kind == .publisher { draft.publisher = entity }
                else {
                    draft.contributors.append(CatalogContributorDraft(author: entity))
                }
            }
        }
    }

    private var contributorsSection: some View {
        Section("Authors and contributors") {
            ForEach($draft.contributors) { $contributor in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(contributor.author.displayName).font(.headline)
                        Spacer()
                        Button(role: .destructive) {
                            let id = contributor.id
                            draft.contributors.removeAll { $0.id == id }
                        } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("Remove contributor").buttonStyle(.borderless)
                    }
                    Picker("Role", selection: $contributor.roleID) {
                        Text("Unspecified").tag(Int?.none)
                        ForEach(lookups.roles) { role in Text(role.displayName).tag(Optional(role.id)) }
                        if let id = contributor.roleID, !lookups.roles.contains(where: { $0.id == id }) {
                            Text("#\(id)").tag(Optional(id))
                        }
                    }
                    .disabled(contributor.specializationID != nil)
                    if let contribution = contributor.contribution, !contribution.isEmpty {
                        Text(contribution).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Button { searchKind = .author } label: { Label("Add contributor", systemImage: "person.badge.plus") }
        }
    }

    private var coverSection: some View {
        Section("Cover") {
            let selected = original.images.first { $0.id == draft.imageID } ?? original.image
            CatalogCoverPreview(url: draft.coverURL.isEmpty ? selected?.url : draft.coverURL)
                .frame(width: 107, height: 160).frame(maxWidth: .infinity)
            if !original.images.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(original.images) { image in
                            Button {
                                draft.imageID = image.id
                                draft.coverURL = ""
                            } label: {
                                CatalogCoverPreview(url: image.url)
                                    .frame(width: 60, height: 90)
                                    .padding(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(draft.imageID == image.id ? Color.accentColor : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Select cover")
                            .accessibilityAddTraits(draft.imageID == image.id ? .isSelected : [])
                        }
                    }.padding(3)
                }
            }
            TextField("New cover image URL", text: $draft.coverURL)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }

    @MainActor private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await service.validateEditionSave(original: original, draft: draft)
            if !draft.coverURL.isEmpty {
                if importedCover?.url != draft.coverURL {
                    let id = try await service.importCover(url: draft.coverURL, original: original)
                    importedCover = (draft.coverURL, id)
                }
                draft.imageID = importedCover?.id
            }
            let messages = try await service.saveEdition(original: original, draft: draft)
            onSaved()
            if messages.isEmpty { dismiss() } else { warnings = messages.joined(separator: "\n") }
        } catch { self.error = error.localizedDescription }
    }
}

struct CatalogTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    init(_ title: LocalizedStringKey, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("", text: $text, axis: .vertical)
                .accessibilityLabel(title)
        }
    }
}

struct CatalogDateField: View {
    @Binding var value: String
    var body: some View {
        LabeledContent("Release date") {
            TextField("YYYY-MM-DD", text: $value)
                .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("Release date")
        }
    }
}

extension View {
    func catalogRefreshError(_ isPresented: Binding<Bool>) -> some View {
        alert("Changes saved", isPresented: isPresented) {
            Button("OK") { }
        } message: {
            Text("The changes were saved, but the book details could not be refreshed. Reopen this view to try again.")
        }
    }

    func catalogError(_ error: Binding<String?>) -> some View {
        alert("Could not save", isPresented: Binding(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } })) {
            Button("OK") { error.wrappedValue = nil }
        } message: { Text(error.wrappedValue ?? "") }
    }

    func catalogSaveConfirmation(isPresented: Binding<Bool>, save: @escaping () -> Void) -> some View {
        confirmationDialog("Save to Hardcover?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Save to Hardcover", action: save)
        } message: {
            Text("These changes update the shared catalog for everyone on Hardcover.")
        }
    }
}
