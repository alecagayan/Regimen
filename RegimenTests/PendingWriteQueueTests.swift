//
//  PendingWriteQueueTests.swift
//  RegimenTests
//

import Foundation
import Testing
@testable import Regimen

/// The merge step is the part that decides whether a check-off made
/// offline survives the next fetch, so it's worth pinning down precisely.
struct PendingWriteQueueTests {

    private func log(
        id: UUID = UUID(),
        product: UUID = UUID(),
        timeOfDay: TimeOfDay = .am
    ) -> UsageLog {
        UsageLog(
            id: id,
            userID: UUID(),
            productID: product,
            timeOfDay: timeOfDay,
            estimatedAmountUsedML: 1
        )
    }

    /// The bug this whole mechanism exists for: a check-off that hasn't
    /// reached the server must not be erased by the fetch that comes back
    /// without it.
    @Test func queuedInsertSurvivesAServerFetchThatLacksIt() {
        let pending = log()
        let merged = PendingWriteQueue.apply([.insertUsageLog(pending)], toLogs: [])

        #expect(merged.count == 1)
        #expect(merged.first?.id == pending.id)
    }

    @Test func queuedDeleteRemovesARowTheServerStillHas() {
        let existing = log()
        let merged = PendingWriteQueue.apply([.deleteUsageLog(id: existing.id)], toLogs: [existing])

        #expect(merged.isEmpty)
    }

    /// Checked on then off while offline has to end up off. Replaying these
    /// out of order would resurrect the check-off.
    @Test func insertThenDeleteOfTheSameRowEndsDeleted() {
        let entry = log()
        let merged = PendingWriteQueue.apply(
            [.insertUsageLog(entry), .deleteUsageLog(id: entry.id)],
            toLogs: []
        )

        #expect(merged.isEmpty)
    }

    /// Once the server has caught up it returns the row itself; replaying
    /// the queued insert must not double it.
    @Test func queuedInsertDoesNotDuplicateARowTheServerAlreadyReturned() {
        let entry = log()
        let merged = PendingWriteQueue.apply([.insertUsageLog(entry)], toLogs: [entry])

        #expect(merged.count == 1)
    }

    @Test func unrelatedServerRowsAreLeftAlone() {
        let untouched = log()
        let pending = log()
        let merged = PendingWriteQueue.apply([.insertUsageLog(pending)], toLogs: [untouched])

        #expect(merged.count == 2)
        #expect(merged.contains { $0.id == untouched.id })
    }

    @Test func emptyQueueChangesNothing() {
        let rows = [log(), log()]
        #expect(PendingWriteQueue.apply([], toLogs: rows).map(\.id) == rows.map(\.id))
    }

    // MARK: - Persistence

    /// The queue is only useful if it outlives the process that made it --
    /// an in-memory-only outbox would lose exactly the check-offs it exists
    /// to protect, the moment the app is killed offline.
    @Test func queueRoundTripsThroughDisk() {
        let userID = UUID()
        defer { PendingWriteQueue.clear(userID: userID) }

        let entry = log()
        PendingWriteQueue.save([.insertUsageLog(entry)], userID: userID)

        let reloaded = PendingWriteQueue.load(userID: userID)
        #expect(reloaded.count == 1)
        #expect(reloaded.first == .insertUsageLog(entry))
    }

    @Test func savingAnEmptyQueueClearsIt() {
        let userID = UUID()
        defer { PendingWriteQueue.clear(userID: userID) }

        PendingWriteQueue.save([.deleteUsageLog(id: UUID())], userID: userID)
        PendingWriteQueue.save([], userID: userID)

        #expect(PendingWriteQueue.load(userID: userID).isEmpty)
    }

    @Test func clearRemovesTheQueue() {
        let userID = UUID()
        PendingWriteQueue.save([.deleteUsageLog(id: UUID())], userID: userID)
        PendingWriteQueue.clear(userID: userID)

        #expect(PendingWriteQueue.load(userID: userID).isEmpty)
    }

    @Test func unknownUserHasNoQueue() {
        #expect(PendingWriteQueue.load(userID: UUID()).isEmpty)
    }
}

/// The cache's job is that a cold, offline launch shows the last known
/// state instead of an empty app.
struct LocalCacheTests {

    private func snapshot(productCount: Int) -> CachedSnapshot {
        CachedSnapshot(
            products: (0..<productCount).map { index in
                Product(
                    userID: UUID(),
                    name: "Product \(index)",
                    brand: "Brand",
                    routineTime: .both,
                    applicationOrder: index,
                    sizeInML: 30,
                    openedDate: .now
                )
            },
            usageLogs: [],
            progressPhotos: [],
            zoneFindings: [],
            streakRestores: [],
            reactions: [],
            empties: [],
            isPremium: true,
            hasUsedFreeScan: true,
            purchasedRestoreCredits: 2,
            savedAt: .now
        )
    }

    @Test func snapshotRoundTripsThroughDisk() async {
        let userID = UUID()
        defer { LocalCache.clear(userID: userID) }

        await LocalCache.save(snapshot(productCount: 3), userID: userID)
        let loaded = LocalCache.load(userID: userID)

        #expect(loaded?.products.count == 3)
        #expect(loaded?.isPremium == true)
        #expect(loaded?.purchasedRestoreCredits == 2)
    }

    /// Each account gets its own file -- signing in as someone else must
    /// not surface the previous user's cabinet.
    @Test func snapshotsAreScopedPerAccount() async {
        let first = UUID()
        let second = UUID()
        defer {
            LocalCache.clear(userID: first)
            LocalCache.clear(userID: second)
        }

        await LocalCache.save(snapshot(productCount: 3), userID: first)

        #expect(LocalCache.load(userID: second) == nil)
    }

    @Test func clearRemovesTheSnapshot() async {
        let userID = UUID()
        await LocalCache.save(snapshot(productCount: 1), userID: userID)
        LocalCache.clear(userID: userID)

        #expect(LocalCache.load(userID: userID) == nil)
    }
}

/// The outbox used to cover only check-offs. Everything the user can author
/// now queues, so these pin that each kind survives a refetch -- the exact
/// failure the queue exists to prevent, where the fetch that was meant to
/// confirm your work instead erases it.
struct ExpandedPendingWriteTests {

    private func product(name: String = "Serum") -> Product {
        Product(
            userID: UUID(),
            name: name,
            brand: "Brand",
            routineTime: .pm,
            layerCategory: .treatment,
            applicationOrder: 1,
            sizeInML: 30,
            openedDate: .now
        )
    }

    // MARK: - Products

    @Test func aQueuedProductSurvivesARefetchThatDoesNotKnowIt() {
        let added = product(name: "Added Offline")
        let merged = PendingWriteQueue.apply([.insertProduct(added)], toProducts: [])
        #expect(merged.map(\.name) == ["Added Offline"])
    }

    @Test func aQueuedEditWinsOverTheServerRow() {
        var item = product(name: "Old Name")
        let serverCopy = item
        item.name = "New Name"

        let merged = PendingWriteQueue.apply([.updateProduct(item)], toProducts: [serverCopy])
        #expect(merged.count == 1)
        #expect(merged.first?.name == "New Name")
    }

    @Test func aQueuedDeleteRemovesARowTheServerStillHas() {
        let item = product()
        let merged = PendingWriteQueue.apply([.deleteProduct(id: item.id)], toProducts: [item])
        #expect(merged.isEmpty)
    }

    /// Add then delete while offline has to end with the product gone,
    /// which only holds if replay respects the order it happened in.
    @Test func addThenDeleteEndsWithNothing() {
        let item = product()
        let merged = PendingWriteQueue.apply(
            [.insertProduct(item), .deleteProduct(id: item.id)],
            toProducts: []
        )
        #expect(merged.isEmpty)
    }

    // MARK: - Reactions

    @Test func aQueuedReactionSurvivesARefetch() {
        let reaction = SkinReaction(userID: UUID(), severity: .moderate)
        let merged = PendingWriteQueue.apply([.saveReaction(reaction)], toReactions: [])
        #expect(merged.count == 1)
        #expect(merged.first?.severity == .moderate)
    }

    /// One row per day: re-logging replaces rather than stacking.
    @Test func reLoggingTheSameReactionReplacesIt() {
        var reaction = SkinReaction(userID: UUID(), severity: .mild)
        let first = reaction
        reaction.severity = .severe

        let merged = PendingWriteQueue.apply([.saveReaction(reaction)], toReactions: [first])
        #expect(merged.count == 1)
        #expect(merged.first?.severity == .severe)
    }

    @Test func aQueuedReactionDeleteRemovesIt() {
        let reaction = SkinReaction(userID: UUID(), severity: .mild)
        #expect(PendingWriteQueue.apply([.deleteReaction(id: reaction.id)], toReactions: [reaction]).isEmpty)
    }

    // MARK: - Empties

    @Test func aQueuedEmptySurvivesARefetch() {
        let empty = ProductEmpty(userID: UUID(), productID: nil, productName: "Finished", brand: "B")
        let merged = PendingWriteQueue.apply([.insertEmpty(empty)], toEmpties: [])
        #expect(merged.map(\.productName) == ["Finished"])
    }

    @Test func replayingAnEmptyTwiceDoesNotDuplicateIt() {
        let empty = ProductEmpty(userID: UUID(), productID: nil, productName: "Finished", brand: "B")
        let merged = PendingWriteQueue.apply([.insertEmpty(empty), .insertEmpty(empty)], toEmpties: [])
        #expect(merged.count == 1)
    }

    // MARK: - Cross-table isolation

    /// Each `apply` overload has a `default: continue`. If one ever started
    /// acting on another table's case, this catches it.
    @Test func writesForOneTableDoNotDisturbAnother() {
        let item = product()
        let reaction = SkinReaction(userID: UUID(), severity: .mild)
        let writes: [PendingWrite] = [
            .insertProduct(item),
            .saveReaction(reaction),
            .setPhotoNote(id: UUID(), note: "hello"),
            .setSkinProfile(userID: UUID(), profile: SkinProfile()),
        ]

        #expect(PendingWriteQueue.apply(writes, toProducts: []).count == 1)
        #expect(PendingWriteQueue.apply(writes, toReactions: []).count == 1)
        #expect(PendingWriteQueue.apply(writes, toEmpties: []).isEmpty)
        #expect(PendingWriteQueue.apply(writes, toLogs: []).isEmpty)
    }

    /// Every case has to survive disk, or a failure to encode would
    /// silently empty the outbox and lose the user's work.
    ///
    /// Equality is asserted per case rather than on the whole array,
    /// because `SkinReaction` and `ProductEmpty` deliberately serialize
    /// their day columns as bare `yyyy-MM-dd` (see `PostgresDay`). That
    /// truncates the time, so those two never compare equal to an
    /// in-memory original -- correct behaviour for a Postgres `date`, and
    /// a real distinction worth stating rather than papering over.
    @Test func everyWriteKindRoundTripsThroughDisk() throws {
        let item = product()
        let writes: [PendingWrite] = [
            .insertProduct(item),
            .updateProduct(item),
            .deleteProduct(id: item.id),
            .saveReaction(SkinReaction(userID: UUID(), severity: .severe)),
            .deleteReaction(id: UUID()),
            .insertEmpty(ProductEmpty(userID: UUID(), productID: nil, productName: "X", brand: "Y")),
            .setPhotoNote(id: UUID(), note: nil),
            .setSkinProfile(userID: UUID(), profile: SkinProfile()),
        ]

        let data = try JSONEncoder().encode(writes)
        let restored = try JSONDecoder().decode([PendingWrite].self, from: data)

        #expect(restored.count == writes.count)

        // Cases with no day-truncating payload must be exactly equal.
        #expect(restored[0] == writes[0])
        #expect(restored[1] == writes[1])
        #expect(restored[2] == writes[2])
        #expect(restored[4] == writes[4])
        #expect(restored[6] == writes[6])
        #expect(restored[7] == writes[7])

        // The two that truncate still have to come back as the same row on
        // the same day.
        guard case .saveReaction(let original) = writes[3],
              case .saveReaction(let decoded) = restored[3]
        else {
            Issue.record("reaction case did not survive encoding")
            return
        }
        #expect(decoded.id == original.id)
        #expect(decoded.severity == original.severity)
        #expect(Calendar.current.isDate(decoded.occurredOn, inSameDayAs: original.occurredOn))

        guard case .insertEmpty(let originalEmpty) = writes[5],
              case .insertEmpty(let decodedEmpty) = restored[5]
        else {
            Issue.record("empty case did not survive encoding")
            return
        }
        #expect(decodedEmpty.id == originalEmpty.id)
        #expect(decodedEmpty.productName == originalEmpty.productName)
        #expect(Calendar.current.isDate(decodedEmpty.finishedOn, inSameDayAs: originalEmpty.finishedOn))
    }
}
