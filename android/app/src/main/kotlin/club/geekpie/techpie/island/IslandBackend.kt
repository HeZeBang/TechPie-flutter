package club.geekpie.techpie.island

/**
 * The three display tiers for the schedule island, in order of preference.
 *
 * - [HYPER_ISLAND]: Xiaomi HyperOS focus notification / super-island (V3 template).
 *   Only floats on whitelisted HyperOS devices with the focus-notification grant.
 * - [LIVE_UPDATE]: Android 16 live updates (promoted ongoing), status-bar capsule.
 * - [PLAIN]: standard persistent notification, works everywhere.
 */
enum class IslandBackend { HYPER_ISLAND, LIVE_UPDATE, PLAIN }

object IslandBackends {

    /** Best available tier: island > live update > plain. */
    fun resolve(islandAvailable: Boolean, liveUpdateGranted: Boolean): IslandBackend = when {
        islandAvailable -> IslandBackend.HYPER_ISLAND
        liveUpdateGranted -> IslandBackend.LIVE_UPDATE
        else -> IslandBackend.PLAIN
    }
}
