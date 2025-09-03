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
    
    private var preferredScheme: ColorScheme? {
        switch appearancePref {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(preferredScheme)
        }
    }
}
