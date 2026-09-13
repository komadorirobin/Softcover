import SwiftUI

@MainActor
final class EditionPickerViewModel: ObservableObject {
    @Published var editions: [Edition] = []
    @Published var isLoading = true
    @Published var selectedEditionId: Int?
    @Published var isSaving = false
    @Published var showError = false
    @Published var errorMessage = ""

    let book: BookProgress
    private let onComplete: (Bool) -> Void
    private let account = HardcoverConfig.authorizationHeaderValue
    private var generation = UUID()

    init(book: BookProgress, onComplete: @escaping (Bool) -> Void) {
        self.book = book
        self.onComplete = onComplete
        selectedEditionId = book.editionId
    }

    func loadEditions() async {
        guard let id = book.bookId else { isLoading = false; return }
        let token = UUID()
        generation = token
        isLoading = true
        errorMessage = ""
        defer { if generation == token { isLoading = false } }
        do {
            let values = try await HardcoverReadScope.checked { await HardcoverService.fetchEditions(for: id) }
            guard generation == token, account == HardcoverConfig.authorizationHeaderValue else { return }
            editions = values
        } catch is CancellationError { }
        catch { if account == HardcoverConfig.authorizationHeaderValue { errorMessage = error.localizedDescription } }
    }

    func saveEdition(dismiss: @escaping () -> Void) async {
        guard !isSaving, let bookID = book.bookId, let editionID = selectedEditionId else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            guard account == HardcoverConfig.authorizationHeaderValue else { throw HardcoverNetworkError.accountChanged }
            guard let own = try await LibraryAPI.ownBook(bookID: bookID, fresh: true), let ownID = own.userBookId else {
                throw HardcoverNetworkError.invalidResponse
            }
            let success = try await HardcoverReadScope.checked {
                await HardcoverService.updateEdition(userBookId: ownID, editionId: editionID)
            }
            guard account == HardcoverConfig.authorizationHeaderValue else { throw HardcoverNetworkError.accountChanged }
            guard success else { throw HardcoverNetworkError.invalidResponse }
            WidgetSync.libraryChanged(statuses: [own.statusId ?? 2])
            onComplete(true)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
