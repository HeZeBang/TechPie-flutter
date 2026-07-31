import 'package:flutter/cupertino.dart';

IconData iosIconForSfSymbol(String? symbol, {required IconData fallback}) {
  return switch (symbol) {
    'arrow.clockwise' ||
    'arrow.counterclockwise' ||
    'arrow.triangle.2.circlepath' =>
      CupertinoIcons.refresh,
    'arrow.down.circle' ||
    'icloud.and.arrow.down' =>
      CupertinoIcons.cloud_download,
    'arrow.right' => CupertinoIcons.chevron_forward,
    'arrow.up.circle' || 'icloud.and.arrow.up' => CupertinoIcons.cloud_upload,
    'arrow.uturn.backward' => CupertinoIcons.arrow_uturn_left,
    'calendar.badge.clock' => CupertinoIcons.calendar,
    'checklist' => CupertinoIcons.check_mark_circled,
    'chevron.left' => CupertinoIcons.back,
    'ellipsis' => CupertinoIcons.ellipsis,
    'ellipsis.circle' => CupertinoIcons.ellipsis_circle,
    'icloud.slash' => CupertinoIcons.cloud,
    'key' => CupertinoIcons.lock,
    'link' || 'link.badge.minus' => CupertinoIcons.link,
    'magnifyingglass' => CupertinoIcons.search,
    'message.badge' => CupertinoIcons.chat_bubble,
    'paperplane.fill' => CupertinoIcons.paperplane_fill,
    'person.crop.circle.badge.plus' => CupertinoIcons.person_add,
    'rectangle.portrait.and.arrow.right' => CupertinoIcons.square_arrow_right,
    'square.and.arrow.down' => CupertinoIcons.square_arrow_down,
    'square.and.arrow.up' => CupertinoIcons.share,
    'trash' => CupertinoIcons.trash,
    _ => fallback,
  };
}
