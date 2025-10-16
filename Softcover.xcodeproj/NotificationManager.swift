import Foundation
import UserNotifications
import SwiftUI

enum NotificationManager {
    private static let center = UNUserNotificationCenter.current()
    private static let enabledKey = "ReleaseNotificationsEnabled"
    private static let categoryId = "UPCOMING_RELEASE_CATEGORY"
    private static let mutedKey = "MutedReleaseIDs" // [Int] av tystade releaseId
    
    static var isEnabled: Bool {
        get { AppGroup.defaults.bool(forKey: enabledKey) }
        set { AppGroup.defaults.set(newValue, forKey: enabledKey) }
    }
    
    // Tystade release-ID:n
    static var mutedReleaseIds: Set<Int> {
        get {
            let arr = AppGroup.defaults.array(forKey: mutedKey) as? [Int] ?? []
            return Set(arr)
        }
        set {
            AppGroup.defaults.set(Array(newValue), forKey: mutedKey)
        }
    }
    
    static func isMuted(releaseId: Int) -> Bool {
        mutedReleaseIds.contains(releaseId)
    }
    
    static func setMuted(_ muted: Bool, for releaseId: Int) {
        var set = mutedReleaseIds
        if muted {
            set.insert(releaseId)
            // Ta bort väntande notis för denna release om den finns
            Task {
                await removeNotification(for: releaseId)
            }
        } else {
            set.remove(releaseId)
        }
        mutedReleaseIds = set
    }
    
    // Be om tillstånd. Returnerar true om tillåtet.
    static func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                isEnabled = granted
            }
            // Registrera kategori (om vi vill lägga till actions i framtiden)
            let category = UNNotificationCategory(identifier: categoryId, actions: [], intentIdentifiers: [], options: [])
            center.setNotificationCategories([category])
            return granted
        } catch {
            await MainActor.run { isEnabled = false }
            return false
        }
    }
    
    // Schemalägg notiser för givna släpp. Rensar gamla notiser för släpp som inte längre finns eller som är tystade.
    static func scheduleReleaseNotifications(for releases: [HardcoverService.UpcomingRelease]) async {
        guard isEnabled else { return }
        
        // Tillåt endast framtida (inkl. idag) släpp och inte tystade
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let muted = mutedReleaseIds
        let upcoming = releases.filter {
            cal.startOfDay(for: $0.releaseDate) >= today && !muted.contains($0.id)
        }
        
        // Hämta väntande
        let pending = await center.pendingNotificationRequests()
        let desiredIds = Set(upcoming.map { identifier(for: $0.id) })
        let pendingIds = Set(pending.map { $0.identifier })
        
        // Ta bort alla som inte längre är önskade (inkl. tystade och borttagna)
        let toRemove = pendingIds.subtracting(desiredIds).filter { $0.hasPrefix("release-") }
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toRemove))
        }
        
        // Lägg bara till de som saknas
        let toAdd = upcoming.filter { !pendingIds.contains(identifier(for: $0.id)) }
        for item in toAdd {
            await scheduleReleaseNotification(for: item)
        }
    }
    
    // Schemalägg en enda release-notis (om aktiverat och ej tystad och datum giltigt)
    static func scheduleReleaseNotification(for release: HardcoverService.UpcomingRelease) async {
        guard isEnabled else { return }
        guard !isMuted(releaseId: release.id) else { return }
        
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard cal.startOfDay(for: release.releaseDate) >= today else { return }
        
        let id = identifier(for: release.id)
        let triggerDate = makeTriggerDate(for: release.releaseDate)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Book releases today", comment: "Notification title for release")
        content.body = String(format: NSLocalizedString("“%@” by %@ is out today.", comment: "Notification body for release"), release.title, release.author)
        content.sound = .default
        content.categoryIdentifier = categoryId
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            // Ignorera individuella fel
        }
    }
    
    // Ta bort väntande notis för specifik release
    static func removeNotification(for releaseId: Int) async {
        let id = identifier(for: releaseId)
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
    
    // Avaktivera: rensa alla relaterade släppnotiser
    static func clearAllReleaseNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map { $0.identifier }
            .filter { $0.hasPrefix("release-") }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
    
    // MARK: - Helpers
    private static func identifier(for releaseId: Int) -> String {
        "release-\(releaseId)"
    }
    
    // Standard: 08:00 lokal tid på releasedagen. Om tiden redan passerat och det är idag, skjut 3 min fram.
    private static func makeTriggerDate(for releaseDate: Date) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: releaseDate)
        if let eightAM = cal.date(bySettingHour: 8, minute: 0, second: 0, of: start) {
            let now = Date()
            if cal.isDate(now, inSameDayAs: releaseDate), eightAM <= now {
                return now.addingTimeInterval(3 * 60)
            }
            return eightAM
        }
        // Fallback: start-of-day + 8h
        return start.addingTimeInterval(8 * 3600)
    }
}
