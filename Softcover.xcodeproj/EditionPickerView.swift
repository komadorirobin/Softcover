import SwiftUI

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
