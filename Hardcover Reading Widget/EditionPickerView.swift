import SwiftUI

struct EditionPickerView: View {
    @StateObject private var viewModel: EditionPickerViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(book: BookProgress, onComplete: @escaping (Bool) -> Void) {
        _viewModel = StateObject(wrappedValue: EditionPickerViewModel(book: book, onComplete: onComplete))
    }
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    loadingView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.editions.isEmpty {
                    emptyView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else {
                    List {
                        Section(header: Text("Select an edition")) {
                            ForEach(viewModel.editions) { edition in
                                // Behåll din befintliga radvy för konsekvent utseende
                                EditionRow(
                                    edition: edition,
                                    isSelected: viewModel.selectedEditionId == edition.id,
                                    isCurrent: viewModel.book.editionId == edition.id
                                ) {
                                    viewModel.selectedEditionId = edition.id
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(viewModel.book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await viewModel.saveEdition(dismiss: { dismiss() }) }
                        }
                        .disabled(viewModel.selectedEditionId == nil || viewModel.selectedEditionId == viewModel.book.editionId)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await viewModel.loadEditions() }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5)
            Text("Loading editions...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No editions found")
                .font(.headline)
            Text("This book might only have one edition")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
