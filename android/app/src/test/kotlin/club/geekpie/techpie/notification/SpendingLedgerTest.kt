package club.geekpie.techpie.notification

import org.junit.Assert.*
import org.junit.Test

class SpendingLedgerTest {
    private fun record(key: String, at: Long, spending: Boolean = true) = SpendingRecord(key, at, spending)

    @Test fun firstSnapshotOnlyCreatesBaseline() {
        val state = SpendingLedger().configure("a")
        val update = state.observe("a", state.generation, listOf(record("old", 1_000)), 2_000)!!
        assertTrue(update.receipts.isEmpty())
        assertTrue(update.ledger.initialized)
        assertEquals(1_000L, update.ledger.floor)
    }

    @Test fun emptyBaselineStillNotifiesFirstLaterPayment() {
        val state = SpendingLedger().configure("a")
        val baseline = state.observe("a", state.generation, emptyList(), 2_000)!!.ledger
        val update = baseline.observe("a", baseline.generation, listOf(record("new", 3_000)), 4_000)!!
        assertEquals(listOf("new"), update.receipts.map { it.key })
    }

    @Test fun overlappingUnorderedPagesNotifyEachPaymentOnceOldestFirst() {
        val state = SpendingLedger(owner = "a", generation = 3, initialized = true, floor = 1_000)
        val page = listOf(record("b", 4_000), record("a", 3_000), record("a", 3_000))
        val first = state.observe("a", 3, page, 5_000)!!
        assertEquals(listOf("a", "b"), first.receipts.map { it.key })
        assertTrue(first.ledger.observe("a", 3, page, 5_000)!!.receipts.isEmpty())
    }

    @Test fun aNewPaymentAtTheBaselineTimestampIsNotLost() {
        val state = SpendingLedger(owner = "a", initialized = true, floor = 2_000,
            seen = mapOf("old" to 2_000L))
        assertEquals(listOf("new"), state.observe("a", 0,
            listOf(record("old", 2_000), record("new", 2_000)), 3_000)!!.receipts.map { it.key })
    }

    @Test fun rechargeRefundAndHistoricalEntriesNeverBecomeSpending() {
        val state = SpendingLedger(owner = "a", initialized = true, floor = 2_000)
        val result = state.observe("a", 0, listOf(record("old", 1_000),
            record("refund", 3_000, false), record("recharge", 4_000, false)), 5_000)!!
        assertTrue(result.receipts.isEmpty())
        assertEquals(3, result.ledger.seen.size)
    }

    @Test fun disablingAndReenablingRejectsInflightReadsEvenForSameOwner() {
        val enabled = SpendingLedger().configure("a")
        val disabled = enabled.configure(null)
        assertNull(disabled.observe("a", enabled.generation, listOf(record("old", 1_000)), 2_000))
        val reenabled = disabled.configure("a")
        assertNull(reenabled.observe("a", enabled.generation, listOf(record("old", 1_000)), 2_000))
        assertTrue(reenabled.observe("a", reenabled.generation, listOf(record("old", 1_000)), 2_000)!!.receipts.isEmpty())
    }

    @Test fun switchingOwnerResetsBaselineAndRejectsOldAccount() {
        val first = SpendingLedger(owner = "a", generation = 2, initialized = true, seen = mapOf("old" to 1_000))
        val second = first.configure("b")
        assertNull(second.observe("a", first.generation, listOf(record("new", 2_000)), 3_000))
        assertTrue(second.observe("b", second.generation, listOf(record("new", 2_000)), 3_000)!!.receipts.isEmpty())
        assertEquals(first, first.configure("a"))
    }

    @Test fun boundedLedgerDoesNotReplayEvictedOlderEntries() {
        val state = SpendingLedger(owner = "a", initialized = true, floor = 0,
            seen = (1..200).associate { "old$it" to it.toLong() })
        val updated = state.observe("a", 0, (201..250).map { record("new$it", it.toLong()) }, 1_000)!!.ledger
        assertEquals(SpendingLedger.LIMIT, updated.seen.size)
        assertEquals(51L, updated.floor)
        assertTrue(updated.observe("a", 0, listOf(record("old1", 1), record("old50", 50)), 1_000)!!.receipts.isEmpty())
    }

    @Test fun invalidFutureAndZeroTimestampsCannotAdvanceBaseline() {
        val state = SpendingLedger(owner = "a")
        val updated = state.observe("a", 0, listOf(record("invalid", 0), record("future", 400_000)), 1_000)!!
        assertEquals(1_000L, updated.ledger.floor)
        assertTrue(updated.ledger.seen.isEmpty())
    }
}
