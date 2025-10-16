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
    @State private var showDeveloperProfile = false
    @AppStorage("AppearancePreference", store: AppGroup.defaults) private var appearancePref: String = "system"
    // NEW: Skip edition picker preference
    @AppStorage("SkipEditionPickerOnAdd", store: AppGroup.defaults) private var skipEditionPickerOnAdd: Bool = false
    
    let onSaved: ((String) -> Void)?
    
    init(onSaved: ((String) -> Void)? = nil) {
        self.onSaved = onSaved
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API Key", comment: "Settings section title")) {
                    TextField("Paste your API key", text: $apiKey, axis: .vertical)
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
                        
                        Button("Clear") {
                            apiKey = ""
                        }
                        .foregroundColor(.red)
                    }
                }
                
                // Egen liten sektion för att få fullbreddsseparatorer
                Section {
                    Button(action: save) {
                        Text("Save Settings")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                Section(header: Text("Where do I find the key?")) {
                    Text("You can find your personal API key on Hardcover under Account → API. Log in and go to:")
                    Link("hardcover.app/account/api", destination: URL(string: "https://hardcover.app/account/api")!)
                }
                
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $appearancePref) {
                        Text("Follow System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    Text(hintText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // NEW: Add Book behavior
                Section(header: Text("Add Book")) {
                    Toggle("Skip \"Choose Edition\" when adding", isOn: $skipEditionPickerOnAdd)
                    Text("When enabled, the default edition is automatically used when you add a book to \"Want to Read\" or \"Currently Reading\".")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Account")) {
                    HStack {
                        Text("Username")
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
                
                Section(header: Text("About", comment: "About section title")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Softcover")
                            .font(.headline)
                        
                        Text("Created by Robin Bolinsson", comment: "App creator credit")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    Button {
                        showDeveloperProfile = true
                    } label: {
                        HStack {
                            Image(systemName: "person.circle")
                            Text("View Developer Profile", comment: "Link to developer profile")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("Data Source", comment: "Data source label")) {
                    Text("All book data, reviews, and reading lists are provided by Hardcover.", comment: "Data source description")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    
                    Link(destination: URL(string: "https://hardcover.app")!) {
                        HStack {
                            Image(systemName: "link")
                            Text("Visit Hardcover", comment: "Link to Hardcover website")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
            }
            .navigationTitle("API Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { loadExistingAndRefreshUsername() }
            .alert("Saved", isPresented: $showSaved) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your settings were saved. Widgets will update shortly.")
            }
            .alert("Could not paste", isPresented: $showPasteWarning) {
                Button("OK") { }
            } message: {
                Text("Check that clipboard contains text, and allow \"Paste\" if iOS asks.")
            }
            .sheet(isPresented: $showDeveloperProfile) {
                NavigationView {
                    UserProfileView(username: "KomadoriRobin")
                }
            }
        }
    }
    
    private var hintText: String {
        switch appearancePref {
        case "light": return "App is forced to light mode."
        case "dark": return "App is forced to dark mode."
        default: return "App follows system light/dark mode."
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

