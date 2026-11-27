package club.geekpie.techpie.widgets

enum class DeadlineUrgency {
    URGENT,
    SOON,
    NORMAL,
}

enum class DeadlineKind(val id: String) {
    ASSIGNMENT("assignment"),
    EXAM("exam");

    companion object {
        fun fromRaw(raw: String): DeadlineKind =
            if (raw == EXAM.id) EXAM else ASSIGNMENT
    }
}

data class DeadlineItem(
    val id: String,
    val kind: DeadlineKind,
    val title: String,
    val subtitle: String,
    val dueAtMillis: Long,
)

data class DeadlineSnapshot(
    val schemaVersion: Int,
    val writtenAtMillis: Long,
    val items: List<DeadlineItem>,
)

data class ScheduleCourse(
    val id: String,
    val title: String,
    val location: String,
    val teacher: String,
    val startAtMillis: Long,
    val endAtMillis: Long,
    val startPeriod: Int? = null,
    val endPeriod: Int? = null,
    val periodLabel: String? = null,
    val isExam: Boolean = false,
    val colorLightHex: String? = null,
    val colorDarkHex: String? = null,
)

data class ScheduleDay(
    val date: String,
    val weekday: Int,
    val weekNumber: Int? = null,
    val courses: List<ScheduleCourse>,
)

data class ScheduleSnapshot(
    val schemaVersion: Int,
    val generatedAtMillis: Long,
    val weekNumber: Int? = null,
    val days: List<ScheduleDay>,
)

enum class ScheduleDayMode(val wireValue: String) {
    AUTO("auto"),
    TODAY("today"),
    TOMORROW("tomorrow");

    companion object {
        fun fromWire(raw: String?): ScheduleDayMode = when (raw) {
            TODAY.wireValue -> TODAY
            TOMORROW.wireValue -> TOMORROW
            else -> AUTO
        }
    }
}

data class EcardSnapshot(
    val schemaVersion: Int,
    val generatedAtMillis: Long,
    val configured: Boolean,
    val balanceText: String?,
    val hideBalance: Boolean,
)
