package club.geekpie.techpie

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import club.geekpie.techpie.widgets.EcardWidgetResolver
import club.geekpie.techpie.widgets.WidgetRefreshScheduler
import club.geekpie.techpie.widgets.WidgetSnapshotStore
import club.geekpie.techpie.widgets.WidgetUiHelper

class EcardPayWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            WidgetUiHelper.ACTION_TOGGLE_ECARD_MASK -> {
                WidgetSnapshotStore(context).toggleEcardMaskOverride()
                updateAll(context, AppWidgetManager.getInstance(context))
            }
            WidgetUiHelper.ACTION_REFRESH_WIDGETS -> {
                updateAll(context, AppWidgetManager.getInstance(context))
            }
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        updateIds(context, manager, ids)
        WidgetRefreshScheduler.scheduleNextRefresh(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, manager, appWidgetId, newOptions)
        updateIds(context, manager, intArrayOf(appWidgetId))
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        WidgetRefreshScheduler.scheduleNextRefresh(context)
    }

    companion object {
        private const val REQUEST_CODE_BASE_OPEN = 1100
        private const val REQUEST_CODE_MASK_TOGGLE = 1201

        fun updateAll(context: Context, manager: AppWidgetManager) {
            val ids = manager.getAppWidgetIds(ComponentName(context, EcardPayWidgetProvider::class.java))
            if (ids.isNotEmpty()) updateIds(context, manager, ids)
        }

        private fun updateIds(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val store = WidgetSnapshotStore(context)
            val snapshot = store.loadEcard()
            val presentation = EcardWidgetResolver.resolve(snapshot, store.getEcardMaskOverride())

            for (id in ids) {
                val (minWidth, _) = WidgetUiHelper.minDimensionsDp(manager, id)
                val wide = minWidth >= 220
                val views = RemoteViews(
                    context.packageName,
                    if (wide) R.layout.ecard_pay_widget_wide else R.layout.ecard_pay_widget,
                )
                val openPay = WidgetUiHelper.openUriPendingIntent(
                    context = context,
                    requestCode = REQUEST_CODE_BASE_OPEN + id,
                    uriString = "techpie://ecard/pay",
                )
                views.setOnClickPendingIntent(R.id.ecard_widget_root, openPay)

                val statusText = if (!presentation.configured) {
                    context.getString(R.string.widget_ecard_unbound)
                } else {
                    presentation.displayBalanceText
                }

                if (wide) {
                    views.setTextViewText(R.id.ecard_widget_balance, statusText)
                    views.setTextViewText(
                        R.id.ecard_widget_subtitle,
                        context.getString(
                            if (presentation.configured) {
                                R.string.ecard_widget_subtitle
                            } else {
                                R.string.widget_ecard_bind_hint
                            },
                        ),
                    )
                    if (presentation.configured && !snapshot?.balanceText.isNullOrBlank()) {
                        views.setViewVisibility(R.id.ecard_widget_mask_btn, View.VISIBLE)
                        views.setImageViewResource(
                            R.id.ecard_widget_mask_btn,
                            if (presentation.masked) R.drawable.ic_widget_eye_off else R.drawable.ic_widget_eye,
                        )
                        views.setContentDescription(
                            R.id.ecard_widget_mask_btn,
                            context.getString(
                                if (presentation.masked) {
                                    R.string.widget_ecard_show_balance
                                } else {
                                    R.string.widget_ecard_hide_balance
                                },
                            ),
                        )
                        views.setOnClickPendingIntent(
                            R.id.ecard_widget_mask_btn,
                            WidgetUiHelper.broadcastPendingIntent(
                                context = context,
                                requestCode = REQUEST_CODE_MASK_TOGGLE,
                                receiverClass = EcardPayWidgetProvider::class.java,
                                action = WidgetUiHelper.ACTION_TOGGLE_ECARD_MASK,
                            ),
                        )
                    } else {
                        views.setViewVisibility(R.id.ecard_widget_mask_btn, View.GONE)
                    }
                } else {
                    if (presentation.configured && !snapshot?.balanceText.isNullOrBlank()) {
                        views.setViewVisibility(R.id.ecard_widget_balance, View.VISIBLE)
                        views.setTextViewText(R.id.ecard_widget_balance, presentation.displayBalanceText)
                    } else {
                        views.setViewVisibility(R.id.ecard_widget_balance, View.GONE)
                    }
                }

                manager.updateAppWidget(id, views)
            }
        }
    }
}
