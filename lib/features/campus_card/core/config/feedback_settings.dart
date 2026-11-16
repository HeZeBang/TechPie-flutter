import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/models/feedback_models.dart';

final feedbackSettingsProvider = AsyncNotifierProvider.family<
    FeedbackSettingsController, FeedbackOptions, FeedbackScenario>(
  FeedbackSettingsController.new,
);

final class FeedbackSettingsController
    extends FamilyAsyncNotifier<FeedbackOptions, FeedbackScenario> {
  late FeedbackScenario _scenario;
  int _generation = 0;

  @override
  Future<FeedbackOptions> build(FeedbackScenario arg) {
    _scenario = arg;
    _generation++;
    ref.onDispose(() => _generation++);
    return ref.watch(appRuntimeProvider).feedback.settingsFor(arg);
  }

  Future<void> setEnabled(FeedbackChannel channel, bool enabled) async {
    final generation = _generation;
    final port = ref.read(appRuntimeProvider).feedback;
    await port.setEnabled(_scenario, channel, enabled);
    final options = await port.settingsFor(_scenario);
    if (generation == _generation) state = AsyncData(options);
  }
}
