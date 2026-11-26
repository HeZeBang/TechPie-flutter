const maxPinnedQuickFeatures = 5;

/// The campus card has its own home tile. Older preferences may also contain duplicates.
List<String> pinnedShortcutIds(Iterable<String> ids) =>
    ids.where((id) => id != 'campus_card').toSet().take(maxPinnedQuickFeatures).toList();
