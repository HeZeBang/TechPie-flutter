package club.geekpie.techpie.notification

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationManagerCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal object SpendingRefreshScheduler {
    private const val NAME = "techpie-spending-refresh"
    fun schedule(context: Context) {
        val request = PeriodicWorkRequestBuilder<SpendingRefreshWorker>(15, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
    }
    fun cancel(context: Context) { WorkManager.getInstance(context).cancelUniqueWork(NAME) }
}

/** All engine/channel operations are on main; only the bounded wait is on Worker. */
class SpendingRefreshWorker(appContext: Context, params: WorkerParameters) : Worker(appContext, params) {
    private val main = Handler(Looper.getMainLooper())
    private val active = AtomicBoolean(true)
    private val finished = CountDownLatch(1)
    private val success = AtomicBoolean(false)
    // The fields below are owned exclusively by the main thread.
    private var engine: FlutterEngine? = null
    private var bridge: SpendingNotificationBridge? = null
    private var completion: MethodChannel? = null

    override fun doWork(): Result {
        main.post {
            if (!active.get() || isStopped) { finished.countDown(); return@post }
            if (SpendingNotificationState.status(applicationContext)["owner"] == null ||
                !NotificationManagerCompat.from(applicationContext).areNotificationsEnabled()) {
                success.set(true); finished.countDown(); return@post
            }
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                val running = FlutterEngine(applicationContext)
                engine = running
                val messenger = running.dartExecutor.binaryMessenger
                bridge = SpendingNotificationBridge(applicationContext, messenger)
                completion = MethodChannel(messenger, "techpie/spending_worker").also { channel ->
                    channel.setMethodCallHandler { call, result ->
                        if (call.method == "done") {
                            success.set(call.argument<Boolean>("success") == true)
                            result.success(true)
                            finished.countDown()
                        } else result.notImplemented()
                    }
                }
                running.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "spendingBackgroundRefresh"))
            } catch (_: Exception) { finished.countDown() }
        }
        try { finished.await(60, TimeUnit.SECONDS) }
        catch (_: InterruptedException) { Thread.currentThread().interrupt() }
        finally { active.set(false); main.post { cleanup() } }
        return if (success.get() || runAttemptCount >= 2) Result.success() else Result.retry()
    }

    override fun onStopped() {
        active.set(false)
        finished.countDown()
        main.post { cleanup() }
        super.onStopped()
    }

    private fun cleanup() {
        completion?.setMethodCallHandler(null)
        completion = null
        bridge?.dispose()
        bridge = null
        engine?.destroy()
        engine = null
    }
}
