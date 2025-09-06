import Foundation
import UserNotifications
import SwiftUI

enum NotificationManager {
    private static let center = UNUserNotificationCenter.current()
    private static let enabledKey = "ReleaseNotificationsEnabled"
    private static let categoryId = "UPCOMING_RELEASE_CATEGORY"
    private static let mutedKey = "MutedReleaseIDs" // [Int] of muted release IDs
    
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
            // Remove pending notification for this release if any
            Task {
                await removeNotification(for: releaseId)
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
        let desiredIds = Set(upcoming.map { identifier(for: $0.id) })
        let pendingIds = Set(pending.map { $0.identifier })
        
        // Remove any that are no longer desired (including muted and removed)
        let toRemove = pendingIds.subtracting(desiredIds).filter { $0.hasPrefix("release-") }
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toRemove))
        }
        
        // Add only those missing
        let toAdd = upcoming.filter { !pendingIds.contains(identifier(for: $0.id)) }
        for item in toAdd {
            await scheduleReleaseNotification(for: item)
        }
    }
    
    // Schedule a single release notification (if enabled, not muted, and date valid)
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
            // Ignore per-notification errors
        }
    }
    
    // Remove pending notification for a specific release
    static func removeNotification(for releaseId: Int) async {
        let id = identifier(for: releaseId)
        center.removePendingNotificationRequests(withIdentifiers: [id])
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
    }
    
    // MARK: - Helpers
    private static func identifier(for releaseId: Int) -> String {
        "release-\(releaseId)"
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
}
