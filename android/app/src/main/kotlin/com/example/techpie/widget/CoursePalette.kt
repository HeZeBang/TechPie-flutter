package com.example.techpie.widget

import androidx.compose.ui.graphics.Color
import androidx.glance.unit.ColorProvider

/**
 * Seven seed colors matching `CourseColor` enum order in
 * lib/models/course.dart. Used for the left edge accent on each course tile.
 */
object CoursePalette {
    private val seeds = listOf(
        Color(0xFF673AB7), // primary - deepPurple
        Color(0xFF607D8B), // secondary - blueGrey
        Color(0xFF009688), // tertiary - teal
        Color(0xFFE53935), // error - red
        Color(0xFF43A047), // green
        Color(0xFFE64A19), // orange (deepOrange)
        Color(0xFFEC407A), // pink
    )

    fun accent(index: Int): ColorProvider =
        ColorProvider(seeds[((index % seeds.size) + seeds.size) % seeds.size])
}
