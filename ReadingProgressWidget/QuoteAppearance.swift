import AppIntents
import SwiftUI

enum QuoteColorTheme: String, AppEnum {
    case classic, paper, forest, ocean, rose
    case aurora, sunset, ink, lavender, ember, moss, moonlight, parchment

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Color Theme"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .classic: "Classic",
        .paper: "Paper",
        .forest: "Forest",
        .ocean: "Ocean",
        .rose: "Rose",
        .aurora: "Aurora · Supporter",
        .sunset: "Sunset · Supporter",
        .ink: "Ink · Supporter",
        .lavender: "Lavender · Supporter",
        .ember: "Ember · Supporter",
        .moss: "Moss · Supporter",
        .moonlight: "Moonlight · Supporter",
        .parchment: "Parchment · Supporter"
    ]

    var requiresSupporter: Bool {
        switch self {
        case .aurora, .sunset, .ink, .lavender, .ember, .moss, .moonlight, .parchment: true
        default: false
        }
    }

    var backgroundColor: Color {
        switch self {
        case .classic: Color(red: 0.1, green: 0.1, blue: 0.15)
        case .paper: Color(red: 0.98, green: 0.98, blue: 0.97)
        case .forest: Color(red: 0.08, green: 0.22, blue: 0.18)
        case .ocean: Color(red: 0.06, green: 0.22, blue: 0.32)
        case .rose: Color(red: 0.35, green: 0.12, blue: 0.20)
        case .aurora: Color(red: 0.08, green: 0.20, blue: 0.22)
        case .sunset: Color(red: 0.40, green: 0.12, blue: 0.22)
        case .ink: Color(red: 0.04, green: 0.05, blue: 0.09)
        case .lavender: Color(red: 0.21, green: 0.13, blue: 0.38)
        case .ember: Color(red: 0.31, green: 0.07, blue: 0.08)
        case .moss: Color(red: 0.10, green: 0.19, blue: 0.10)
        case .moonlight: Color(red: 0.06, green: 0.10, blue: 0.20)
        case .parchment: Color(red: 0.95, green: 0.86, blue: 0.66)
        }
    }

    var gradientEndColor: Color {
        switch self {
        case .classic: Color(red: 0.15, green: 0.1, blue: 0.2)
        case .paper: Color(red: 0.87, green: 0.91, blue: 0.90)
        case .forest: Color(red: 0.15, green: 0.34, blue: 0.25)
        case .ocean: Color(red: 0.10, green: 0.34, blue: 0.43)
        case .rose: Color(red: 0.48, green: 0.20, blue: 0.28)
        case .aurora: Color(red: 0.25, green: 0.48, blue: 0.42)
        case .sunset: Color(red: 0.95, green: 0.42, blue: 0.20)
        case .ink: Color(red: 0.24, green: 0.20, blue: 0.36)
        case .lavender: Color(red: 0.62, green: 0.38, blue: 0.76)
        case .ember: Color(red: 0.87, green: 0.36, blue: 0.10)
        case .moss: Color(red: 0.42, green: 0.48, blue: 0.18)
        case .moonlight: Color(red: 0.34, green: 0.47, blue: 0.70)
        case .parchment: Color(red: 0.73, green: 0.49, blue: 0.27)
        }
    }

    var textColor: Color {
        switch self {
        case .paper, .parchment: Color(red: 0.12, green: 0.16, blue: 0.15)
        default: .white
        }
    }
}

enum QuoteFont: String, AppEnum {
    case system, serif, rounded, monospaced

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Font"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .system: "System",
        .serif: "Serif",
        .rounded: "Rounded",
        .monospaced: "Monospaced"
    ]

    var design: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }
}

enum QuoteBackground: String, AppEnum {
    case gradient, solid

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Background"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .gradient: "Gradient",
        .solid: "Solid"
    ]
}
