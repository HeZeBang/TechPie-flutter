package club.geekpie.techpie.notification

/** Pure receipt state. Android persists only opaque keys and timestamps. */
data class SpendingRecord(
    val key: String,
    val at: Long,
    val spending: Boolean,
    val title: String = "",
    val body: String = "",
)

data class SpendingLedger(
    val owner: String? = null,
    val generation: Long = 0,
    val initialized: Boolean = false,
    val floor: Long = Long.MIN_VALUE,
    val seen: Map<String, Long> = emptyMap(),
) {
    data class Update(val ledger: SpendingLedger, val receipts: List<SpendingRecord>)

    fun configure(nextOwner: String?): SpendingLedger =
        if (owner == nextOwner) this else SpendingLedger(nextOwner, generation + 1)

    fun observe(expectedOwner: String, expectedGeneration: Long,
                records: List<SpendingRecord>, now: Long): Update? {
        if (owner == null || owner != expectedOwner || generation != expectedGeneration) return null
        val page = records.filter { it.at > 0 && it.at <= now + 300_000L }
            .distinctBy { it.key }.sortedWith(compareBy({ it.at }, { it.key }))
        // An empty first page is still a baseline: the next real payment is news.
        val baseline = if (initialized) floor else page.maxOfOrNull { it.at } ?: now
        val receipts = if (!initialized) emptyList() else page.filter {
            it.spending && it.at >= floor && !seen.containsKey(it.key)
        }
        val merged = seen.toMutableMap()
        page.forEach { merged[it.key] = it.at }
        val ordered = merged.entries.sortedWith(compareBy({ it.value }, { it.key }))
        val removed = ordered.dropLast(LIMIT)
        val nextFloor = maxOf(baseline, removed.maxOfOrNull { it.value + 1 } ?: Long.MIN_VALUE)
        return Update(copy(initialized = true, floor = nextFloor,
            seen = ordered.takeLast(LIMIT).associate { it.key to it.value }), receipts)
    }

    companion object { const val LIMIT = 200 }
}
