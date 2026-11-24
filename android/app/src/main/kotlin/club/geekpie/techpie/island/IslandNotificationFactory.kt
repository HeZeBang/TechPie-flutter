package club.geekpie.techpie.island

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import club.geekpie.techpie.MainActivity
import club.geekpie.techpie.R
import com.xzakota.hyper.notification.focus.FocusNotification
import com.xzakota.hyper.notification.island.model.TextInfo

/**
 * Builds the island notification for a frame, per active backend.
 *
 * - PLAIN: silent ongoing notification with title/text/status line
 * - LIVE_UPDATE: same plus promoted-ongoing request and a short capsule text
 * - HYPER_ISLAND: V3 focus-notification template on a HIGH-importance silent
 *   channel (the system will not float low-importance notifications to the island)
 */
class IslandNotificationFactory(
    context: Context,
    private val sequenceStore: FocusSequenceStore,
) {
    private val appContext = context.applicationContext
    private val manager = appContext.getSystemService(NotificationManager::class.java)

    @Volatile
    private var channelsReady = false

    /** Frames refresh at most once a minute; decoding the icon every time is wasteful. */
    private val appIcon: Icon by lazy {
        val drawable = appContext.applicationInfo.loadIcon(appContext.packageManager)
        if (drawable is BitmapDrawable) {
            Icon.createWithBitmap(drawable.bitmap)
        } else {
            Icon.createWithResource(appContext, appContext.applicationInfo.icon)
        }
    }

    fun ensureChannels() {
        if (channelsReady || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                appContext.getString(R.string.island_channel_name),
                // HIGH so the island can float; sound and vibration are off on the
                // channel itself because setSilent() on the notification would suppress floating.
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = appContext.getString(R.string.island_channel_desc)
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },
        )
        channelsReady = true
    }

    /**
     * Publish [frame] as [backend]. A user who turned notifications off has no
     * channel to post on, so the frame is dropped rather than thrown back at
     * the caller — the island has nothing to show in that state anyway.
     */
    fun updateFrame(frame: IslandFrame, backend: IslandBackend, notifyId: Int) {
        if (!NotificationManagerCompat.from(appContext).areNotificationsEnabled()) return
        runCatching { manager.notify(notifyId, build(frame, backend, notifyId)) }
    }

    fun cancel(notifyId: Int) {
        manager.cancel(notifyId)
    }

    /**
     * @param firstFloat let the island float up once on the first frame after activation;
     *   later refreshes must not re-interrupt.
     */
    fun build(
        frame: IslandFrame,
        backend: IslandBackend,
        notifyId: Int,
        firstFloat: Boolean = false,
    ): Notification {
        ensureChannels()
        val builder = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_island_notification)
            .setContentTitle(frame.title)
            .setContentText(frame.text?.takeIf { it.isNotBlank() })
            .setContentIntent(contentIntent(notifyId))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        // Let the notification retire itself at the moment its content stops
        // being true. The dismissal alarm is the primary path; this is what
        // covers a system that dropped or delayed it.
        frame.expiresAt?.let { at ->
            val left = at - System.currentTimeMillis()
            if (left > 0L) builder.setTimeoutAfter(left)
        }

        if (backend == IslandBackend.HYPER_ISLAND && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            runCatching { islandExtras(frame, notifyId, firstFloat) }
                .onSuccess(builder::addExtras)
        } else {
            builder.setSilent(true)
            if (backend == IslandBackend.LIVE_UPDATE) {
                // Below Android 16 the request is ignored; only the query needs a guard.
                val canPromote = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
                    runCatching { manager.canPostPromotedNotifications() }.getOrDefault(true)
                } else {
                    true
                }
                builder.setRequestPromotedOngoing(canPromote)
                frame.statusLine.takeIf { it.isNotBlank() }?.let(builder::setShortCriticalText)
            }
        }
        return builder.build()
    }

    /**
     * V3 island template: big-island left column = app icon + course name / time,
     * right column = status line / detail; small island = app icon.
     */
    private fun islandExtras(frame: IslandFrame, notifyId: Int, firstFloat: Boolean): Bundle {
        val headline = frame.title.take(40)
        val body = frame.text.orEmpty().take(80)
        val status = frame.statusLine.ifBlank { frame.title }
        return FocusNotification.buildV3 {
            business = BUSINESS_PROGRESS
            this.notifyId = notifyId.toString()
            updatable = true
            isShowNotification = true
            reopen = "reopen"
            timeout = ONGOING_TIMEOUT_MIN
            sequence = sequenceStore.next(notifyId)
            aodTitle = status.take(20)
            ticker = "$headline $status".trim().take(40)
            val appPic = createPicture(PIC_APP, appIcon)
            tickerPic = appPic
            filterWhenNoPermission = false
            showSmallIcon = false
            enableFloat = false
            islandFirstFloat = firstFloat
            hideDeco = false
            if (firstFloat) outEffectSrc = "glow"

            chatInfo {
                title = headline
                content = body
            }
            island {
                islandProperty = 1
                islandTimeout = ONGOING_TIMEOUT_MIN * 60
                dismissIsland = false
                islandOrder = false
                bigIslandArea {
                    imageTextInfoLeft {
                        type = 1
                        picInfo {
                            type = 1
                            pic = appPic
                        }
                        textInfo {
                            title = frame.title.take(16)
                            content = (frame.subTitle ?: "").take(12)
                            showHighlightColor = true
                        }
                    }
                    textInfo = TextInfo().apply {
                        title = status.take(18)
                        content = (frame.detail ?: body).take(32)
                        showHighlightColor = true
                        narrowFont = true
                    }
                }
                smallIslandArea {
                    picInfo {
                        type = 1
                        pic = appPic
                    }
                }
            }
        }
    }

    private fun contentIntent(notifyId: Int): PendingIntent {
        val intent = Intent(appContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            appContext,
            notifyId,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    companion object {
        const val CHANNEL_ID = "schedule_island"
        const val NOTIFICATION_ID = 0x15DA // island

        private const val ONGOING_TIMEOUT_MIN = 24 * 60
        private const val PIC_APP = "miui.focus.pic_progress_app"
        private const val BUSINESS_PROGRESS = "download_progress"
    }
}
