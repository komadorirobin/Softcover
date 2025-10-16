import Foundation
import UserNotifications
import SwiftUI

enum NotificationManager {
    private static let center = UNUserNotificationCenter.current()
    private static let enabledKey = "ReleaseNotificationsEnabled"
    private static let categoryId = "UPCOMING_RELEASE_CATEGORY"
    private static let mutedKey = "MutedReleaseIDs" // [Int] of muted release IDs
    // New: keep track of which release/date we already notified today to avoid re-scheduling same day
    // We store identifiers in the same format we schedule with: "release-<id>-<yyyyMMdd>"
    private static let notifiedKey = "ReleaseNotifiedIdentifiers"

    static var isEnabled: Bool {
        get { AppGroup.defaults.bool(forKey: enabledKey) }
        set { AppGroup.defaults.set(newValue, forKey: enabledKey) }
    }
    
    // Muted release IDs
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
            // Remove pending notifications for this release (all date variants)
            Task {
                await removeNotifications(forReleaseId: releaseId)
            }
        } else {
            set.remove(releaseId)
        }
        mutedReleaseIds = set
    }
    
    // Request authorization. Returns true if granted.
    static func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                isEnabled = granted
            }
            // Register category (for potential future actions)
            let category = UNNotificationCategory(identifier: categoryId, actions: [], intentIdentifiers: [], options: [])
            center.setNotificationCategories([category])
            return granted
        } catch {
            await MainActor.run { isEnabled = false }
            return false
        }
    }
    
    // Schedule notifications for given releases. Cleans up old or muted ones.
    static func scheduleReleaseNotifications(for releases: [HardcoverService.UpcomingRelease]) async {
        guard isEnabled else { return }
        
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let muted = mutedReleaseIds
        let upcoming = releases.filter {
            cal.startOfDay(for: $0.releaseDate) >= today && !muted.contains($0.id)
        }
        
        // Fetch pending
        let pending = await center.pendingNotificationRequests()
        let pendingIds = Set(pending.map { $0.identifier })
        
        // Build desired identifiers (date-stable)
        let desiredIds: Set<String> = Set(upcoming.map { identifier(for: $0.id, on: $0.releaseDate) })
        
        // Remove any that are no longer desired (including muted and removed), but only ours
        let toRemove = pendingIds.subtracting(desiredIds).filter { $0.hasPrefix("release-") }
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toRemove))
        }
        
        // Load already-notified set (avoid re-scheduling same release+date after it's been delivered or already scheduled post-09:00)
        var alreadyNotified = notifiedIdentifiers()
        
        // Add only those missing and not already-notified for that date
        for item in upcoming {
            let id = identifier(for: item.id, on: item.releaseDate)
            if pendingIds.contains(id) { continue }
            
            // If it's release day and we've already notified/scheduled once today, skip
            if cal.isDate(item.releaseDate, inSameDayAs: Date()), alreadyNotified.contains(id) {
                continue
            }
            await scheduleReleaseNotification(for: item)
            
            // If we scheduled after 09:00 for today (i.e. immediate catch-up), mark as notified to avoid duplicates later the same day.
            if cal.isDate(item.releaseDate, inSameDayAs: Date()) {
                alreadyNotified.insert(id)
                saveNotifiedIdentifiers(alreadyNotified)
            }
        }
    }
    
    // Schedule a single release notification (if enabled, not muted, and date valid)
    static func scheduleReleaseNotification(for release: HardcoverService.UpcomingRelease) async {
        guard isEnabled else { return }
        guard !isMuted(releaseId: release.id) else { return }
        
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard cal.startOfDay(for: release.releaseDate) >= today else { return }
        
        let id = identifier(for: release.id, on: release.releaseDate)
        
        // If already pending with this exact id, do nothing
        let pending = await center.pendingNotificationRequests()
        if pending.contains(where: { $0.identifier == id }) { return }
        
        // If it is release day and we've already notified/scheduled today, do nothing
        var alreadyNotified = notifiedIdentifiers()
        if cal.isDate(release.releaseDate, inSameDayAs: Date()), alreadyNotified.contains(id) {
            return
        }
        
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
            // If we scheduled on release day (likely after 09:00 catch-up), mark as notified to prevent further same-day schedules
            if cal.isDate(release.releaseDate, inSameDayAs: Date()) {
                alreadyNotified.insert(id)
                saveNotifiedIdentifiers(alreadyNotified)
            }
        } catch {
            // Ignore per-notification errors
        }
    }
    
    // Remove pending notifications for a specific release (all date variants)
    static func removeNotifications(forReleaseId releaseId: Int) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map { $0.identifier }
            .filter { $0.hasPrefix("release-\(releaseId)-") }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        // Also clear any “already-notified” marks for this release (all dates)
        var notified = notifiedIdentifiers()
        let before = notified.count
        notified = Set(notified.filter { !$0.hasPrefix("release-\(releaseId)-") })
        if notified.count != before {
            saveNotifiedIdentifiers(notified)
        }
    }
    
    // Backwards compatibility helper (old call sites)
    static func removeNotification(for releaseId: Int) async {
        await removeNotifications(forReleaseId: releaseId)
    }
    
    // Deactivate: clear all related release notifications
    static func clearAllReleaseNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map { $0.identifier }
            .filter { $0.hasPrefix("release-") }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        // Clear “already-notified” memory
        saveNotifiedIdentifiers([])
    }
    
    // MARK: - Helpers
    // Identifier now includes date so one notification per release per day
    private static func identifier(for releaseId: Int, on date: Date) -> String {
        "release-\(releaseId)-\(yyyyMMdd(from: date))"
    }
    
    // Default: 09:00 local time on the release day. If it's today and the time has passed, push 3 minutes ahead.
    private static func makeTriggerDate(for releaseDate: Date) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: releaseDate)
        if let nineAM = cal.date(bySettingHour: 9, minute: 0, second: 0, of: start) {
            let now = Date()
            if cal.isDate(now, inSameDayAs: releaseDate), nineAM <= now {
                return now.addingTimeInterval(3 * 60)
            }
            return nineAM
        }
        // Fallback: start-of-day + 9h
        return start.addingTimeInterval(9 * 3600)
    }
    
    private static func yyyyMMdd(from date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }
    
    // Persist and load “already-notified” identifiers for the day
    private static func notifiedIdentifiers() -> Set<String> {
        let arr = AppGroup.defaults.array(forKey: notifiedKey) as? [String] ?? []
        // Garbage collect past days occasionally: keep only today-or-future entries
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let filtered = arr.filter { id in
            // id format: release-<id>-<yyyyMMdd>
            guard let day = id.split(separator: "-").last.map(String.init) else { return false }
            return parseYYYYMMDD(day).map { cal.startOfDay(for: $0) >= today } ?? false
        }
        if filtered.count != arr.count {
            AppGroup.defaults.set(filtered, forKey: notifiedKey)
        }
        return Set(filtered)
    }
    
    private static func saveNotifiedIdentifiers(_ set: Set<String>) {
        AppGroup.defaults.set(Array(set), forKey: notifiedKey)
    }
    
    private static func parseYYYYMMDD(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f.date(from: s)
    }
}
