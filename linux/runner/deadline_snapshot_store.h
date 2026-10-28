#pragma once

#include <gio/gio.h>

// Display-only v1 snapshot. Paths always belong to the current user's XDG data.
gchar* deadline_snapshot_path();
gboolean deadline_snapshot_valid(const gchar* json, gsize length);
gboolean deadline_snapshot_write(const gchar* json, GError** error);
gboolean deadline_snapshot_clear(GError** error);
gboolean deadline_uri_valid(const gchar* uri);
