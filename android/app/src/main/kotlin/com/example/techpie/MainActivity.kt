package com.example.techpie

import androidx.lifecycle.lifecycleScope
import com.example.techpie.widget.SystemEventReceiver
import io.flutter.embedding.android.FlutterActivity
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    /**
     * When the user backgrounds the app, refresh both home-screen widgets so
     * any newly-cached schedule/assignment data appears the next time the user
     * looks at their home screen.
     */
    override fun onStop() {
        super.onStop()
        lifecycleScope.launch {
            SystemEventReceiver.refreshAll(applicationContext)
        }
    }
}
