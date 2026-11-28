import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../widgets/app_shell/desktop/desktop_command_palette.dart';

typedef SpotlightCommandHandler = void Function(String commandId);

/// Mirrors desktop command-palette entries into macOS Spotlight via
/// `techpie/spotlight` and forwards Spotlight item activations back to Flutter.
///
/// Only non-sensitive command metadata (ID, title, subtitle, group, keywords)
/// is sent to CoreSpotlight.
final class SpotlightService {
  SpotlightService({
    MethodChannel? channel,
    bool? enabled,
  })  : _channel = channel ?? const MethodChannel('techpie/spotlight'),
        _enabled =
            enabled ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS);

  final MethodChannel _channel;
  final bool _enabled;

  bool get enabled => _enabled;

  SpotlightCommandHandler? _onOpenCommand;
  String? _pendingCommandId;
  String? _lastSyncedDigest;
  bool _initialized = false;
  bool _disposed = false;
  Future<void> _writes = Future<void>.value();

  void initialize({SpotlightCommandHandler? onOpenCommand}) {
    if (onOpenCommand != null) {
      _onOpenCommand = onOpenCommand;
    }
    if (_initialized || _disposed) {
      _flushPendingCommand();
      return;
    }
    _initialized = true;
    if (!_enabled) return;

    _channel.setMethodCallHandler(_handleMethodCall);
    unawaited(_consumePendingCommand());
  }

  void setCommandHandler(SpotlightCommandHandler? handler) {
    _onOpenCommand = handler;
    if (handler != null) {
      _flushPendingCommand();
    }
  }

  /// Wait for queued Spotlight index writes to finish (for tests).
  Future<void> flush() => _writes;

  /// Syncs the given [items] to macOS Spotlight, skipping redundant writes
  /// when the serialized payload has not changed.
  Future<void> syncCommands(List<DesktopCommandItem> items) {
    if (!_enabled || _disposed) return Future<void>.value();
    final payload = serializeCommands(items);
    final digest = jsonEncode(payload);
    if (digest == _lastSyncedDigest) return _writes;
    _lastSyncedDigest = digest;

    _writes = _writes.then((_) async {
      if (_disposed) return;
      try {
        await _channel.invokeMethod<bool>('syncItems', payload);
      } on MissingPluginException {
        // Native bridge unavailable (e.g. non-macOS test environment).
      } on PlatformException {
        // Spotlight indexing is best-effort; allow retry on next sync.
        if (_lastSyncedDigest == digest) _lastSyncedDigest = null;
      }
    });
    return _writes;
  }

  /// High-frequency commands that receive top CoreSpotlight `rankingHint`.
  static const Set<String> _highPriorityIds = {
    'tab.schedule',
    'tab.deadlines',
    'feature.elrc_recordings',
  };

  /// Computes a CoreSpotlight `rankingHint` (0–100) for [id].
  static int rankingHintFor(String id) {
    if (_highPriorityIds.contains(id)) return 100;
    if (id.startsWith('tab.')) return 85;
    if (id.startsWith('feature.')) return 80;
    return 50;
  }

  /// Donates an in-app command execution to macOS Spotlight (`lastUsedDate` +
  /// `NSUserActivity`) so frequently used commands climb toward Top Hit.
  Future<void> donateCommandUsage(DesktopCommandItem item) {
    if (!_enabled || _disposed) return Future<void>.value();
    final payload = serializeCommand(item);
    if (payload == null) return Future<void>.value();

    _writes = _writes.then((_) async {
      if (_disposed) return;
      try {
        await _channel.invokeMethod<bool>('donateUsage', payload);
      } on MissingPluginException {
        // Native bridge unavailable.
      } on PlatformException {
        // Best-effort usage donation.
      }
    });
    return _writes;
  }

  /// Removes all TechPie command items from Spotlight.
  Future<void> clearCommands() {
    if (!_enabled || _disposed) return Future<void>.value();
    _lastSyncedDigest = null;
    _writes = _writes.then((_) async {
      if (_disposed) return;
      try {
        await _channel.invokeMethod<bool>('clearItems');
      } on MissingPluginException {
        // Native bridge unavailable.
      } on PlatformException {
        // Best-effort cleanup.
      }
    });
    return _writes;
  }

  /// Converts a single [DesktopCommandItem] into the wire format expected by
  /// `SpotlightBridge.swift`, or `null` if its ID or title is empty.
  static Map<String, Object>? serializeCommand(DesktopCommandItem item) {
    final id = item.id.trim();
    final title = item.title.trim();
    if (id.isEmpty || title.isEmpty) return null;

    final aliasSeen = <String>{};
    final aliases = <String>[];
    for (final raw in item.aliases) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (aliasSeen.add(trimmed.toLowerCase())) {
        aliases.add(trimmed);
      }
    }

    final keywordSeen = <String>{};
    final keywords = <String>[];
    void addKeyword(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      if (keywordSeen.add(trimmed.toLowerCase())) {
        keywords.add(trimmed);
      }
    }

    for (final alias in aliases) {
      addKeyword(alias);
    }
    for (final raw in item.keywords) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      addKeyword(trimmed);
      final joined = trimmed.replaceAll(RegExp(r"[\s'\u2019\u3000]+"), '');
      if (joined != trimmed) {
        addKeyword(joined);
      }
    }

    return <String, Object>{
      'id': id,
      'title': title,
      'subtitle': item.subtitle.trim(),
      'group': item.group.trim(),
      'aliases': List<String>.unmodifiable(aliases),
      'keywords': List<String>.unmodifiable(keywords),
      'rankingHint': rankingHintFor(id),
    };
  }

  /// Converts [DesktopCommandItem]s into the wire format expected by
  /// `SpotlightBridge.swift`.
  ///
  /// Spaced multi-syllable Pinyin keywords (e.g. `"ke biao"`) are expanded to
  /// emit both the spaced form (matched by live Chinese IME preedit in
  /// Spotlight) and the joined form (`"kebiao"`, matched when typed without
  /// spaces).
  static List<Map<String, Object>> serializeCommands(
    List<DesktopCommandItem> items,
  ) {
    final seen = <String>{};
    final result = <Map<String, Object>>[];
    for (final item in items) {
      final serialized = serializeCommand(item);
      if (serialized == null) continue;
      final id = serialized['id'] as String;
      if (!seen.add(id)) continue;
      result.add(serialized);
    }
    return result;
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (_disposed) return;
    if (call.method == 'openCommand') {
      final raw = call.arguments;
      if (raw is String && raw.trim().isNotEmpty) {
        _pendingCommandId = raw.trim();
        _flushPendingCommand();
      }
    }
  }

  Future<void> _consumePendingCommand() async {
    if (_disposed || !_enabled) return;
    try {
      final raw = await _channel.invokeMethod<String>('consumePendingCommand');
      if (_disposed) return;
      if (raw != null && raw.trim().isNotEmpty) {
        _pendingCommandId = raw.trim();
        _flushPendingCommand();
      }
    } on MissingPluginException {
      // Native bridge unavailable.
    } on PlatformException {
      // Best-effort cold-start check.
    }
  }

  void _flushPendingCommand() {
    final commandId = _pendingCommandId;
    final handler = _onOpenCommand;
    if (_disposed || commandId == null || handler == null) return;
    _pendingCommandId = null;
    if (_enabled) {
      unawaited(_acknowledgePendingCommand());
    }
    handler(commandId);
  }

  Future<void> _acknowledgePendingCommand() async {
    try {
      await _channel.invokeMethod<void>('acknowledgePendingCommand');
    } on MissingPluginException {
      // Native bridge unavailable.
    } on PlatformException {
      // Best-effort ack.
    }
  }

  void dispose() {
    _disposed = true;
    _onOpenCommand = null;
    if (_initialized && _enabled) {
      _channel.setMethodCallHandler(null);
    }
  }
}
