package club.geekpie.techpie

import android.app.Activity
import android.content.Context
import android.content.pm.ApplicationInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Plays the waveforms the Dart layer names (lib/utils/haptics.dart).
 *
 * The phone is told what to play, not asked to decide: the pulses arrive with
 * the call, so one action feels the same on every device, and a waveform is a
 * few milliseconds of motor rather than whatever a platform default happens to
 * be.
 */
class EcardFeedback(activity: Activity, messenger: BinaryMessenger) {
    private val context = activity.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "techpie/feedback")
    private val pool = SoundPool.Builder().setMaxStreams(1).setAudioAttributes(
        AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
    ).build()
    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
        context.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        (context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)
    }
    private val samples = mutableMapOf<String, Int>()
    private val ready = mutableSetOf<Int>()
    private val failed = mutableSetOf<Int>()
    private var pending: Request? = null
    private var stream = 0
    private var generation = 0
    private var disposed = false

    init {
        activity.volumeControlStream = AudioManager.STREAM_MUSIC
        pool.setOnLoadCompleteListener { _, sample, status ->
            handler.post {
                if (disposed) return@post
                if (status == 0) ready.add(sample) else failed.add(sample)
                pending?.takeIf { it.sample == sample }?.let {
                    pending = null
                    start(it)
                }
            }
        }
        channel.setMethodCallHandler { call, result ->
            if (call.method != "play") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val request = request(call, result)
            if (disposed || request == null) {
                result.error("feedback_unavailable", "No waveform was given.", null)
                return@setMethodCallHandler
            }
            pending?.result?.success(null)
            pending = null
            generation++
            stopPlayback()
            if (request.sound && request.sample != 0 &&
                request.sample !in ready && request.sample !in failed) {
                pending = request
            } else {
                start(request)
            }
        }
    }

    private fun request(call: MethodCall, result: MethodChannel.Result): Request? {
        val entries = call.argument<Any>("pulses") as? List<*> ?: emptyList<Any?>()
        val pulses = entries.mapNotNull { entry -> pulse(entry as? Map<*, *>) }
        val vibration = call.argument<Boolean>("vibration") == true
        val asset = call.argument<String>("soundAsset")
        val sound = call.argument<Boolean>("sound") == true && asset != null
        if (pulses.isEmpty() && !sound) return null
        val vibrated = pulses.fold(0L) { end, pulse -> maxOf(end, pulse.atMs + pulse.durationMs) }
        val declared = (call.argument<Number>("soundDurationMs"))?.toLong() ?: 0L
        return Request(
            id = call.argument<String>("id") ?: "waveform",
            pulses = pulses,
            sound = sound,
            vibration = vibration,
            windowMs = maxOf(declared, vibrated),
            sample = if (sound) sampleFor(asset!!) else 0,
            result = result,
        )
    }

    private fun pulse(raw: Map<*, *>?): Pulse? {
        if (raw == null) return null
        return Pulse(
            atMs = (raw["atMs"] as? Number)?.toLong() ?: 0L,
            durationMs = (raw["durationMs"] as? Number)?.toLong() ?: 0L,
            intensity = (raw["intensity"] as? Number)?.toFloat() ?: 1f,
        )
    }

    /** The sample for one asset, loaded once and replayed from the pool after. */
    private fun sampleFor(asset: String): Int {
        samples[asset]?.let { return it }
        val sample = runCatching {
            context.assets.openFd(assetKey(asset)).use { pool.load(it, 1) }
        }.getOrDefault(0)
        samples[asset] = sample
        return sample
    }

    private fun assetKey(path: String) =
        FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(path)

    private fun start(request: Request) {
        if (request.sound) {
            val sample = request.sample
            val playable = sample != 0 && sample !in failed
            if (playable) stream = pool.play(sample, 1f, 1f, 1, 0, 1f)
            if (!playable || stream == 0) {
                // The waveform is the point; a sound that will not load must not
                // take the vibration down with it, nor fail a payment.
                if (!request.vibration) {
                    request.result.error("feedback_audio_failed", "The sound could not be played.", null)
                    return
                }
                Log.w("TechPieFeedback", "sound unavailable for ${request.id}; vibrating only")
            }
        }
        if (request.vibration && vibrator?.hasVibrator() == true) {
            vibrate(request.pulses)
        }
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            Log.d("TechPieFeedback", "play ${request.id} sound=${request.sound} vibration=${request.vibration}")
        }
        val current = generation
        handler.postDelayed({ if (generation == current) stopPlayback() }, request.windowMs)
        request.result.success(null)
    }

    @Suppress("DEPRECATION")
    private fun vibrate(pulses: List<Pulse>) {
        val motor = vibrator ?: return
        val timings = mutableListOf<Long>()
        val amplitudes = mutableListOf<Int>()
        var cursor = 0L
        for (pulse in pulses) {
            timings.add((pulse.atMs - cursor).coerceAtLeast(0))
            amplitudes.add(0)
            timings.add(pulse.durationMs)
            amplitudes.add((pulse.intensity * 255).toInt().coerceIn(1, 255))
            cursor = pulse.atMs + pulse.durationMs
        }
        if (Build.VERSION.SDK_INT >= 26) {
            val levels = amplitudes.map { if (it == 0 || motor.hasAmplitudeControl()) it else VibrationEffect.DEFAULT_AMPLITUDE }.toIntArray()
            motor.vibrate(VibrationEffect.createWaveform(timings.toLongArray(), levels, -1))
        } else {
            motor.vibrate(timings.toLongArray(), -1)
        }
    }

    private fun stopPlayback() {
        if (stream != 0) pool.stop(stream)
        stream = 0
        vibrator?.cancel()
    }

    fun dispose() {
        disposed = true
        generation++
        pending?.result?.success(null)
        pending = null
        handler.removeCallbacksAndMessages(null)
        stopPlayback()
        pool.setOnLoadCompleteListener(null)
        pool.release()
        channel.setMethodCallHandler(null)
    }

    private data class Pulse(val atMs: Long, val durationMs: Long, val intensity: Float)
    private data class Request(
        val id: String,
        val pulses: List<Pulse>,
        val sound: Boolean,
        val vibration: Boolean,
        val windowMs: Long,
        val sample: Int,
        val result: MethodChannel.Result,
    )
}
