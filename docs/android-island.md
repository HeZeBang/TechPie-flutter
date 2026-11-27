# Cached schedule and deadline notifications

This optional Android feature displays the current class, next class within 90 minutes or a pending deadline within 24 hours. It chooses HyperOS focus notifications when granted, Android 16 promoted ongoing notifications when available, and ordinary persistent notifications otherwise. Native alarms carry cached frames for three days, restore future events after reboot/update and expire stale content without a running Flutter process.

The switch defaults off and requests notification permission without running a foreground service or background network polling. Cached alarm content is removed when the feature is disabled, and source changes immediately replace the displayed state.

HyperOS SDK calls are guarded at API 27; API 24–26 use only the ordinary notification path. The library's minSdk declaration is narrowly overridden for that guarded path. Android 16 promoted ongoing APIs are supplied by AndroidX Core 1.18.0.
