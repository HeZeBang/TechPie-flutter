package club.geekpie.techpie.atrust

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log

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
        if (tunnel != null) {
            active = true
            instance = this
            return START_STICKY
        }
        val routes = intent?.getStringArrayListExtra(REQUEST_ROUTES_ARG).orEmpty()
        val dns = intent?.getStringArrayListExtra(REQUEST_DNS_ARG).orEmpty()

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
        Log.i(TAG, "interface up, fd=${descriptor.fd} routes=${routes.size} dns=${dns.size}")
        return START_STICKY
    }

    override fun onRevoke() {
        // The user (or another VPN) revoked us: take the interface down.
        stopSelf()
    }

    override fun onDestroy() {
        tunnel?.close()
        tunnel = null
        instance = null
        active = false
        super.onDestroy()
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
         * Takes the interface down now. `stopService()` alone would not: the VPN
         * framework holds a binding for as long as the interface exists.
         */
        fun stopTunnel() {
            val service = instance
            service?.tunnel?.close()
            service?.tunnel = null
            active = false
            service?.stopSelf()
        }
    }
}
