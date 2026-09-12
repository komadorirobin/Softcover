import AppIntents
import SwiftUI

enum QuoteColorTheme: String, AppEnum {
    case classic, paper, forest, ocean, rose

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Color Theme"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .classic: "Classic",
        .paper: "Paper",
        .forest: "Forest",
        .ocean: "Ocean",
        .rose: "Rose"
    ]

    var backgroundColor: Color {
        switch self {
        case .classic: Color(red: 0.1, green: 0.1, blue: 0.15)
        case .paper: Color(red: 0.98, green: 0.98, blue: 0.97)
        case .forest: Color(red: 0.08, green: 0.22, blue: 0.18)
        case .ocean: Color(red: 0.06, green: 0.22, blue: 0.32)
        case .rose: Color(red: 0.35, green: 0.12, blue: 0.20)
        }
    }

    var gradientEndColor: Color {
        switch self {
        case .classic: Color(red: 0.15, green: 0.1, blue: 0.2)
        case .paper: Color(red: 0.87, green: 0.91, blue: 0.90)
        case .forest: Color(red: 0.15, green: 0.34, blue: 0.25)
        case .ocean: Color(red: 0.10, green: 0.34, blue: 0.43)
        case .rose: Color(red: 0.48, green: 0.20, blue: 0.28)
        }
    }

    var textColor: Color {
        self == .paper ? Color(red: 0.12, green: 0.16, blue: 0.15) : .white
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
