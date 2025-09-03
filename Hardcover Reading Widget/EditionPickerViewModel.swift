import SwiftUI

@MainActor
class EditionPickerViewModel: ObservableObject {
    @Published var editions: [Edition] = []
    @Published var isLoading = true
    @Published var selectedEditionId: Int?
    @Published var isSaving = false
    @Published var showError = false
    @Published var errorMessage = ""
    
    let book: BookProgress
    private let onComplete: (Bool) -> Void
    
    init(book: BookProgress, onComplete: @escaping (Bool) -> Void) {
        self.book = book
        self.onComplete = onComplete
        self.selectedEditionId = book.editionId
    }
    
    func loadEditions() async {
        print("🔄 Loading editions for book: \(book.title)")
        
        guard let bookId = book.bookId else {
            print("❌ No bookId available!")
            isLoading = false
            return
        }
        
        let fetchedEditions = await HardcoverService.fetchEditions(for: bookId)
        print("📚 Fetched \(fetchedEditions.count) editions")
        
        self.editions = fetchedEditions
        self.isLoading = false
        print("✅ Editions loaded, selected edition: \(self.selectedEditionId ?? -1)")
    }
    
    func saveEdition(dismiss: @escaping () -> Void) async {
        print("🔍 saveEdition called")
        
        guard let userBookId = book.userBookId else {
            print("❌ Missing userBookId!")
            errorMessage = "Missing user book ID. Please try refreshing the books list."
            showError = true
            return
        }
        
        guard let editionId = selectedEditionId else {
            print("❌ Missing selectedEditionId!")
            errorMessage = "No edition selected"
            showError = true
            return
        }
        
        print("💾 Saving edition - UserBookId: \(userBookId), EditionId: \(editionId)")
        
        isSaving = true
        
        let success = await HardcoverService.updateEdition(
            userBookId: userBookId,
            editionId: editionId
        )
        
        isSaving = false
        if success {
            print("✅ Edition saved successfully!")
            onComplete(true)
            dismiss()
        } else {
            print("❌ Failed to save edition")
            errorMessage = "Failed to save edition. Please try again."
            showError = true
        }
    }
}