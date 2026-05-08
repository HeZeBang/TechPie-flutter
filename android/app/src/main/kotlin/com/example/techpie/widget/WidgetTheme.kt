package com.example.techpie.widget

import android.content.Context
import android.content.res.Configuration
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.glance.LocalContext
import androidx.glance.color.ColorProviders
import androidx.glance.material3.ColorProviders as Material3ColorProviders
import com.example.techpie.widget.data.FlutterPrefs

/**
 * Builds a Glance [ColorProviders] mirroring the user's Flutter theme:
 *   - SharedPreferences key `theme_mode`  ∈ {system, light, dark, amoled}
 *   - SharedPreferences key `color_scheme` ∈ {system, techRed}
 *
 * - `system` color scheme defers to the platform: on Android 12+ Glance's
 *   default already pulls in dynamic color from the system, so we just
 *   fall back to the default palette built around `Color.Unspecified` —
 *   which Glance interpolates with the system tonal palette.
 * - `techRed` overrides primary to the app's seed (#A30B19).
 * - `amoled` forces a near-black surface regardless of seed.
 *
 * NOTE: Glance does not support `MaterialTheme.colorScheme.fromSeed(...)`,
 * so we hand-pick a small palette per mode rather than re-deriving every
 * tonal step from a seed. This is "good enough" for widget surfaces.
 */
object WidgetTheme {
    private const val TECH_RED = 0xFFA30B19.toInt()
    private const val TECH_RED_LIGHT_CONTAINER = 0xFFFFDAD6.toInt()
    private const val TECH_RED_DARK_CONTAINER = 0xFF93000A.toInt()

    private fun isSystemDark(context: Context): Boolean {
        val mask = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return mask == Configuration.UI_MODE_NIGHT_YES
    }

    private data class Settings(val mode: String, val scheme: String)

    private fun read(context: Context): Settings {
        val p = FlutterPrefs.open(context)
        return Settings(
            mode = FlutterPrefs.string(p, "theme_mode") ?: "system",
            scheme = FlutterPrefs.string(p, "color_scheme") ?: "system",
        )
    }

    @Composable
    fun providers(): ColorProviders {
        val context = LocalContext.current
        val s = read(context)
        val dark = when (s.mode) {
            "light" -> false
            "dark", "amoled" -> true
            else -> isSystemDark(context)
        }
        val amoled = s.mode == "amoled"
        val techRed = s.scheme == "techRed"

        val light: ColorScheme = buildScheme(dark = false, amoled = false, techRed = techRed)
        val darkScheme: ColorScheme = buildScheme(dark = true, amoled = amoled, techRed = techRed)

        // Glance picks light/dark from the system at render time, so we always
        // pass both. The widget then matches whatever Android decides for its
        // night-mode resolution. We additionally honor explicit user selection
        // by collapsing both schemes to the chosen brightness.
        return when (s.mode) {
            "light" -> Material3ColorProviders(light = light, dark = light)
            "dark", "amoled" -> Material3ColorProviders(light = darkScheme, dark = darkScheme)
            else -> if (dark) Material3ColorProviders(light = darkScheme, dark = darkScheme)
                    else Material3ColorProviders(light = light, dark = light)
        }
    }

    private fun buildScheme(dark: Boolean, amoled: Boolean, techRed: Boolean): ColorScheme {
        val base = if (dark) darkColorScheme() else lightColorScheme()
        val primary = if (techRed) Color(TECH_RED) else base.primary
        val onPrimary = if (techRed) Color.White else base.onPrimary
        val primaryContainer = if (techRed) {
            if (dark) Color(TECH_RED_DARK_CONTAINER) else Color(TECH_RED_LIGHT_CONTAINER)
        } else base.primaryContainer

        val surface = when {
            amoled -> Color.Black
            dark -> Color(0xFF121212)
            else -> Color(0xFFFFFBFE)
        }
        val onSurface = if (dark) Color.White else Color(0xFF1C1B1F)
        val onSurfaceVariant = if (dark) Color(0xFFCAC4D0) else Color(0xFF49454F)
        val outline = if (dark) Color(0xFF49454F) else Color(0xFFCAC4D0)

        return base.copy(
            primary = primary,
            onPrimary = onPrimary,
            primaryContainer = primaryContainer,
            onPrimaryContainer = if (techRed && dark) Color(0xFFFFDAD6)
                                 else if (techRed) Color(0xFF410002)
                                 else base.onPrimaryContainer,
            surface = surface,
            onSurface = onSurface,
            onSurfaceVariant = onSurfaceVariant,
            outline = outline,
            background = surface,
            onBackground = onSurface,
        )
    }
}
