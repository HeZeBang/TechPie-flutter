package club.geekpie.techpie.atrust

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import club.geekpie.techpie.MainActivity
import club.geekpie.techpie.R
import java.io.IOException

/**
 * The system-VPN shape on Android: an interface the whole device routes through
 * for the campus destinations the controller's policy authorizes — which is what
 * reaches the campus from WebViews and from other apps, unlike the in-app proxy.
 *
 * Unlike OHOS there is no separate extension process: this service runs in the
 * app's own process, so the descriptor it establishes is handed straight to the
 * Dart side, which passes it to the engine over FFI. Nothing is filtered by
 * package name — the engine authorizes every flow against the policy, so a broad
 * route cannot leak traffic.
 */
class AtrustVpnService : VpnService() {
    private var tunnel: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Only a start that carries this app's request builds an interface. The
        // VPN framework starts the service again on its own once the descriptor
        // it was given closes — with no arguments — and building from those would
        // leave a second interface carrying no routes at all: measured, that is
        // what made a "stopped" VPN look like one that would not stop.
        if (intent?.action != ACTION_START) {
            Log.i(TAG, "start without a request (action=${intent?.action}); refusing")
            return failStart()
        }
        if (tunnel != null) {
            active = true
            instance = this
            return START_STICKY
        }
        val routes = intent?.getStringArrayListExtra(REQUEST_ROUTES_ARG).orEmpty()
        val dns = intent?.getStringArrayListExtra(REQUEST_DNS_ARG).orEmpty().ifEmpty {
            // An interface that declares no resolver becomes a default network
            // with nowhere to ask, and every lookup on the device then fails —
            // measured: `ping vpn.shanghaitech.edu.cn` from the device shell
            // answered "unknown host" while the app's own interface was up. The
            // network already under this one has resolvers that work, so they are
            // carried rather than the campus's own (which cannot answer for the
            // controller, an off-campus name).
            underlyingDnsServers()
        }

        val builder = Builder()
            .setSession(SESSION_NAME)
            .addAddress(TUN_ADDRESS, 32)
            .setMtu(MTU)
            .setBlocking(false)

        for (route in routes) {
            val parts = route.split('/')
            val network = parts.getOrNull(0)?.trim().orEmpty()
            val prefix = parts.getOrNull(1)?.trim()?.toIntOrNull()
            if (network.isEmpty() || prefix == null) continue
            try {
                builder.addRoute(network, prefix)
            } catch (error: IllegalArgumentException) {
                Log.w(TAG, "route $route refused", error)
            }
        }
        for (server in dns) {
            try {
                builder.addDnsServer(server)
            } catch (error: IllegalArgumentException) {
                Log.w(TAG, "dns $server refused", error)
            }
        }

        val descriptor = try {
            builder.establish()
        } catch (error: Exception) {
            // No consent, or the platform refused the interface.
            Log.e(TAG, "establish failed", error)
            null
        }
        if (descriptor == null) {
            tunnel = null
            active = false
            instance = null
            stopSelf()
            return START_NOT_STICKY
        }
        tunnel = descriptor
        instance = this
        active = true
        showForeground("$TUN_ADDRESS · ${routes.size} 条校园路由")
        Log.i(TAG, "interface up, fd=${descriptor.fd} routes=${routes.size} dns=${dns.size}")
        return START_STICKY
    }

    /** The resolvers of the network this interface sits above. */
    private fun underlyingDnsServers(): List<String> {
        val manager = getSystemService(ConnectivityManager::class.java) ?: return emptyList()
        val active = manager.activeNetwork ?: return emptyList()
        return manager.getLinkProperties(active)?.dnsServers
            ?.mapNotNull { it.hostAddress }
            .orEmpty()
    }

    /** Nothing is left running; the caller must return START_NOT_STICKY. */
    private fun failStart(): Int {
        closeTunnel()
        active = false
        stopSelf()
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        // The user (or another VPN) revoked us: take the interface down.
        Log.i(TAG, "revoked")
        closeTunnel()
        active = false
        stopSelf()
    }

    override fun onDestroy() {
        Log.i(TAG, "service destroyed, fd=${tunnel?.fd}")
        closeTunnel()
        instance = null
        super.onDestroy()
    }

    /**
     * Puts the interface under a foreground service, which is what keeps the
     * system from reclaiming the app in the background — the shape every Android
     * VPN client uses (Clash Meta, sing-box, v2rayNG, Tailscale all raise one).
     * The notification is the price, and it is a fair one: a client whose tunnel
     * disappears without saying so is worse than one with a status line.
     */
    private fun showForeground(address: String) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "校园网 VPN",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { description = "校园网 VPN 的连接状态" },
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("校园网 VPN 已连接")
            .setContentText(address)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(open)
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    /** Closing the descriptor is what removes the interface. */
    private fun closeTunnel() {
        try {
            tunnel?.close()
        } catch (_: IOException) {
            // Already gone; nothing left to release.
        }
        tunnel = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
    }

    companion object {
        private const val TAG = "AtrustVpn"
        private const val SESSION_NAME = "TechPie campus tunnel"

        /**
         * The interface's own address — private, and distinct from the eCard
         * bind tunnel's, so the two can coexist.
         */
        private const val TUN_ADDRESS = "10.111.223.2"
        private const val MTU = 1400

        private const val CHANNEL_ID = "campus-vpn"
        private const val NOTIFICATION_ID = 0x4156

        /** The action an interface request is started with. */
        const val ACTION_START = "club.geekpie.techpie.action.ATRUST_VPN_START"

        const val REQUEST_ROUTES_ARG = "routes"
        const val REQUEST_DNS_ARG = "dns"

        @Volatile
        var active = false
            private set

        @Volatile
        private var instance: AtrustVpnService? = null

        /** The descriptor of the interface in this process, or -1 when none is up. */
        fun descriptorFd(): Int = instance?.tunnel?.fd ?: -1

        /**
         * Takes the interface down now — the same shape the eCard bind tunnel
         * uses, for the same reason.
         *
         * `stopSelf()`/`stopService()` are not enough on their own: the VPN
         * framework keeps this service bound for as long as the interface exists,
         * so the system never destroys it and `onDestroy` — where the teardown
         * otherwise lives — would never run. Closing the descriptor is what
         * actually removes the interface.
         */
        fun stopTunnel() {
            val service = instance ?: return
            service.closeTunnel()
            active = false
            service.stopSelf()
        }
    }
}
