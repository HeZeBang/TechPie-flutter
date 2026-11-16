enum FeedbackScenario { paymentSuccess, networkDisconnected, interaction }

enum FeedbackChannel { vibration, sound }

final class FeedbackOptions {
  const FeedbackOptions({this.vibration = true, this.sound = true});

  final bool vibration;
  final bool sound;

  FeedbackOptions withEnabled(FeedbackChannel channel, bool enabled) =>
      FeedbackOptions(
        vibration: channel == FeedbackChannel.vibration ? enabled : vibration,
        sound: channel == FeedbackChannel.sound ? enabled : sound,
      );
}
