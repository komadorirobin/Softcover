import Foundation
import Network
import Combine
import SwiftUI

enum OfflineWriteOperation: Codable, Sendable {
    case progress(userBookID: Int, editionID: Int?, units: Int, audiobook: Bool, actionAt: Date?)
    case validatedProgress(ReadingProgressWriteRequest)
    case status(userBookID: Int, statusID: Int, userDate: String?)
    case delete(userBookID: Int)
    case add(bookID: Int, editionID: Int?, statusID: Int)
    case finish(userBookID: Int, editionID: Int?, totalPages: Int?, currentPage: Int?, actionAt: Date?)
    case complete(bookID: Int, userBookID: Int?, editionID: Int?, targetUnits: Int,
                  audiobook: Bool, totalPages: Int?, currentPage: Int?, actionAt: Date?,
                  ratingChanged: Bool, rating: Double?, review: String?, spoilers: Bool)
    case rating(userBookID: Int, value: Double?)
    case review(userBookID: Int, text: String, spoilers: Bool)
    case own(editionID: Int, book: BookProgress)
    case unown(listBookID: Int)
}

@MainActor
final class OfflineWriteQueue: ObservableObject {
    struct Item: Codable, Identifiable, Sendable {
        let id: UUID
        let account: String
        let createdAt: Date
        let operation: OfflineWriteOperation
        var attempts: Int?
        var nextAttemptAt: Date?

        var attemptCount: Int { attempts ?? 0 }
    }

    static let shared = OfflineWriteQueue()
    @Published private(set) var isOffline = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var failedCount = 0
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Softcover.NetworkMonitor")
    private var items: [Item] = []
    private var draining = false
    private var retryTask: Task<Void, Never>?
    private let storageKey = "OfflineWriteQueue.v1"
    private let maximumAttempts = 3

    private init() {
        items = AppGroup.defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
        updateCounts()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isOffline = path.status != .satisfied
                if !self.isOffline { await self.drain() }
            }
        }
        monitor.start(queue: queue)
    }

    func perform(_ operation: OfflineWriteOperation) async -> Bool {
        if isOffline { enqueue(operation); return true }
        if await performDirect(operation) { return true }
        if isOffline { enqueue(operation); return true }
        // Completion is deliberately replay-safe: every step is an idempotent
        // update and finishBook de-duplicates the reading-history entry. Queue it
        // after a transient-looking failure even if NWPath has not caught up yet.
        if case .complete = operation { enqueue(operation); return true }
        return false
    }

    func performProgress(_ request: ReadingProgressWriteRequest, fallback: BookProgress) async throws -> BookProgress {
        if isOffline {
            try ReadingProgressWriter.validate(request, against: fallback)
            enqueue(.validatedProgress(request))
            return fallback.withProgress(request.units)
        }
        do { return try await ReadingProgressWriter.write(request) }
        catch {
            if isOffline {
                try ReadingProgressWriter.validate(request, against: fallback)
                enqueue(.validatedProgress(request))
                return fallback.withProgress(request.units)
            }
            throw error
        }
    }

    func drain() async {
        guard !draining, !isOffline else { return }
        retryTask?.cancel()
        retryTask = nil
        updateCounts()
        draining = true; defer { draining = false }
        let account = HardcoverConfig.accountIdentifier
        let ids = items.filter { $0.account == account }.map(\.id)
        for id in ids {
            if isOffline { break }
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            if items[index].attemptCount >= maximumAttempts { continue }
            if let next = items[index].nextAttemptAt, next > Date() {
                scheduleRetry(at: next)
                break
            }
            let succeeded = await performDirect(items[index].operation)
            if succeeded {
                items.remove(at: index)
                persist()
                continue
            }
            guard let failedIndex = items.firstIndex(where: { $0.id == id }) else { continue }
            let attempts = items[failedIndex].attemptCount + 1
            items[failedIndex].attempts = attempts
            items[failedIndex].nextAttemptAt = attempts < maximumAttempts
                ? Date().addingTimeInterval(pow(3, Double(attempts - 1))) : nil
            persist()
            if attempts < maximumAttempts {
                scheduleRetry(at: items[failedIndex].nextAttemptAt ?? Date())
                break
            }
        }
    }

    func accountChanged() async {
        retryTask?.cancel(); retryTask = nil
        updateCounts()
        if !isOffline { await drain() }
    }

    func retryFailed() async {
        for index in items.indices where items[index].account == HardcoverConfig.accountIdentifier {
            items[index].attempts = nil
            items[index].nextAttemptAt = nil
        }
        persist()
        if !isOffline { await drain() }
    }

    func discardPendingForCurrentAccount() {
        items.removeAll { $0.account == HardcoverConfig.accountIdentifier }
        persist()
    }

    private var currentItems: [Item] { items.filter { $0.account == HardcoverConfig.accountIdentifier } }
    private func enqueue(_ operation: OfflineWriteOperation) {
        items.append(Item(id: UUID(), account: HardcoverConfig.accountIdentifier, createdAt: Date(),
                          operation: operation, attempts: nil, nextAttemptAt: nil))
        persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(items) { AppGroup.defaults.set(data, forKey: storageKey) }
        updateCounts()
    }
    private func updateCounts() {
        let current = currentItems
        pendingCount = current.filter { $0.attemptCount < maximumAttempts }.count
        failedCount = current.count - pendingCount
    }
    private func scheduleRetry(at date: Date) {
        retryTask?.cancel()
        let delay = max(0.1, date.timeIntervalSinceNow)
        retryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            await self?.drain()
        }
    }

    private func performDirect(_ operation: OfflineWriteOperation) async -> Bool {
        switch operation {
        case let .progress(id, edition, units, audiobook, actionAt):
            return await HardcoverService.updateProgress(userBookId: id, editionId: edition, page: units, isAudiobook: audiobook, actionAt: actionAt)
        case let .validatedProgress(request):
            do { _ = try await ReadingProgressWriter.write(request); return true }
            catch { return false }
        case let .status(id, status, userDate):
            return await HardcoverService.updateUserBookStatus(userBookId: id, statusId: status, userDate: userDate)
        case let .delete(id):
            return await HardcoverService.deleteUserBook(userBookId: id)
        case let .add(bookID, editionID, statusID):
            if statusID == 2 { return await HardcoverService.addBookToCurrentlyReading(bookId: bookID, editionId: editionID) }
            if statusID == 1 { return await HardcoverService.addBookToWantToRead(bookId: bookID, editionId: editionID) }
            guard await HardcoverService.addBookToWantToRead(bookId: bookID, editionId: editionID),
                  let own = try? await LibraryAPI.ownBook(bookID: bookID, fresh: true), let id = own.userBookId else { return false }
            return await HardcoverService.updateUserBookStatus(userBookId: id, statusId: statusID)
        case let .finish(id, edition, pages, current, actionAt):
            return await HardcoverService.finishBook(userBookId: id, editionId: edition, totalPages: pages, currentPage: current, rating: nil, actionAt: actionAt)
        case let .complete(bookID, knownUserBookID, editionID, targetUnits, audiobook, pages, current, actionAt,
                           ratingChanged, rating, review, spoilers):
            var own = try? await LibraryAPI.ownBook(bookID: bookID, fresh: true)
            if own == nil {
                guard await HardcoverService.addBookToWantToRead(bookId: bookID, editionId: editionID) else { return false }
                own = try? await LibraryAPI.ownBook(bookID: bookID, fresh: true)
            }
            guard let own, let id = own.userBookId,
                  knownUserBookID == nil || knownUserBookID == id else { return false }
            // A previous attempt may have completed the read and then failed while
            // saving the rating or review. Do not finish it again on a later day.
            if own.statusId != 3 {
                if targetUnits > own.currentUnits,
                   !(await HardcoverService.updateProgress(userBookId: id, editionId: own.editionId ?? editionID,
                        page: targetUnits, isAudiobook: audiobook, actionAt: actionAt)) { return false }
                guard await HardcoverService.finishBook(userBookId: id, editionId: own.editionId ?? editionID,
                    totalPages: pages, currentPage: current, rating: nil, actionAt: actionAt) else { return false }
            }
            if ratingChanged, !(await HardcoverService.updateUserBookRating(userBookId: id, rating: rating)) { return false }
            if let review, !review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !(await HardcoverService.publishReview(userBookId: id, text: review, hasSpoilers: spoilers)) { return false }
            return true
        case let .rating(id, value):
            return await HardcoverService.updateUserBookRating(userBookId: id, rating: value)
        case let .review(id, text, spoilers):
            return await HardcoverService.publishReview(userBookId: id, text: text, hasSpoilers: spoilers)
        case let .own(editionID, book):
            return (try? await OwnedEditionsService.mark(editionID: editionID, fallbackBook: book)) != nil
        case let .unown(listBookID):
            do { try await OwnedEditionsService.remove(listBookID: listBookID); return true }
            catch { return false }
        }
    }
}

struct OfflineQueueBanner: View {
    @ObservedObject private var queue = OfflineWriteQueue.shared
    var body: some View {
        if queue.isOffline || queue.pendingCount > 0 || queue.failedCount > 0 {
            HStack(spacing: 8) {
                Image(systemName: queue.isOffline ? "wifi.slash" : queue.failedCount > 0 ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath")
                Text(queue.isOffline ? "Offline — changes will sync later" : queue.failedCount > 0
                     ? "\(queue.failedCount) change\(queue.failedCount == 1 ? "" : "s") need attention"
                     : "Syncing \(queue.pendingCount) change\(queue.pendingCount == 1 ? "" : "s")…")
                    .font(.caption.weight(.medium))
                Spacer()
                if !queue.isOffline && queue.failedCount > 0 {
                    Button("Retry") { Task { await queue.retryFailed() } }.font(.caption.weight(.semibold))
                } else if !queue.isOffline && queue.pendingCount > 0 {
                    Button("Sync") { Task { await queue.drain() } }.font(.caption.weight(.semibold))
                }
            }.padding(.horizontal, 12).padding(.vertical, 8).background(.regularMaterial)
        }
    }
}
