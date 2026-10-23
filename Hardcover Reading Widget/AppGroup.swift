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

/// A verified StoreKit entitlement mirrored into the App Group so widgets can
/// render supporter-only appearances without making their own StoreKit calls.
enum SupporterAccess {
    // Product policy: this entitlement may gate cosmetic appearances only.
    // Reading, library, statistics, sharing, sync, and widget capabilities stay free.
    static let standardProductID = "komadori.softcover.supporter.lifetime"
    static let generousProductID = "komadori.softcover.supporter.generous"
    static let productIDs = [standardProductID, generousProductID]
    static let entitlementKey = "SoftcoverSupporterLifetimeUnlocked"

    static func grantsEntitlement(_ productID: String) -> Bool {
        productIDs.contains(productID)
    }

    static var isUnlocked: Bool {
        get { AppGroup.defaults.bool(forKey: entitlementKey) }
        set { AppGroup.defaults.set(newValue, forKey: entitlementKey) }
    }
}
