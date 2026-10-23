import SwiftUI

struct HardcoverBookTag: Codable, Hashable, Identifiable {
    var id: String { "\(category)-\(name)-\(spoiler)" }
    let name: String
    let category: String
    var spoiler: Bool
    var count: Int?
}

enum BookTagsService {
    static let loadQuery = """
    query SoftcoverBookTags($userID: Int!, $bookID: bigint!) {
      mine: taggings(where: {user_id: {_eq: $userID}, taggable_id: {_eq: $bookID}, taggable_type: {_eq: "Book"}}) {
        spoiler tag { tag tag_category { category } }
      }
      vocabulary: taggings(where: {user_id: {_eq: $userID}, taggable_type: {_eq: "Book"}}, limit: 1000) {
        spoiler tag { tag tag_category { category } }
      }
      books(where: {id: {_eq: $bookID}}, limit: 1) {
        taggable_counts(order_by: {count: desc}, limit: 100) { count tag { tag tag_category { category } } }
      }
    }
    """
    static let saveMutation = """
    mutation SoftcoverSaveTags($id: bigint!, $tags: [BasicTag]!, $type: String!) {
      upsertTags: upsert_tags(tags: $tags, id: $id, type: $type) { tags { category tag count spoiler } }
    }
    """

    static func load(bookID: Int) async throws -> (mine: [HardcoverBookTag], vocabulary: [HardcoverBookTag], community: [HardcoverBookTag]) {
        let user = try await LibraryAPI.identity()
        let data = try await LibraryAPI.request(loadQuery, variables: ["userID": user.id, "bookID": bookID], fresh: true)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any] else { throw HardcoverNetworkError.invalidResponse }
        let mine: [HardcoverBookTag] = (payload["mine"] as? [[String: Any]] ?? []).compactMap { row in
            guard let tag = row["tag"] as? [String: Any], let name = tag["tag"] as? String else { return nil }
            let category = ((tag["tag_category"] as? [String: Any])?["category"] as? String) ?? "Other"
            return HardcoverBookTag(name: name, category: category, spoiler: row["spoiler"] as? Bool ?? false, count: nil)
        }
        var seen = Set<String>()
        let vocabulary: [HardcoverBookTag] = (payload["vocabulary"] as? [[String: Any]] ?? []).compactMap { row in
            guard let tag = row["tag"] as? [String: Any], let name = tag["tag"] as? String else { return nil }
            let category = ((tag["tag_category"] as? [String: Any])?["category"] as? String) ?? "Other"
            let key = "\(category.lowercased())|\(name.lowercased())"
            guard seen.insert(key).inserted else { return nil }
            return HardcoverBookTag(name: name, category: category, spoiler: row["spoiler"] as? Bool ?? false, count: nil)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let book = (payload["books"] as? [[String: Any]])?.first
        let community: [HardcoverBookTag] = (book?["taggable_counts"] as? [[String: Any]] ?? []).compactMap { row in
            guard let tag = row["tag"] as? [String: Any], let name = tag["tag"] as? String else { return nil }
            let category = ((tag["tag_category"] as? [String: Any])?["category"] as? String) ?? "Other"
            return HardcoverBookTag(name: name, category: category, spoiler: false, count: row["count"] as? Int)
        }
        return (mine, vocabulary, community)
    }

    static func save(bookID: Int, tags: [HardcoverBookTag]) async throws {
        let values = tags.map { ["tag": $0.name, "category": $0.category, "spoiler": $0.spoiler] as [String: Any] }
        let data = try await LibraryAPI.request(saveMutation, variables: ["id": bookID, "type": "Book", "tags": values], fresh: true)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["errors"] == nil else {
            throw HardcoverNetworkError.invalidResponse
        }
    }
}

struct BookTagsView: View {
    let bookID: Int
    @Environment(\.dismiss) private var dismiss
    @State private var mine: [HardcoverBookTag] = []
    @State private var community: [HardcoverBookTag] = []
    @State private var vocabulary: [HardcoverBookTag] = []
    @State private var newName = ""
    @State private var category = "Mood"
    @State private var spoiler = false
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    private let categories = ["Genre", "Mood", "Tag", "Content Warning", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                if loading { ProgressView("Loading tags…") }
                if let error { Text(error).foregroundStyle(.red) }
                Section("Your tags") {
                    if mine.isEmpty && !loading { Text("No personal tags yet").foregroundStyle(.secondary) }
                    ForEach($mine) { $tag in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tag.name)
                                Text(tag.category).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Spoiler", isOn: $tag.spoiler).labelsHidden()
                            Button(role: .destructive) { mine.removeAll { $0.id == tag.id } } label: { Image(systemName: "minus.circle") }
                        }
                    }
                }
                Section("Add a tag") {
                    TextField("Tag", text: $newName)
                    Picker("Category", selection: $category) { ForEach(categories, id: \.self) { Text($0) } }
                    Toggle("Spoiler", isOn: $spoiler)
                    Button("Add", systemImage: "plus") { addCustom() }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Popular community tags") {
                    ForEach(community.prefix(30)) { tag in
                        Button {
                            guard !mine.contains(where: { $0.name.caseInsensitiveCompare(tag.name) == .orderedSame }) else { return }
                            mine.append(HardcoverBookTag(name: tag.name, category: tag.category, spoiler: false, count: nil))
                        } label: {
                            HStack { Text(tag.name); Spacer(); if let count = tag.count { Text("\(count)").foregroundStyle(.secondary) }; Image(systemName: "plus.circle") }
                        }.buttonStyle(.plain)
                    }
                }
                let reusable = vocabulary.filter { candidate in
                    !mine.contains { $0.name.caseInsensitiveCompare(candidate.name) == .orderedSame && $0.category == candidate.category }
                }
                if !reusable.isEmpty {
                    Section("Your recent tags") {
                        ForEach(reusable.prefix(30)) { tag in
                            Button { mine.append(tag) } label: {
                                HStack { Text(tag.name); Spacer(); Text(tag.category).foregroundStyle(.secondary); Image(systemName: "plus.circle") }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Book Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { Task { await save() } }.disabled(saving || loading) }
            }
            .task { await load() }
        }
    }

    private func addCustom() {
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !mine.contains(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        mine.append(.init(name: value, category: category, spoiler: spoiler, count: nil)); newName = ""; spoiler = false
    }
    @MainActor private func load() async {
        loading = true; defer { loading = false }
        do {
            let result = try await BookTagsService.load(bookID: bookID)
            mine = result.mine; vocabulary = result.vocabulary; community = result.community
        }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func save() async {
        saving = true; defer { saving = false }
        do { try await BookTagsService.save(bookID: bookID, tags: mine); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
