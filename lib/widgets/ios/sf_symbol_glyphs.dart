import 'package:flutter/cupertino.dart';

/// The Flutter glyph that stands in for an SF Symbol before iOS 26.
///
/// Before iOS 26 cupertino_native_better falls back to Flutter widgets, but it
/// still draws each SF Symbol as a native platform view (CNIcon). That view
/// takes the touch, so a tab or button only responds outside its icon. Chrome
/// below iOS 26 therefore draws these glyphs instead. Unknown names fall back
/// to a neutral glyph rather than to a native view.
IconData cupertinoGlyphFor(String sfSymbol) =>
    _glyphs[sfSymbol] ?? CupertinoIcons.circle;

const _glyphs = <String, IconData>{
  'arrow.clockwise': CupertinoIcons.arrow_clockwise,
  'arrow.counterclockwise': CupertinoIcons.arrow_counterclockwise,
  'arrow.down.circle': CupertinoIcons.arrow_down_circle,
  'arrow.triangle.2.circlepath': CupertinoIcons.arrow_2_circlepath,
  'arrow.up.circle': CupertinoIcons.arrow_up_circle,
  'arrow.uturn.backward': CupertinoIcons.arrow_uturn_left,
  'calendar': CupertinoIcons.calendar,
  'calendar.badge.clock': CupertinoIcons.calendar_badge_plus,
  'calendar.circle.fill': CupertinoIcons.calendar_circle_fill,
  'checklist': CupertinoIcons.list_bullet,
  'checkmark': CupertinoIcons.checkmark,
  'checkmark.circle': CupertinoIcons.checkmark_circle,
  'checkmark.circle.fill': CupertinoIcons.checkmark_circle_fill,
  'checkmark.shield': CupertinoIcons.checkmark_shield,
  'chevron.left': CupertinoIcons.back,
  'ellipsis': CupertinoIcons.ellipsis,
  'ellipsis.circle': CupertinoIcons.ellipsis_circle,
  'gearshape': CupertinoIcons.gear_alt,
  'gearshape.fill': CupertinoIcons.gear_alt_fill,
  'house': CupertinoIcons.house,
  'house.fill': CupertinoIcons.house_fill,
  'icloud.and.arrow.down': CupertinoIcons.cloud_download,
  'icloud.and.arrow.up': CupertinoIcons.cloud_upload,
  'icloud.slash': CupertinoIcons.cloud,
  'info.circle': CupertinoIcons.info_circle,
  'key': CupertinoIcons.lock,
  'link': CupertinoIcons.link,
  'link.badge.minus': CupertinoIcons.link,
  'magnifyingglass': CupertinoIcons.search,
  'paperplane.fill': CupertinoIcons.paperplane_fill,
  'person.crop.circle.badge.checkmark': CupertinoIcons.person_crop_circle_badge_checkmark,
  'person.crop.circle.badge.plus': CupertinoIcons.person_crop_circle_badge_plus,
  'plus.rectangle.on.rectangle': CupertinoIcons.plus_rectangle_on_rectangle,
  'qrcode.viewfinder': CupertinoIcons.qrcode_viewfinder,
  'rectangle.portrait.and.arrow.right': CupertinoIcons.square_arrow_right,
  'square.and.arrow.down': CupertinoIcons.square_arrow_down,
  'square.grid.2x2': CupertinoIcons.square_grid_2x2,
  'trash': CupertinoIcons.trash,
  'xmark': CupertinoIcons.xmark,
};
