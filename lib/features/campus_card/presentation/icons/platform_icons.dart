import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

@immutable
final class GpPlatformIcon {
  const GpPlatformIcon({required this.apple, required this.android});

  final IconData apple;
  final IconData android;

  IconData call(BuildContext context) =>
      forPlatform(Theme.of(context).platform);

  IconData forPlatform(TargetPlatform platform) => switch (platform) {
        TargetPlatform.iOS || TargetPlatform.macOS => apple,
        _ => android,
      };
}

/// Semantic icon pairs used by GeekPay's Flutter interface.
///
/// Apple platforms use Cupertino's bundled symbol font. Android and other
/// platforms use Material Icons. App-owned painted geometry and branded image
/// assets remain identical on every platform.
abstract final class GpPlatformIcons {
  static const brightness = GpPlatformIcon(
    apple: CupertinoIcons.brightness,
    android: Icons.brightness_high_outlined,
  );
  static const vibration = GpPlatformIcon(
    apple: CupertinoIcons.device_phone_portrait,
    android: Icons.vibration_rounded,
  );
  static const sound = GpPlatformIcon(
    apple: CupertinoIcons.speaker_2,
    android: Icons.volume_up_rounded,
  );
  static const homeWidget = GpPlatformIcon(
    apple: CupertinoIcons.square_grid_2x2,
    android: Icons.widgets_outlined,
  );
  static const qrCode = GpPlatformIcon(
    apple: CupertinoIcons.qrcode,
    android: Icons.qr_code_2_rounded,
  );
  static const back = GpPlatformIcon(
    apple: CupertinoIcons.chevron_back,
    android: Icons.arrow_back_rounded,
  );
  static const forward = GpPlatformIcon(
    apple: CupertinoIcons.chevron_forward,
    android: Icons.chevron_right_rounded,
  );
  static const close = GpPlatformIcon(
    apple: CupertinoIcons.xmark,
    android: Icons.close_rounded,
  );
  static const closeCircleFilled = GpPlatformIcon(
    apple: CupertinoIcons.xmark_circle_fill,
    android: Icons.cancel_rounded,
  );
  static const backspace = GpPlatformIcon(
    apple: CupertinoIcons.delete_left,
    android: Icons.backspace_outlined,
  );
  static const flashOn = GpPlatformIcon(
    apple: CupertinoIcons.bolt_fill,
    android: Icons.flash_on_rounded,
  );
  static const flashOff = GpPlatformIcon(
    apple: CupertinoIcons.bolt,
    android: Icons.flash_off_rounded,
  );
  static const photoLibrary = GpPlatformIcon(
    apple: CupertinoIcons.photo_on_rectangle,
    android: Icons.photo_library_outlined,
  );
  static const errorCircle = GpPlatformIcon(
    apple: CupertinoIcons.exclamationmark_circle,
    android: Icons.error_outline_rounded,
  );
  static const warningFilled = GpPlatformIcon(
    apple: CupertinoIcons.exclamationmark_triangle_fill,
    android: Icons.warning_rounded,
  );
  static const security = GpPlatformIcon(
    apple: CupertinoIcons.lock_shield,
    android: Icons.shield_outlined,
  );
  static const securityFilled = GpPlatformIcon(
    apple: CupertinoIcons.lock_shield_fill,
    android: Icons.shield_rounded,
  );
  static const password = GpPlatformIcon(
    apple: CupertinoIcons.lock_rotation,
    android: Icons.lock_reset_rounded,
  );
  static const limits = GpPlatformIcon(
    apple: CupertinoIcons.slider_horizontal_3,
    android: Icons.tune_rounded,
  );
  static const settings = GpPlatformIcon(
    apple: CupertinoIcons.settings,
    android: Icons.settings_outlined,
  );
  static const offline = GpPlatformIcon(
    apple: CupertinoIcons.wifi_slash,
    android: Icons.wifi_off_rounded,
  );
  static const calendar = GpPlatformIcon(
    apple: CupertinoIcons.calendar,
    android: Icons.calendar_month_outlined,
  );
  static const visibility = GpPlatformIcon(
    apple: CupertinoIcons.eye,
    android: Icons.visibility_outlined,
  );
  static const visibilityOff = GpPlatformIcon(
    apple: CupertinoIcons.eye_slash,
    android: Icons.visibility_off_outlined,
  );
  static const language = GpPlatformIcon(
    apple: CupertinoIcons.globe,
    android: Icons.language_rounded,
  );
  static const verifiedUser = GpPlatformIcon(
    apple: CupertinoIcons.person_crop_circle_badge_checkmark,
    android: Icons.verified_user_outlined,
  );
  static const card = GpPlatformIcon(
    apple: CupertinoIcons.creditcard,
    android: Icons.credit_card_rounded,
  );
  static const successCircle = GpPlatformIcon(
    apple: CupertinoIcons.check_mark_circled_solid,
    android: Icons.check_circle_rounded,
  );
  static const refresh = GpPlatformIcon(
    apple: CupertinoIcons.refresh,
    android: Icons.refresh_rounded,
  );
  static const delete = GpPlatformIcon(
    apple: CupertinoIcons.delete,
    android: Icons.delete_outline_rounded,
  );
  static const scan = GpPlatformIcon(
    apple: CupertinoIcons.qrcode_viewfinder,
    android: Icons.qr_code_scanner_rounded,
  );
  static const paymentCode = GpPlatformIcon(
    apple: CupertinoIcons.qrcode,
    android: Icons.qr_code_2_rounded,
  );
  static const info = GpPlatformIcon(
    apple: CupertinoIcons.info,
    android: Icons.info_outline_rounded,
  );
  static const infoCircle = GpPlatformIcon(
    apple: CupertinoIcons.info_circle,
    android: Icons.info_outline_rounded,
  );
  static const debug = GpPlatformIcon(
    apple: CupertinoIcons.hammer,
    android: Icons.bug_report_outlined,
  );
  static const recharge = GpPlatformIcon(
    apple: CupertinoIcons.arrow_down_circle_fill,
    android: Icons.arrow_circle_down_rounded,
  );
  static const gift = GpPlatformIcon(
    apple: CupertinoIcons.gift_fill,
    android: Icons.card_giftcard_rounded,
  );
  static const transfer = GpPlatformIcon(
    apple: CupertinoIcons.arrow_right_circle_fill,
    android: Icons.arrow_circle_right_rounded,
  );
  static const refund = GpPlatformIcon(
    apple: CupertinoIcons.arrow_uturn_left_circle_fill,
    android: Icons.undo_rounded,
  );
  static const adjustment = GpPlatformIcon(
    apple: CupertinoIcons.slider_horizontal_3,
    android: Icons.tune_rounded,
  );
  static const consumption = GpPlatformIcon(
    apple: CupertinoIcons.cart_fill,
    android: Icons.shopping_cart_rounded,
  );

  static const all = <GpPlatformIcon>[
    brightness,
    back,
    forward,
    close,
    closeCircleFilled,
    backspace,
    flashOn,
    flashOff,
    photoLibrary,
    errorCircle,
    warningFilled,
    security,
    securityFilled,
    password,
    limits,
    settings,
    offline,
    calendar,
    visibility,
    visibilityOff,
    language,
    verifiedUser,
    card,
    successCircle,
    refresh,
    delete,
    scan,
    paymentCode,
    info,
    infoCircle,
    debug,
    recharge,
    gift,
    transfer,
    refund,
    adjustment,
    consumption,
  ];
}
