package club.geekpie.techpie.widgets

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

class WidgetRefreshWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {
    override fun doWork(): Result {
        WidgetRefreshScheduler.updateAllAndSchedule(applicationContext)
        return Result.success()
    }
}
