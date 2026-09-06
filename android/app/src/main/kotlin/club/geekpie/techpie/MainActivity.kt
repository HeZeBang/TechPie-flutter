package club.geekpie.techpie

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingCalendarImport: PendingCalendarImport? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALENDAR_IMPORTER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "importCalendarEvents" -> handleImportCalendarEvents(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleImportCalendarEvents(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val rawEvents = call.argument<List<Map<String, Any?>>>("events")
        val calendarName = call.argument<String>("calendarName")?.trim()

        if (rawEvents == null || calendarName.isNullOrEmpty()) {
            result.error(
                "bad_args",
                "Missing events or calendarName for calendar import.",
                null,
            )
            return
        }

        val request = PendingCalendarImport(rawEvents, calendarName, result)
        if (hasCalendarPermissions()) {
            importCalendarEvents(request)
            return
        }

        if (pendingCalendarImport != null) {
            result.error("import_in_progress", "Calendar import is already running.", null)
            return
        }

        pendingCalendarImport = request
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
            REQUEST_CALENDAR_PERMISSIONS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != REQUEST_CALENDAR_PERMISSIONS) return

        val request = pendingCalendarImport ?: return
        pendingCalendarImport = null

        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            importCalendarEvents(request)
        } else {
            request.result.error("calendar_access_denied", "未获得日历访问权限。", null)
        }
    }

    private fun hasCalendarPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_CALENDAR,
        ) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_CALENDAR,
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun importCalendarEvents(request: PendingCalendarImport) {
        try {
            val calendarId = resolveCalendar(request.calendarName)
            val importedCount = insertEvents(request.events, calendarId)
            request.result.success(importedCount)
        } catch (error: Exception) {
            request.result.error("import_failed", error.localizedMessage, null)
        }
    }

    private fun resolveCalendar(calendarName: String): Long {
        findWritableCalendar(calendarName)?.let { return it }

        val values = ContentValues().apply {
            put(Calendars.ACCOUNT_NAME, LOCAL_ACCOUNT_NAME)
            put(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(Calendars.NAME, calendarName)
            put(Calendars.CALENDAR_DISPLAY_NAME, calendarName)
            put(Calendars.CALENDAR_COLOR, CALENDAR_COLOR)
            put(Calendars.CALENDAR_ACCESS_LEVEL, Calendars.CAL_ACCESS_OWNER)
            put(Calendars.OWNER_ACCOUNT, LOCAL_ACCOUNT_NAME)
            put(Calendars.VISIBLE, 1)
            put(Calendars.SYNC_EVENTS, 1)
            put(Calendars.CALENDAR_TIME_ZONE, TIME_ZONE)
        }

        val uri = Calendars.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(Calendars.ACCOUNT_NAME, LOCAL_ACCOUNT_NAME)
            .appendQueryParameter(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            .build()

        val createdUri = contentResolver.insert(uri, values)
            ?: throw IllegalStateException("无法创建目标日历。")
        return ContentUris.parseId(createdUri)
    }

    private fun findWritableCalendar(calendarName: String): Long? {
        val projection = arrayOf(
            Calendars._ID,
            Calendars.NAME,
            Calendars.CALENDAR_DISPLAY_NAME,
            Calendars.CALENDAR_ACCESS_LEVEL,
        )
        val selection =
            "(${Calendars.NAME}=? OR ${Calendars.CALENDAR_DISPLAY_NAME}=?) AND ${Calendars.CALENDAR_ACCESS_LEVEL}>=?"
        val selectionArgs = arrayOf(
            calendarName,
            calendarName,
            Calendars.CAL_ACCESS_CONTRIBUTOR.toString(),
        )

        contentResolver.query(
            Calendars.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            null,
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(Calendars._ID)
            if (cursor.moveToFirst()) {
                return cursor.getLong(idIndex)
            }
        }

        return null
    }

    private fun insertEvents(
        events: List<Map<String, Any?>>,
        calendarId: Long,
    ): Int {
        var importedCount = 0

        for (rawEvent in events) {
            val title = rawEvent["title"] as? String ?: continue
            val startMillis = (rawEvent["startMillis"] as? Number)?.toLong() ?: continue
            val endMillis = (rawEvent["endMillis"] as? Number)?.toLong() ?: continue

            val values = ContentValues().apply {
                put(Events.CALENDAR_ID, calendarId)
                put(Events.TITLE, title)
                put(Events.DTSTART, startMillis)
                put(Events.DTEND, endMillis)
                put(Events.EVENT_TIMEZONE, TIME_ZONE)
                put(Events.EVENT_LOCATION, rawEvent["location"] as? String)

                val notes = (rawEvent["notes"] as? String)?.trim()
                if (!notes.isNullOrEmpty()) {
                    put(Events.DESCRIPTION, notes)
                }
            }

            if (contentResolver.insert(Events.CONTENT_URI, values) != null) {
                importedCount += 1
            }
        }

        return importedCount
    }

    private data class PendingCalendarImport(
        val events: List<Map<String, Any?>>,
        val calendarName: String,
        val result: MethodChannel.Result,
    )

    private companion object {
        const val CALENDAR_IMPORTER_CHANNEL = "techpie/calendar_importer"
        const val REQUEST_CALENDAR_PERMISSIONS = 48291
        const val LOCAL_ACCOUNT_NAME = "TechPie"
        const val TIME_ZONE = "Asia/Shanghai"
        const val CALENDAR_COLOR = -13660983
    }
}
