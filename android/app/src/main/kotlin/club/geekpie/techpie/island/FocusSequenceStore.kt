package club.geekpie.techpie.island

import android.content.Context
import androidx.core.content.edit

/** Island update sequences must be monotonically increasing or the system drops the update. */
internal object FocusSequence {
    fun next(last: Long, nowMs: Long): Long = maxOf(last + 1L, nowMs)
}

/**
 * Per-notification island sequence numbers, following the wall clock.
 *
 * Frames refresh at most once a minute, so persisting every tick would be
 * wasted I/O; persist only when the in-memory value has advanced by more than
 * [PERSIST_STEP_MS] past what is on disk (guards against clock rollback).
 */
class FocusSequenceStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val cache = mutableMapOf<Int, Long>()
    private val persisted = mutableMapOf<Int, Long>()

    @Synchronized
    fun next(notifyId: Int, nowMs: Long = System.currentTimeMillis()): Long {
        val key = "seq_$notifyId"
        val last = cache[notifyId] ?: prefs.getLong(key, 0L)
        val seq = FocusSequence.next(last, nowMs)
        cache[notifyId] = seq
        val lastWritten = persisted[notifyId] ?: prefs.getLong(key, 0L)
        if (seq - lastWritten >= PERSIST_STEP_MS) {
            persisted[notifyId] = seq
            prefs.edit { putLong(key, seq) }
        }
        return seq
    }

    private companion object {
        const val PREFS_NAME = "island_focus_seq"
        const val PERSIST_STEP_MS = 30_000L
    }
}
