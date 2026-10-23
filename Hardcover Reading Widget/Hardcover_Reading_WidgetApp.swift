//
//  Hardcover_Reading_WidgetApp.swift
//  Hardcover Reading Widget
//
//  Created by Robin Bolinsson on 2025-08-22.
//

import SwiftUI

@main
struct Hardcover_Reading_WidgetApp: App {
    @AppStorage("AppearancePreference", store: AppGroup.defaults) private var appearancePref: String = "system"
    @AppStorage("ColorPalette", store: AppGroup.defaults) private var colorPalette: String = "vellum"
    @AppStorage(SupporterAccess.entitlementKey, store: AppGroup.defaults) private var isSupporter = false
    
    private var preferredScheme: ColorScheme? {
        switch appearancePref {
        case "light": return .light
        case "dark", "dim": return .dark
        default: return nil
        }
    }

    private var accent: Color {
        SoftcoverPalette.resolvedAccent(for: colorPalette, isSupporter: isSupporter)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(preferredScheme)
                .tint(accent)
        }
    }
}
