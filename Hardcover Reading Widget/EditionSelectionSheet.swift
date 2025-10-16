import SwiftUI

// A simple sheet to choose an Edition used from the Add Book → search flow.
// Now reuses the same EditionRow styling as the Want to Read edition picker.
struct EditionSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let bookTitle: String
    let currentEditionId: Int?
    let editions: [Edition]
    let onCancel: () -> Void
    let onSave: (Int?) -> Void

    @State private var selectedId: Int?

    init(
        bookTitle: String,
        currentEditionId: Int?,
        editions: [Edition],
        onCancel: @escaping () -> Void,
        onSave: @escaping (Int?) -> Void
    ) {
        self.bookTitle = bookTitle
        self.currentEditionId = currentEditionId
        self.editions = editions
        self.onCancel = onCancel
        self.onSave = onSave
        // Preselect the incoming current edition if any
        self._selectedId = State(initialValue: currentEditionId)
    }

    var body: some View {
        NavigationView {
            Group {
                if editions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No editions available")
                            .font(.headline)
                        Text("This book might only have one edition")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        Section(header: Text(NSLocalizedString("Select an edition", comment: "Header for edition picker section"))) {
                            ForEach(editions, id: \.id) { ed in
                                EditionRow(
                                    edition: ed,
                                    isSelected: selectedId == ed.id,
                                    isCurrent: currentEditionId == ed.id
                                ) {
                                    selectedId = ed.id
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(bookTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Save", comment: "Save button")) {
                        onSave(selectedId)
                        dismiss()
                    }
                    .disabled(editions.isEmpty || selectedId == nil || selectedId == currentEditionId)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // If currentEditionId isn’t in the provided list, clear the selection
            if let current = currentEditionId,
               !editions.contains(where: { $0.id == current }) {
                selectedId = nil
            }
        }
    }
}
