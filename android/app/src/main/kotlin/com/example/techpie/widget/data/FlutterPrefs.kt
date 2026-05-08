package com.example.techpie.widget.data

import android.content.Context
import android.content.SharedPreferences

/**
 * Reads the SharedPreferences file written by Flutter's `shared_preferences`
 * plugin. The plugin uses file name `FlutterSharedPreferences` and prefixes
 * every key with `flutter.`. We never write here — widgets are passive readers.
 */
object FlutterPrefs {
    private const val FILE_NAME = "FlutterSharedPreferences"
    private const val KEY_PREFIX = "flutter."

    fun open(context: Context): SharedPreferences =
        context.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)

    fun string(prefs: SharedPreferences, key: String): String? =
        prefs.getString(KEY_PREFIX + key, null)
}
