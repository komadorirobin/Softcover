import SwiftUI
import UIKit

enum SoftcoverPalette: String, CaseIterable, Identifiable {
    case vellum, ink, foxed, sea
    case aurora, sunset, moss, lavender

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .vellum: "Vellum"
        case .ink: "Ink"
        case .foxed: "Foxed"
        case .sea: "Sea"
        case .aurora: "Aurora"
        case .sunset: "Sunset"
        case .moss: "Moss"
        case .lavender: "Lavender"
        }
    }

    var isSupporterOnly: Bool {
        switch self {
        case .aurora, .sunset, .moss, .lavender: true
        default: false
        }
    }

    var accent: Color {
        switch self {
        case .vellum: Color(red: 0.48, green: 0.38, blue: 0.72)
        case .ink: Color(red: 0.25, green: 0.47, blue: 0.82)
        case .foxed: Color(red: 0.72, green: 0.35, blue: 0.20)
        case .sea: Color(red: 0.12, green: 0.55, blue: 0.54)
        case .aurora: Color(red: 0.22, green: 0.72, blue: 0.63)
        case .sunset: Color(red: 0.91, green: 0.30, blue: 0.39)
        case .moss: Color(red: 0.32, green: 0.55, blue: 0.29)
        case .lavender: Color(red: 0.62, green: 0.43, blue: 0.88)
        }
    }

    var previewEnd: Color {
        switch self {
        case .vellum: Color(red: 0.71, green: 0.63, blue: 0.88)
        case .ink: Color(red: 0.10, green: 0.17, blue: 0.32)
        case .foxed: Color(red: 0.91, green: 0.62, blue: 0.34)
        case .sea: Color(red: 0.15, green: 0.35, blue: 0.58)
        case .aurora: Color(red: 0.42, green: 0.30, blue: 0.88)
        case .sunset: Color(red: 0.98, green: 0.63, blue: 0.24)
        case .moss: Color(red: 0.71, green: 0.64, blue: 0.30)
        case .lavender: Color(red: 0.91, green: 0.60, blue: 0.80)
        }
    }

    static func resolvedAccent(for rawValue: String, isSupporter: Bool) -> Color {
        let palette = SoftcoverPalette(rawValue: rawValue) ?? .vellum
        return palette.isSupporterOnly && !isSupporter ? SoftcoverPalette.vellum.accent : palette.accent
    }
}

private enum SoftcoverAppIcon: String, CaseIterable, Identifiable {
    case classic, aurora, sunset, ink, vellum

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .classic: "Classic"
        case .aurora: "Aurora"
        case .sunset: "Sunset"
        case .ink: "Ink"
        case .vellum: "Vellum"
        }
    }

    var alternateName: String? {
        switch self {
        case .classic: nil
        case .aurora: "AppIconAurora"
        case .sunset: "AppIconSunset"
        case .ink: "AppIconInk"
        case .vellum: "AppIconVellum"
        }
    }

    var previewAsset: String {
        switch self {
        case .classic: "AppIconClassicPreview"
        case .aurora: "AppIconAuroraPreview"
        case .sunset: "AppIconSunsetPreview"
        case .ink: "AppIconInkPreview"
        case .vellum: "AppIconVellumPreview"
        }
    }

    var isSupporterOnly: Bool { self != .classic }
}

struct AppearanceSettingsView: View {
    @AppStorage("AppearancePreference", store: AppGroup.defaults) private var appearancePreference = "system"
    @AppStorage("ColorPalette", store: AppGroup.defaults) private var colorPalette = "vellum"
    @AppStorage(SupporterAccess.entitlementKey, store: AppGroup.defaults) private var isSupporter = false
    @State private var selectedIconName = UIApplication.shared.alternateIconName
    @State private var isChangingIcon = false
    @State private var iconError: String?
    @State private var showingSupporterPack = false

    private let paletteColumns = [GridItem(.adaptive(minimum: 72), spacing: 12)]
    private let iconColumns = [GridItem(.adaptive(minimum: 104), spacing: 14)]

    var body: some View {
        Form {
            Section("App appearance") {
                Picker("Theme", selection: $appearancePreference) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("Dim").tag("dim")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Accent palette")
                        .font(.subheadline.weight(.semibold))

                    LazyVGrid(columns: paletteColumns, spacing: 14) {
                        ForEach(SoftcoverPalette.allCases) { palette in
                            Button {
                                select(palette)
                            } label: {
                                VStack(spacing: 7) {
                                    ZStack(alignment: .topTrailing) {
                                        Circle()
                                            .fill(LinearGradient(
                                                colors: [palette.accent, palette.previewEnd],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                            .frame(width: 48, height: 48)
                                            .overlay {
                                                if colorPalette == palette.rawValue {
                                                    Image(systemName: "checkmark")
                                                        .font(.headline.weight(.bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }

                                        if palette.isSupporterOnly && !isSupporter {
                                            Image(systemName: "lock.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.white)
                                                .padding(5)
                                                .background(.black.opacity(0.65), in: Circle())
                                                .offset(x: 5, y: -5)
                                        }
                                    }

                                    Text(palette.title)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(colorPalette == palette.rawValue ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                if UIApplication.shared.supportsAlternateIcons {
                    LazyVGrid(columns: iconColumns, spacing: 16) {
                        ForEach(SoftcoverAppIcon.allCases) { icon in
                            Button {
                                select(icon)
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(icon.previewAsset)
                                            .resizable()
                                            .scaledToFit()
                                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                            .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
                                            .overlay {
                                                if selectedIconName == icon.alternateName {
                                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                        .stroke(.tint, lineWidth: 4)
                                                }
                                            }

                                        if icon.isSupporterOnly && !isSupporter {
                                            Image(systemName: "lock.fill")
                                                .font(.caption)
                                                .foregroundStyle(.white)
                                                .padding(7)
                                                .background(.black.opacity(0.72), in: Circle())
                                                .offset(x: 5, y: -5)
                                        }
                                    }

                                    HStack(spacing: 5) {
                                        Text(icon.title)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if isChangingIcon && selectedIconName == icon.alternateName {
                                            ProgressView().controlSize(.mini)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isChangingIcon)
                            .accessibilityAddTraits(selectedIconName == icon.alternateName ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                } else {
                    Text("Alternate app icons aren't available on this device.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("App icon")
            } footer: {
                Text("Classic is included for everyone. The four alternate icons are part of the cosmetic Supporter Collection.")
            }

            if !isSupporter {
                Section {
                    Button {
                        showingSupporterPack = true
                    } label: {
                        Label("Explore the Supporter Collection", systemImage: "sparkles")
                    }
                } footer: {
                    Text("All reading, library, statistics, sharing, and widget features remain free.")
                }
            }
        }
        .navigationTitle("Appearance")
        .sheet(isPresented: $showingSupporterPack) {
            NavigationStack {
                TipJarView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingSupporterPack = false }
                        }
                    }
            }
        }
        .alert("Couldn't change the app icon", isPresented: Binding(
            get: { iconError != nil },
            set: { if !$0 { iconError = nil } }
        )) {
            Button("OK", role: .cancel) { iconError = nil }
        } message: {
            Text(iconError ?? String(localized: "Please try again later."))
        }
    }

    private func select(_ palette: SoftcoverPalette) {
        guard !palette.isSupporterOnly || isSupporter else {
            showingSupporterPack = true
            return
        }
        colorPalette = palette.rawValue
    }

    private func select(_ icon: SoftcoverAppIcon) {
        guard !icon.isSupporterOnly || isSupporter else {
            showingSupporterPack = true
            return
        }
        guard selectedIconName != icon.alternateName else { return }

        isChangingIcon = true
        UIApplication.shared.setAlternateIconName(icon.alternateName) { error in
            Task { @MainActor in
                isChangingIcon = false
                if let error {
                    iconError = error.localizedDescription
                } else {
                    selectedIconName = icon.alternateName
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
