package club.geekpie.techpie

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import club.geekpie.techpie.ecardbind.EcardBindVpnService
import club.geekpie.techpie.atrust.AtrustVpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingCalendarImport: PendingCalendarImport? = null
    private var pendingVpnConsent: PendingVpnConsent? = null
    private var pendingAtrustConsent: PendingAtrustConsent? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var ecardWidgets: EcardWidgetBridge? = null
    private var ecardFeedback: EcardFeedback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ecardWidgets = EcardWidgetBridge(this, flutterEngine.dartExecutor.binaryMessenger).also {
            it.capture(intent, notifyFlutter = false)
        }
        ecardFeedback = EcardFeedback(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALENDAR_IMPORTER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "importCalendarEvents" -> handleImportCalendarEvents(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ATRUST_VPN_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> handleStartAtrustVpn(call, result)
                "status" -> {
                    // What the interface is actually doing, so the page can show
                    // the platform's verdict rather than the app's last intent —
                    // the system's own disconnect changes it behind the app.
                    result.success(
                        if (AtrustVpnService.active) "active" else "inactive",
                    )
                }
                "stop" -> {
                    AtrustVpnService.stopTunnel()
                    stopService(Intent(this, AtrustVpnService::class.java))
                    // Answer with what is true a moment later, not with what was
                    // asked for: the platform holds a service for as long as its
                    // interface exists, so an acknowledged stop is not a released
                    // interface. The Dart side keeps the engine while this says
                    // active — an interface whose routes outlive its engine drops
                    // every campus destination into a descriptor nobody reads.
                    mainHandler.postDelayed(
                        {
                            result.success(
                                if (AtrustVpnService.active) "active" else "inactive",
                            )
                        },
                        VPN_STOP_SETTLE_MS,
                    )
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ECARD_BIND_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> handleStartEcardBindHijack(call, result)
                "stop" -> {
                    // The service cannot rely on onDestroy here: the VPN
                    // framework holds a binding for as long as the interface
                    // exists, so stopService() alone would leave the tunnel up.
                    EcardBindVpnService.stopTunnel()
                    stopService(Intent(this, EcardBindVpnService::class.java))
                    result.success(
                        if (EcardBindVpnService.active) "active" else "inactive",
                    )
                }
                "status" -> result.success(
                    if (EcardBindVpnService.active) "active" else "inactive",
                )
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ecardWidgets?.capture(intent, notifyFlutter = true)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pendingVpnConsent?.let {
            pendingVpnConsent = null
            it.result.error("engine_detached", "The VPN consent request was dropped.", null)
        }
        ecardWidgets?.dispose()
        ecardWidgets = null
        ecardFeedback?.dispose()
        ecardFeedback = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /**
     * Raises the system-wide campus tunnel and answers with the interface's file
     * descriptor: the engine runs in this process (Dart calls it over FFI), so
     * the descriptor is exactly what it needs. -1 means the user declined.
     */
    private fun handleStartAtrustVpn(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val routes = call.argument<List<String>>("routes").orEmpty()
        val dns = call.argument<List<String>>("dns").orEmpty()
        if (routes.isEmpty()) {
            result.error("bad_args", "No routes for the campus tunnel.", null)
            return
        }
        if (pendingAtrustConsent != null) {
            result.error("vpn_request_in_progress", "A VPN consent request is already pending.", null)
            return
        }

        val pending = PendingAtrustConsent(routes = routes, dns = dns, result = result)
        val consent = VpnService.prepare(this)
        if (consent == null) {
            startAtrustVpn(pending)
            return
        }
        pendingAtrustConsent = pending
        @Suppress("DEPRECATION")
        startActivityForResult(consent, REQUEST_ATRUST_CONSENT)
    }

    private fun startAtrustVpn(pending: PendingAtrustConsent) {
        val intent = Intent(this, AtrustVpnService::class.java)
            .setAction(AtrustVpnService.ACTION_START)
            .putStringArrayListExtra(AtrustVpnService.REQUEST_ROUTES_ARG, ArrayList(pending.routes))
            .putStringArrayListExtra(AtrustVpnService.REQUEST_DNS_ARG, ArrayList(pending.dns))
        startService(intent)
        // The interface exists a moment after the service starts, so answer with
        // what is actually true instead of a hopeful descriptor.
        reportAtrustTunnelFd(pending.result)
    }

    private fun reportAtrustTunnelFd(result: MethodChannel.Result, attempt: Int = 0) {
        val fd = AtrustVpnService.descriptorFd()
        if (fd >= 0) {
            result.success(fd)
            return
        }
        if (attempt >= VPN_STATE_ATTEMPTS) {
            result.error("vpn_unavailable", "The campus tunnel interface did not come up.", null)
            return
        }
        mainHandler.postDelayed(
            { reportAtrustTunnelFd(result, attempt + 1) },
            VPN_STATE_INTERVAL_MS,
        )
    }

    private fun handleStartEcardBindHijack(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val host = call.argument<String>("host")?.trim()
        val ip = call.argument<String>("ip")?.trim()
        if (host.isNullOrEmpty() || ip.isNullOrEmpty()) {
            result.error("bad_args", "Missing host or ip for the DNS hijack.", null)
            return
        }
        if (pendingVpnConsent != null) {
            result.error("vpn_request_in_progress", "A VPN consent request is already pending.", null)
            return
        }

        val request = PendingVpnConsent(
            host = host,
            ip = ip,
            result = result,
        )
        val consent = VpnService.prepare(this)
        if (consent == null) {
            // Already prepared (or consented before): straight to the service.
            startEcardBindHijack(request)
            return
        }
        pendingVpnConsent = request
        @Suppress("DEPRECATION")
        startActivityForResult(consent, REQUEST_VPN_CONSENT)
    }

    @Deprecated("VpnService.prepare hands back an Intent, so consent arrives here.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_ATRUST_CONSENT) {
            val pending = pendingAtrustConsent ?: return
            pendingAtrustConsent = null
            if (resultCode == RESULT_OK) {
                startAtrustVpn(pending)
            } else {
                pending.result.success(-1)
            }
            return
        }
        if (requestCode != REQUEST_VPN_CONSENT) return
        val request = pendingVpnConsent ?: return
        pendingVpnConsent = null

        if (resultCode == RESULT_OK) {
            startEcardBindHijack(request)
        } else {
            request.result.success("denied")
        }
    }

    private fun startEcardBindHijack(request: PendingVpnConsent) {
        val intent = Intent(this, EcardBindVpnService::class.java)
            .putExtra(EcardBindVpnService.REQUEST_HOST_ARG, request.host)
            .putExtra(EcardBindVpnService.REQUEST_IP_ARG, request.ip)
        startService(intent)
        // The interface exists a moment after the service starts, so answer with
        // what is actually true instead of a hopeful "active".
        reportEcardBindState(request.result)
    }

    private fun reportEcardBindState(result: MethodChannel.Result, attempt: Int = 0) {
        if (EcardBindVpnService.active || attempt >= VPN_STATE_ATTEMPTS) {
            result.success(if (EcardBindVpnService.active) "active" else "inactive")
            return
        }
        mainHandler.postDelayed(
            { reportEcardBindState(result, attempt + 1) },
            VPN_STATE_INTERVAL_MS,
        )
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

    private data class PendingVpnConsent(
        val host: String,
        val ip: String,
        val result: MethodChannel.Result,
    )

    private companion object {
        const val CALENDAR_IMPORTER_CHANNEL = "techpie/calendar_importer"
        const val ECARD_BIND_CHANNEL = "techpie/ecard_bind"
        const val ATRUST_VPN_CHANNEL = "techpie/atrust_vpn"
        const val REQUEST_ATRUST_CONSENT = 0x4154
        const val REQUEST_CALENDAR_PERMISSIONS = 48291
        const val REQUEST_VPN_CONSENT = 0x0ECB
        const val VPN_STATE_ATTEMPTS = 15

        /** How long a teardown is given before its result is read back. */
        const val VPN_STOP_SETTLE_MS = 400L
        const val VPN_STATE_INTERVAL_MS = 100L
        const val LOCAL_ACCOUNT_NAME = "TechPie"
        const val TIME_ZONE = "Asia/Shanghai"
        const val CALENDAR_COLOR = -13660983
    }

    private data class PendingAtrustConsent(
        val routes: List<String>,
        val dns: List<String>,
        val result: MethodChannel.Result,
    )
}
