import Foundation

/// Delade UserDefaults via App Group så att både app och widget kan läsa API-nyckeln.
/// VIKTIGT: Uppdatera identifier nedan till din riktiga App Group ID och lägg till den i både app- och widget-entitlements.
enum AppGroup {
    // Se till att denna sträng matchar exakt vad som är ibockat i båda target:arnas App Groups.
    static let identifier = "group.komadori.Hardcover-Reading-Widget"
    
    // Delade UserDefaults. Om entitlements inte är rätt konfigurerade faller detta tillbaka till .standard.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
    
    // Diagnostik: true om vi fick en giltig suite (inte standard).
    static var isUsingSuite: Bool {
        return UserDefaults(suiteName: identifier) != nil
    }
    
    // Diagnostik: skriv ut status för enklare felsökning.
    static func logSuiteStatus(context: String) {
        let ok = isUsingSuite
        print("🧪 AppGroup[\(context)]: identifier=\(identifier), usingSuite=\(ok)")
    }
}
