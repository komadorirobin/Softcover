import SwiftUI
import UIKit

struct BookShareView: View {
    let book: BookProgress
    let metadata: BookDetailMetadata?
    @Environment(\.dismiss) private var dismiss
    @State private var includeDescription = true
    @State private var includeTags = true
    @State private var compact = false
    @State private var cover: UIImage?
    @State private var rendered: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BookShareCard(book: book, metadata: metadata, cover: cover,
                                  includeDescription: includeDescription,
                                  includeTags: includeTags, compact: compact)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section("Card") {
                    Toggle("Include description", isOn: $includeDescription)
                    Toggle("Include genres and moods", isOn: $includeTags)
                    Toggle("Compact layout", isOn: $compact)
                }
                Section {
                    Button("Share book card", systemImage: "square.and.arrow.up") { renderAndShare() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Share Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await loadCover() }
            .sheet(isPresented: Binding(get: { rendered != nil }, set: { if !$0 { rendered = nil } })) {
                if let rendered { ActivityShare(items: [rendered]) }
            }
        }
    }

    @MainActor private func renderAndShare() {
        let view = BookShareCard(book: book, metadata: metadata, cover: cover,
                                 includeDescription: includeDescription,
                                 includeTags: includeTags, compact: compact)
            .frame(width: 900, height: compact ? 760 : 1100)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        rendered = renderer.uiImage
    }

    private func loadCover() async {
        guard let value = book.coverImageUrl ?? metadata?.coverURL,
              let url = URL(string: value),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        await MainActor.run { cover = UIImage(data: data) }
    }
}

private struct BookShareCard: View {
    let book: BookProgress
    let metadata: BookDetailMetadata?
    let cover: UIImage?
    let includeDescription: Bool
    let includeTags: Bool
    let compact: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.95), .purple.opacity(0.75), .black.opacity(0.9)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: compact ? 24 : 38) {
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                        .frame(width: compact ? 210 : 280, height: compact ? 315 : 420)
                        .clipShape(RoundedRectangle(cornerRadius: 18)).shadow(radius: 20)
                } else {
                    RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.14))
                        .frame(width: compact ? 210 : 280, height: compact ? 315 : 420)
                        .overlay(Image(systemName: "book.closed.fill").font(.system(size: 80)).foregroundStyle(.white.opacity(0.7)))
                }
                VStack(spacing: 10) {
                    Text(metadata?.title ?? book.title).font(.system(size: compact ? 40 : 48, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center).lineLimit(3)
                    Text(metadata?.author ?? book.author).font(.system(size: 25, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }
                if includeTags {
                    let tags = Array(((metadata?.genres ?? []) + (metadata?.moods ?? [])).prefix(5))
                    if !tags.isEmpty { Text(tags.joined(separator: "  •  ")).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white.opacity(0.75)) }
                }
                if includeDescription, !compact, let text = metadata?.description ?? book.bookDescription, !text.isEmpty {
                    Text(text).font(.system(size: 20)).lineLimit(5).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.82))
                }
                Text("SOFTCOVER").font(.system(size: 18, weight: .black, design: .rounded)).tracking(6).foregroundStyle(.white.opacity(0.55))
            }.padding(56)
        }.foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 36))
    }
}

private struct ActivityShare: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
