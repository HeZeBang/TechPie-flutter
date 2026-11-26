import 'package:flutter/widgets.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Unified thin-stroke iconography for TechPie content surfaces.
///
/// Backed by pure-Dart `flutter_lucide` (annotated `@staticIconProvider` so
/// release builds tree-shake unused glyphs cleanly and OHOS needs no native
/// plugin). iOS native navigation bars and tab bars retain SF Symbols.
@staticIconProvider
abstract final class TpIcons {
  // Primary navigation tabs.
  static const IconData home = LucideIcons.house;
  static const IconData schedule = LucideIcons.calendar_days;
  static const IconData deadlines = LucideIcons.clock;
  static const IconData profile = LucideIcons.user;
  static const IconData settings = LucideIcons.settings;

  // Campus features & quick actions.
  static const IconData campusCard = LucideIcons.credit_card;
  static const IconData wallet = LucideIcons.wallet;
  static const IconData qrCode = LucideIcons.qr_code;
  static const IconData scan = LucideIcons.scan_line;
  static const IconData recordings = LucideIcons.video;
  static const IconData classroom = LucideIcons.monitor;
  static const IconData building = LucideIcons.building;
  static const IconData gym = LucideIcons.dumbbell;
  static const IconData activities = LucideIcons.layout_grid;
  static const IconData watch = LucideIcons.watch;
  static const IconData more = LucideIcons.ellipsis;
  static const IconData allowance = LucideIcons.award;
  static const IconData course = LucideIcons.book_open;
  static const IconData graduation = LucideIcons.graduation_cap;

  // Account, privacy & settings.
  static const IconData login = LucideIcons.log_in;
  static const IconData logout = LucideIcons.log_out;
  static const IconData linkedAccounts = LucideIcons.link_2;
  static const IconData sync = LucideIcons.cloud;
  static const IconData refresh = LucideIcons.refresh_cw;
  static const IconData privacy = LucideIcons.shield;
  static const IconData eye = LucideIcons.eye;
  static const IconData eyeOff = LucideIcons.eye_off;
  static const IconData lock = LucideIcons.lock;
  static const IconData bell = LucideIcons.bell;
  static const IconData bellRing = LucideIcons.bell_ring;
  static const IconData palette = LucideIcons.palette;
  static const IconData sun = LucideIcons.sun;
  static const IconData moon = LucideIcons.moon;
  static const IconData amoled = LucideIcons.eclipse;
  static const IconData smartphone = LucideIcons.smartphone;
  static const IconData globe = LucideIcons.globe;
  static const IconData sliders = LucideIcons.sliders_horizontal;

  // Common actions & metadata.
  static const IconData chevronRight = LucideIcons.chevron_right;
  static const IconData chevronLeft = LucideIcons.chevron_left;
  static const IconData add = LucideIcons.plus;
  static const IconData check = LucideIcons.check;
  static const IconData checkCircle = LucideIcons.circle_check;
  static const IconData close = LucideIcons.x;
  static const IconData delete = LucideIcons.trash;
  static const IconData edit = LucideIcons.pencil;
  static const IconData externalLink = LucideIcons.external_link;
  static const IconData feedback = LucideIcons.message_square;
  static const IconData info = LucideIcons.info;
  static const IconData code = LucideIcons.code;
  static const IconData bug = LucideIcons.bug;
  static const IconData location = LucideIcons.map_pin;
  static const IconData document = LucideIcons.file_text;
  static const IconData download = LucideIcons.download;
  static const IconData filter = LucideIcons.list_filter;
  static const IconData search = LucideIcons.search;
  static const IconData calendar = LucideIcons.calendar;
  static const IconData calendarPlus = LucideIcons.calendar_plus;
  static const IconData calendarCheck = LucideIcons.calendar_check;
  static const IconData sparkles = LucideIcons.sparkles;
  static const IconData activity = LucideIcons.activity;
  static const IconData clock = LucideIcons.clock;
  static const IconData copy = LucideIcons.copy;
  static const IconData repeat = LucideIcons.repeat;
  static const IconData help = LucideIcons.info;
  static const IconData unlink = LucideIcons.unlink;
  static const IconData alertCircle = LucideIcons.circle_exclamation_point;
  static const IconData warning = LucideIcons.triangle_exclamation_point;
  static const IconData inbox = LucideIcons.inbox;
  static const IconData command = LucideIcons.command;
  static const IconData wifiOff = LucideIcons.wifi_off;

  // Desktop sidebar chrome.
  static const IconData sidebar = LucideIcons.panel_left;
  static const IconData sidebarCollapse = LucideIcons.panel_left_close;
  static const IconData sidebarExpand = LucideIcons.panel_left_open;
}
