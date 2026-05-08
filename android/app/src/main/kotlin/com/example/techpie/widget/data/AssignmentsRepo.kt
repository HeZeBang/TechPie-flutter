package com.example.techpie.widget.data

import android.content.Context
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

object AssignmentsRepo {

    /**
     * Returns assignments that are NOT done and NOT hidden, sorted by due date
     * ascending. "Done" obeys the same rule as the Flutter app:
     * effectiveCompleted = override (if any) else status in {Submitted, Graded}.
     */
    fun loadPending(context: Context): List<Assignment> {
        val prefs = FlutterPrefs.open(context)

        val list = FlutterPrefs.string(prefs, "cached_assignments")
            ?.let { runCatching { widgetJson.parseToJsonElement(it).jsonArray }.getOrNull() }
            ?.map { Assignment.fromJson(it.jsonObject) }
            ?: return emptyList()

        val overrides = FlutterPrefs.string(prefs, "assignment_overrides")
            ?.let { runCatching { widgetJson.parseToJsonElement(it).jsonObject }.getOrNull() }
            ?.let { AssignmentOverrides.fromJson(it) }
            ?: AssignmentOverrides.EMPTY

        return list
            .filter { !overrides.isHidden(it) && !overrides.effectiveCompleted(it) }
            .sortedBy { it.dueEpochSeconds }
    }
}
