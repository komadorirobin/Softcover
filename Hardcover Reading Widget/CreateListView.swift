import SwiftUI

enum HardcoverListWriter {
    static let mutation = """
    mutation SoftcoverCreateList($list: ListInput!) {
      insert_list(object: $list) { errors list { id name slug ranked privacy_setting_id } }
    }
    """

    static func create(name: String, description: String, isPrivate: Bool, ranked: Bool) async throws {
        var input: [String: Any] = [
            "name": name,
            "privacy_setting_id": isPrivate ? 3 : 1,
            "ranked": ranked
        ]
        if !description.isEmpty { input["description"] = description }
        let data = try await LibraryAPI.request(mutation, variables: ["list": input], fresh: true)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["errors"] == nil,
              let payload = root["data"] as? [String: Any],
              let result = payload["insert_list"] as? [String: Any],
              result["list"] is [String: Any] else {
            throw HardcoverNetworkError.invalidResponse
        }
        if let errors = result["errors"] as? [String], !errors.isEmpty {
            throw ListWriteError.server(errors.joined(separator: "\n"))
        }
    }

    enum ListWriteError: LocalizedError {
        case duplicate, server(String)
        var errorDescription: String? {
            switch self {
            case .duplicate: return "A list with this name already exists."
            case .server(let message): return message
            }
        }
    }
}

struct CreateListView: View {
    let existingNames: [String]
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = false
    @State private var ranked = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("List") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical).lineLimit(3...6)
                    Toggle("Private list", isOn: $isPrivate)
                    Toggle("Rank books", isOn: $ranked)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Creating…" : "Create") { Task { await create() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    @MainActor private func create() async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !existingNames.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) else {
            error = HardcoverListWriter.ListWriteError.duplicate.localizedDescription; return
        }
        saving = true; error = nil; defer { saving = false }
        do {
            try await HardcoverListWriter.create(name: clean,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                isPrivate: isPrivate, ranked: ranked)
            onCreated(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
