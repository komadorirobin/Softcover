import SwiftUI
import WidgetKit
import UniformTypeIdentifiers
import AuthenticationServices

struct ApiKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var oauth = HardcoverOAuthCoordinator()
    @State private var apiKey: String = ""
    @State private var detectedUsername: String = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var showSaved = false
    @State private var showPasteWarning = false
    @State private var showDeveloperProfile = false
    @State private var showAPIKeyFallback = false
    @State private var showDisconnectConfirmation = false
    @AppStorage("AppearancePreference", store: AppGroup.defaults) private var appearancePref: String = "system"
    // NEW: Skip edition picker preference
    @AppStorage("SkipEditionPickerOnAdd", store: AppGroup.defaults) private var skipEditionPickerOnAdd: Bool = false
    // NEW: Default progress input mode preference
    @AppStorage("DefaultProgressInputMode", store: AppGroup.defaults) private var defaultProgressInputMode: String = "page"
    // NEW: Currently Reading widget sort order preference
    @AppStorage("CurrentlyReadingSortOrder", store: AppGroup.defaults) private var currentlyReadingSortOrder: String = "recentlyUpdated"
    @AppStorage("ShowReadingStreak", store: AppGroup.defaults) private var showReadingStreak = true
    @AppStorage("LibrarySwipeEnabled", store: AppGroup.defaults) private var librarySwipeEnabled = true
    @AppStorage("DateFormatPreference", store: AppGroup.defaults) private var dateFormatPreference = "regional"
    
    let onSaved: ((String) -> Void)?
    
    init(onSaved: ((String) -> Void)? = nil) {
        self.onSaved = onSaved
    }
    
    var body: some View {
        NavigationView {
            Form {
                if !HardcoverConfig.isSignedIn {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "hand.wave.fill")
                                    .font(.title)
                                    .foregroundColor(.blue)
                                Text(NSLocalizedString("Welcome to Softcover!", comment: "Onboarding welcome title"))
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            
                            Text(NSLocalizedString("Connect your Hardcover account to sync your library, reading progress, and widgets.", comment: "Onboarding welcome description"))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                Section("Hardcover Account") {
                    if HardcoverConfig.isSignedIn {
                        LabeledContent("Username", value: detectedUsername.isEmpty ? "-" : "@\(detectedUsername)")
                        Label(HardcoverConfig.usesOAuth ? "Connected securely" : "Connected with API key",
                              systemImage: HardcoverConfig.usesOAuth ? "checkmark.shield.fill" : "key.fill")
                            .foregroundStyle(.green)
                        if !HardcoverConfig.usesOAuth {
                            Button(action: connectWithHardcover) {
                                HStack {
                                    if oauth.isWorking { ProgressView() }
                                    Label("Switch to Hardcover Sign-In", systemImage: "person.badge.key.fill")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving || oauth.isWorking)
                        }
                        Button("Disconnect", role: .destructive) { showDisconnectConfirmation = true }
                            .disabled(isSaving || oauth.isWorking)
                    } else {
                        Button(action: connectWithHardcover) {
                            HStack {
                                if oauth.isWorking { ProgressView() }
                                Label("Connect with Hardcover", systemImage: "person.badge.key.fill")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || oauth.isWorking)
                        Text("Softcover opens Hardcover so you can approve access. Your password is never shared with Softcover.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let saveError {
                        Text(saveError).font(.callout).foregroundStyle(.red)
                    }
                }

                Section {
                    DisclosureGroup("Use an API key instead", isExpanded: $showAPIKeyFallback) {
                        SecureField("Paste your API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                            .disabled(isSaving || oauth.isWorking)

                        HStack {
                            PasteButton(payloadType: String.self) { strings in
                                if let pasted = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !pasted.isEmpty { apiKey = pasted }
                                else { showPasteWarning = true }
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Button("Clear") { apiKey = "" }.foregroundColor(.red)
                        }
                        .disabled(isSaving || oauth.isWorking)

                        Button(action: save) {
                            HStack {
                                if isSaving { ProgressView() }
                                Text("Save API Key")
                            }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || oauth.isWorking || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Text("API keys remain supported for existing users and development builds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section(header: Text("Appearance")) {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Themes & App Icon", systemImage: "paintpalette.fill")
                    }
                    Text(hintText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Library & Reading")) {
                    Toggle("Show reading streak", isOn: $showReadingStreak)
                    Toggle("Swipe between library shelves", isOn: $librarySwipeEnabled)
                    NavigationLink("Choose and reorder shelves") { LibraryShelfSettingsView() }
                    Picker("Date format", selection: $dateFormatPreference) {
                        Text("Regional default").tag("regional")
                        Text("Day / Month / Year").tag("dmy")
                        Text("Month / Day / Year").tag("mdy")
                        Text("Year / Month / Day").tag("ymd")
                    }
                }
                
                // NEW: Add Book behavior
                Section(header: Text("Add Book")) {
                    Toggle("Skip \"Choose Edition\" when adding", isOn: $skipEditionPickerOnAdd)
                    Text("When enabled, the default edition is automatically used when you add a book to \"Want to Read\" or \"Currently Reading\".")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // NEW: Progress Update preference
                Section(header: Text("Progress Update")) {
                    Picker("Default input mode", selection: $defaultProgressInputMode) {
                        Text("Page/Time").tag("page")
                        Text("Percent").tag("percent")
                    }
                    Text("Choose whether to update progress using page numbers/time or percentage by default. You can always switch between modes when updating.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // NEW: Widget Settings
                Section(header: Text("Widget Settings")) {
                    Picker("Currently Reading Sort Order", selection: $currentlyReadingSortOrder) {
                        Text("Recently Updated").tag("recentlyUpdated")
                        Text("Recently Added").tag("recentlyAdded")
                    }
                    .onChange(of: currentlyReadingSortOrder) { _, _ in
                        // Reload widgets when sort order changes
                        WidgetSync.libraryChanged(statuses: [2])
                    }
                    Text("Choose how your currently reading books are sorted in both the app and widgets. \"Recently Updated\" shows books you've most recently updated progress on. \"Recently Added\" shows books in the order you added them to your reading list.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                    
                    NavigationLink {
                        TipJarView()
                    } label: {
                        HStack {
                            Image(systemName: SupporterAccess.isUnlocked ? "checkmark.seal.fill" : "sparkles")
                                .foregroundColor(SupporterAccess.isUnlocked ? .green : .purple)
                            Text(SupporterAccess.isUnlocked ? "Softcover Supporter" : "Support Softcover")
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
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(isSaving || oauth.isWorking)
                }
            }
            .onAppear { loadExistingAndRefreshUsername() }
            .onDisappear { saveTask?.cancel() }
            .interactiveDismissDisabled(isSaving || oauth.isWorking)
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
            .confirmationDialog("Disconnect Hardcover?", isPresented: $showDisconnectConfirmation,
                                titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { disconnect() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Softcover's local account data and widget caches will be cleared.")
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
        apiKey = HardcoverConfig.usesOAuth ? "" : ((try? HardcoverLegacyAPIKeyStore.load())
            ?? AppGroup.defaults.string(forKey: "HardcoverAPIKey") ?? "")
        detectedUsername = AppGroup.defaults.string(forKey: "HardcoverUsername") ?? ""
    }

    @MainActor private func connectWithHardcover() {
        guard !isSaving, !oauth.isWorking else { return }
        saveError = nil
        saveTask = Task {
            do {
                let user = try await oauth.signIn()
                detectedUsername = user.username
                apiKey = ""
                onSaved?("")
                showSaved = true
            } catch {
                guard !Task.isCancelled,
                      (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin else { return }
                saveError = error.localizedDescription
            }
        }
    }

    @MainActor private func disconnect() {
        guard !isSaving, !oauth.isWorking else { return }
        saveError = nil
        saveTask = Task {
            do { try await oauth.disconnect() }
            catch { saveError = error.localizedDescription }
            detectedUsername = ""
            apiKey = ""
            onSaved?("")
        }
    }

    @MainActor private func save() {
        guard !isSaving else { return }
        let normalizedKey = HardcoverConfig.normalize(apiKey)
        guard !normalizedKey.isEmpty else { return }
        let previousAccount = HardcoverConfig.accountIdentifier
        isSaving = true
        saveError = nil
        saveTask = Task {
            defer { isSaving = false }
            do {
                let user = try await LibraryAPI.identity(
                    authorization: HardcoverConfig.headerValue(for: normalizedKey), fresh: true)
                try Task.checkCancellation()
                guard HardcoverConfig.accountIdentifier == previousAccount else { throw HardcoverNetworkError.accountChanged }
                // No account or cached data is replaced until the candidate token is verified.
                let previousOAuth = try? HardcoverOAuthCredentialsStore.load()
                try HardcoverLegacyAPIKeyStore.save(normalizedKey)
                try? HardcoverOAuthCredentialsStore.delete()
                AppGroup.defaults.removeObject(forKey: "HardcoverAPIKey")
                AppGroup.defaults.set(user.username, forKey: "HardcoverUsername")
                AppGroup.defaults.set(UUID().uuidString, forKey: "HardcoverAuthRevision")
                detectedUsername = user.username
                await HardcoverHTTP.shared.invalidate()
                LibrarySnapshot.clear()
                WidgetSync.accountChanged()
                NotificationCenter.default.post(name: .hardcoverAccountDidChange, object: nil)
                if let previousOAuth { try? await HardcoverOAuthAPI.revoke(previousOAuth) }
                onSaved?(normalizedKey)
                showSaved = true
            } catch {
                guard !Task.isCancelled else { return }
                saveError = error.localizedDescription
            }
        }
    }
}
