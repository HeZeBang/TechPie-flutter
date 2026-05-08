package com.example.techpie.widget.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/**
 * Loose JSON parsing — Dart side may emit numbers / strings inconsistently
 * (e.g. tableId is a string but sometimes serialized as int). We hand-parse
 * with kotlinx.serialization's JsonObject API to stay tolerant.
 */
val widgetJson = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
}

data class CoursePeriod(
    val index: Int,
    val startTime: String,
    val endTime: String,
) {
    companion object {
        fun fromJson(obj: JsonObject): CoursePeriod {
            val idx = obj["index"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0
            val tr = obj["timeRange"]?.jsonPrimitive?.contentOrNull.orEmpty()
            val parts = tr.split('-')
            return CoursePeriod(
                index = idx,
                startTime = parts.getOrNull(0)?.trim().orEmpty(),
                endTime = parts.getOrNull(1)?.trim().orEmpty(),
            )
        }
    }
}

/** Mirrors lib/models/course_table.dart EamsCourse */
data class EamsCourse(
    val name: String,
    val classroom: String,
    val teachers: String,
    val weeks: String,            // bitstring; index i means week i active
    val times: Map<Int, List<Int>>, // weekday(1-7) -> sorted list of period numbers
) {
    fun isActiveInWeek(week: Int): Boolean =
        week in 0 until weeks.length && weeks[week] == '1'

    companion object {
        fun fromJson(obj: JsonObject): EamsCourse {
            val rawTimes = obj["times"]?.jsonObject ?: JsonObject(emptyMap())
            val times = mutableMapOf<Int, List<Int>>()
            for ((k, v) in rawTimes) {
                val day = k.toIntOrNull() ?: continue
                val csv = v.jsonPrimitive.contentOrNull.orEmpty()
                val periods = csv.split(',')
                    .mapNotNull { it.trim().toIntOrNull() }
                    .filter { it > 0 }
                    .sorted()
                times[day] = periods
            }
            return EamsCourse(
                name = obj["name"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                classroom = obj["classroom"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                teachers = obj["teachers"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                weeks = obj["weeks"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                times = times,
            )
        }
    }
}

data class CourseTable(
    val periods: List<CoursePeriod>,
    val courses: List<EamsCourse>,
) {
    companion object {
        fun fromJson(obj: JsonObject): CourseTable {
            val periods = (obj["periods"] as? JsonElement)?.jsonArray
                ?.map { CoursePeriod.fromJson(it.jsonObject) }
                ?.sortedBy { it.index }
                .orEmpty()
            val courses = (obj["courses"] as? JsonElement)?.jsonArray
                ?.map { EamsCourse.fromJson(it.jsonObject) }
                .orEmpty()
            return CourseTable(periods, courses)
        }
    }
}

/** SemesterInfo from lib/models/course_table.dart */
data class SemesterInfo(
    /** year ("2024-2025") -> { label("春") -> semesterId } */
    val semesters: Map<String, Map<String, String>>,
    val defaultSemester: String,
    val tableId: String,
) {
    fun findLabel(semesterId: String): String? {
        for ((year, inner) in semesters) {
            for ((label, id) in inner) {
                if (id == semesterId) return "$year $label" + "学期"
            }
        }
        return null
    }

    companion object {
        fun fromJson(obj: JsonObject): SemesterInfo {
            val raw = obj["semesters"]?.jsonObject ?: JsonObject(emptyMap())
            val outer = mutableMapOf<String, Map<String, String>>()
            for ((year, v) in raw) {
                val inner = mutableMapOf<String, String>()
                for ((label, id) in v.jsonObject) {
                    inner[label] = id.jsonPrimitive.contentOrNull.orEmpty()
                }
                outer[year] = inner
            }
            return SemesterInfo(
                semesters = outer,
                defaultSemester = obj["defaultSemester"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                tableId = obj["tableId"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            )
        }
    }
}

/** Mirrors lib/models/assignment.dart */
@Serializable
data class Assignment(
    val id: String,
    val platform: String,
    val title: String,
    val course: String,
    /** Epoch seconds (UTC). */
    val dueEpochSeconds: Long,
    val status: String?,
    val url: String?,
) {
    /** Matches Dart `Assignment.submitted`. */
    val submitted: Boolean
        get() = status == "Submitted" || status == "Graded"

    val key: String get() = "$platform:$id"

    companion object {
        fun fromJson(obj: JsonObject): Assignment = Assignment(
            id = obj["id"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            platform = obj["platform"]?.jsonPrimitive?.contentOrNull ?: "unknown",
            title = obj["title"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            course = obj["course"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            dueEpochSeconds = obj["due"]?.jsonPrimitive?.longOrNull ?: 0L,
            status = obj["status"]?.jsonPrimitive?.contentOrNull,
            url = obj["url"]?.jsonPrimitive?.contentOrNull,
        )
    }
}

/** Mirrors lib/models/assignment_overrides.dart */
data class AssignmentOverrides(
    val completed: Map<String, Boolean>,
    val hidden: Set<String>,
) {
    fun isHidden(a: Assignment): Boolean = a.key in hidden

    fun effectiveCompleted(a: Assignment): Boolean =
        completed[a.key] ?: a.submitted

    companion object {
        val EMPTY = AssignmentOverrides(emptyMap(), emptySet())

        fun fromJson(obj: JsonObject): AssignmentOverrides {
            val completed = obj["completed"]?.jsonObject?.mapValues { (_, v) ->
                v.jsonPrimitive.booleanOrNull ?: false
            } ?: emptyMap()
            val hidden = obj["hidden"]?.jsonArray
                ?.mapNotNull { it.jsonPrimitive.contentOrNull }
                ?.toSet() ?: emptySet()
            return AssignmentOverrides(completed, hidden)
        }
    }
}
