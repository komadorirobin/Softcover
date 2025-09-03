import SwiftUI
import WidgetKit
import UniformTypeIdentifiers

struct ApiKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var detectedUsername: String = ""
    @State private var isFetchingUsername = false
    @State private var showSaved = false
    @State private var showPasteWarning = false
    @AppStorage("AppearancePreference", store: AppGroup.defaults) private var appearancePref: String = "system"
    
    let onSaved: ((String) -> Void)?
    
    init(onSaved: ((String) -> Void)? = nil) {
        self.onSaved = onSaved
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Hardcover API-nyckel")) {
                    TextField("Klistra in din API-nyckel", text: $apiKey, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(3, reservesSpace: true)
                    
                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            if let pasted = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !pasted.isEmpty {
                                apiKey = pasted
                            } else {
                                showPasteWarning = true
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Rensa") {
                            apiKey = ""
                        }
                        .foregroundColor(.red)
                    }
                }
                
                // Egen liten sektion för att få fullbreddsseparatorer
                Section {
                    Button(action: save) {
                        Text("Spara inställningar")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                Section(header: Text("Utseende")) {
                    Picker("Tema", selection: $appearancePref) {
                        Text("Följer system").tag("system")
                        Text("Ljust").tag("light")
                        Text("Mörkt").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    Text(hintText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Konto")) {
                    HStack {
                        Text("Användarnamn")
                        Spacer()
                        if isFetchingUsername {
                            ProgressView()
                        } else if detectedUsername.isEmpty {
                            Text("—")
                                .foregroundColor(.secondary)
                        } else {
                            Text("@\(detectedUsername)")
                                .fontWeight(.semibold)
                        }
                    }
                }
                
                Section(header: Text("Var hittar jag nyckeln?")) {
                    Text("Du hittar din personliga API-nyckel på Hardcover under Konto → API. Logga in och gå till:")
                    Link("hardcover.app/account/api", destination: URL(string: "https://hardcover.app/account/api")!)
                }
            }
            .navigationTitle("API-inställningar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
            }
            .onAppear { loadExistingAndRefreshUsername() }
            .alert("Sparat", isPresented: $showSaved) {
                Button("OK") { dismiss() }
            } message: {
                Text("Dina inställningar sparades. Widgetar uppdateras strax.")
            }
            .alert("Kunde inte klistra in", isPresented: $showPasteWarning) {
                Button("OK") { }
            } message: {
                Text("Kontrollera att clipboard innehåller text, och tillåt ”Klistra in” om iOS frågar.")
            }
        }
    }
    
    private var hintText: String {
        switch appearancePref {
        case "light": return "Appen tvingas till ljust läge."
        case "dark": return "Appen tvingas till mörkt läge."
        default: return "Appen följer systemets ljus/mörkt."
        }
    }
    
    private func loadExistingAndRefreshUsername() {
        if let key = AppGroup.defaults.string(forKey: "HardcoverAPIKey") {
            apiKey = key
        }
        detectedUsername = AppGroup.defaults.string(forKey: "HardcoverUsername") ?? ""
        
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { await refreshUsername() }
        }
    }
    
    private func refreshUsername() async {
        await MainActor.run { isFetchingUsername = true }
        await HardcoverService.refreshUsernameFromAPI()
        let u = AppGroup.defaults.string(forKey: "HardcoverUsername") ?? ""
        await MainActor.run {
            detectedUsername = u
            isFetchingUsername = false
        }
    }
    
    private func save() {
        let normalizedKey = HardcoverConfig.normalize(apiKey)
        AppGroup.defaults.set(normalizedKey, forKey: "HardcoverAPIKey")
        
        Task {
            await refreshUsername()
            WidgetCenter.shared.reloadAllTimelines()
            await MainActor.run {
                onSaved?(normalizedKey)
                showSaved = true
            }
        }
    }
}
