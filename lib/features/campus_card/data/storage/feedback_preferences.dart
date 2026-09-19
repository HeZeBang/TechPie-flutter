import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/feedback_models.dart';

/// One cache serves playback and settings, including when persistence fails.
final class FeedbackPreferences {
  final _options = <FeedbackScenario, FeedbackOptions>{
    for (final scenario in FeedbackScenario.values)
      scenario:
          FeedbackOptions(sound: scenario != FeedbackScenario.interaction),
  };
  Future<void>? _restoring;

  Future<void> _ready() => _restoring ??= _restore();

  static String key(FeedbackScenario scenario, FeedbackChannel channel) =>
      'geekpay.feedback.${scenario.name}.${channel.name}';

  Future<void> _restore() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      for (final scenario in FeedbackScenario.values) {
        _options[scenario] = FeedbackOptions(
          vibration:
              preferences.getBool(key(scenario, FeedbackChannel.vibration)) ??
                  true,
          sound: scenario != FeedbackScenario.interaction &&
              (preferences.getBool(key(scenario, FeedbackChannel.sound)) ??
                  true),
        );
      }
    } catch (_) {
      // Defaults remain usable if platform preferences are temporarily unavailable.
    }
  }

  Future<FeedbackOptions> read(FeedbackScenario scenario) async {
    await _ready();
    return _options[scenario]!;
  }

  Future<void> setEnabled(
    FeedbackScenario scenario,
    FeedbackChannel channel,
    bool enabled,
  ) async {
    await _ready();
    _options[scenario] = _options[scenario]!.withEnabled(channel, enabled);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(key(scenario, channel), enabled);
    } catch (_) {
      // Playback keeps using the user's in-process choice.
    }
  }
}
