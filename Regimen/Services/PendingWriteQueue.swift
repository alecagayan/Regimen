//
//  PendingWriteQueue.swift
//  Regimen
//

import Foundation
import os

/// A durable outbox for check-offs that couldn't reach Supabase.
///
/// Check-offs used to be written with `try? await UsageLogService.insert`:
/// the local array updated, the checkmark appeared, and a failed write was
/// discarded in silence. The next `loadAll` -- which now runs on every
/// foreground -- would then refetch from the server and the check-off would
/// quietly disappear. The user saw a tick, believed their streak was safe,
/// and lost it to a dropped request they were never told about.
///
/// So writes that fail are parked here, on disk, and retried on the next
/// load. `AppData.loadAll` also re-applies anything still queued on top of
/// freshly fetched rows, so pending work stays visible in the UI instead of
/// being erased by the very fetch that was supposed to confirm it.
///
/// Scope was originally just usage logs, on the argument that everything
/// else is a rare, deliberate, foreground action whose failure could simply
/// be reported. That argument doesn't survive contact with a phone on a
/// train: adding a product, logging a reaction the day it happens, or
/// marking a bottle empty are all things people do exactly where the
/// signal isn't, and "Something Didn't Save" means retyping it later --
/// assuming they remember. Everything the user can author now queues.
///
/// Photo *uploads* are still excluded, and deliberately: the JPEG lives in
/// Storage, not Postgres, and parking megabytes of image data in a JSON
/// outbox is a different problem from replaying a row.
enum PendingWrite: Codable, Hashable {
    case insertUsageLog(UsageLog)
    case deleteUsageLog(id: UUID)
    case insertProduct(Product)
    case updateProduct(Product)
    case deleteProduct(id: UUID)
    case saveReaction(SkinReaction)
    case deleteReaction(id: UUID)
    case insertEmpty(ProductEmpty)
    case setPhotoNote(id: UUID, note: String?)
    case setSkinProfile(userID: UUID, profile: SkinProfile)
}

enum PendingWriteQueue {
    private static func url(for userID: UUID) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Cache", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("pending-\(userID.uuidString).json")
    }

    static func load(userID: UUID) -> [PendingWrite] {
        do {
            let url = try url(for: userID)
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            return try JSONDecoder().decode([PendingWrite].self, from: Data(contentsOf: url))
        } catch {
            AppLog.sync.debug("pending queue load failed, ignoring: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func save(_ writes: [PendingWrite], userID: UUID) {
        do {
            let url = try url(for: userID)
            guard !writes.isEmpty else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            let data = try JSONEncoder().encode(writes)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            AppLog.sync.error("pending queue save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func clear(userID: UUID) {
        guard let url = try? url(for: userID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Folds the queue into a freshly fetched log list, so work that hasn't
    /// reached the server yet still shows as done.
    ///
    /// Applied in order: a queued insert followed by a queued delete of the
    /// same row (check on, check off, both offline) has to end with the row
    /// absent, which only holds if they're replayed in the order they
    /// happened.
    static func apply(_ writes: [PendingWrite], toLogs logs: [UsageLog]) -> [UsageLog] {
        var merged = logs
        for write in writes {
            switch write {
            case .insertUsageLog(let log):
                if !merged.contains(where: { $0.id == log.id }) {
                    merged.append(log)
                }
            case .deleteUsageLog(let id):
                merged.removeAll { $0.id == id }
            default:
                // Every other case addresses a different table; folding
                // those into a usage-log array would be meaningless. They
                // get their own `apply` overloads below.
                continue
            }
        }
        return merged
    }

    /// Same idea for products: a product added offline has to survive the
    /// refetch that doesn't know about it yet.
    static func apply(_ writes: [PendingWrite], toProducts products: [Product]) -> [Product] {
        var merged = products
        for write in writes {
            switch write {
            case .insertProduct(let product), .updateProduct(let product):
                if let index = merged.firstIndex(where: { $0.id == product.id }) {
                    merged[index] = product
                } else {
                    merged.append(product)
                }
            case .deleteProduct(let id):
                merged.removeAll { $0.id == id }
            default:
                continue
            }
        }
        return merged
    }

    static func apply(_ writes: [PendingWrite], toReactions reactions: [SkinReaction]) -> [SkinReaction] {
        var merged = reactions
        for write in writes {
            switch write {
            case .saveReaction(let reaction):
                // One row per day, matching the table's own unique
                // constraint -- re-logging a day replaces it rather than
                // stacking a second row.
                merged.removeAll { $0.id == reaction.id }
                merged.append(reaction)
            case .deleteReaction(let id):
                merged.removeAll { $0.id == id }
            default:
                continue
            }
        }
        return merged
    }

    static func apply(_ writes: [PendingWrite], toEmpties empties: [ProductEmpty]) -> [ProductEmpty] {
        var merged = empties
        for write in writes {
            switch write {
            case .insertEmpty(let empty):
                if !merged.contains(where: { $0.id == empty.id }) {
                    merged.append(empty)
                }
            default:
                continue
            }
        }
        return merged
    }

    /// Performs one write against its service.
    ///
    /// One switch, used by both `flush` and `AppData.performOrQueue`.
    /// They used to each carry their own copy, which is the same
    /// two-places-must-agree hazard that `WidgetSharedTypes` exists to
    /// remove: a case added to the enum and handled in only one of them
    /// compiles fine and silently never syncs.
    static func send(_ write: PendingWrite) async throws {
        switch write {
        case .insertUsageLog(let log):
            try await UsageLogService.insert(log)
        case .deleteUsageLog(let id):
            try await UsageLogService.delete(id: id)
        case .insertProduct(let product):
            try await ProductService.insert(product)
        case .updateProduct(let product):
            try await ProductService.update(product)
        case .deleteProduct(let id):
            try await ProductService.delete(id: id)
        case .saveReaction(let reaction):
            try await SkinReactionService.save(reaction)
        case .deleteReaction(let id):
            try await SkinReactionService.delete(id: id)
        case .insertEmpty(let empty):
            try await ProductEmptyService.insert(empty)
        case .setPhotoNote(let id, let note):
            try await ProgressPhotoService.updateNote(id: id, note: note)
        case .setSkinProfile(let userID, let profile):
            try await ProfileService.setSkinProfile(userID: userID, profile: profile)
        }
    }

    /// Sends everything queued, in order, and returns whatever still
    /// hasn't made it.
    ///
    /// Stops at the first failure rather than skipping past it: these are
    /// ordered operations on the same rows, and running a later delete
    /// while its matching insert is still unsent would drop the check-off
    /// entirely.
    static func flush(_ writes: [PendingWrite]) async -> [PendingWrite] {
        var remaining = writes
        while let next = remaining.first {
            do {
                try await send(next)
                remaining.removeFirst()
            } catch {
                AppLog.sync.error("pending write failed, keeping queued: \(error.localizedDescription, privacy: .public)")
                break
            }
        }
        return remaining
    }
}
