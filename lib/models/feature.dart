import 'package:flutter/material.dart';

import '../features/campus_card/app/app_providers.dart';
import '../pages/campus_card_page.dart';
import '../pages/egate_app_page.dart';
import '../pages/elrc_recordings_page.dart';
import '../pages/oa_gym_page.dart';
import '../pages/student_allowance_page.dart';
import '../theme/tp_icons.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_page_navigation.dart';

enum FeatureMode {
  native,
  webviewWithCookie,
}

enum CookieType {
  ecourse,
  eams,
  egateApp,
}

class Feature {
  final String id;
  final String description;
  final FeatureMode mode;
  final String? url;
  final CookieType? cookieType;
  final Icon icon;
  final void Function(BuildContext context)? nativeEntry;

  Feature({
    required this.id,
    required this.description,
    required this.mode,
    this.url,
    this.cookieType,
    required this.icon,
    this.nativeEntry,
  });
}

final _mobileEntries = _buildEntries(
  campusCard: Feature(
    id: 'campus_card',
    description: '校园卡',
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(
      context,
      builder: (_) => const CampusCardPage(
        entry: CampusCardEntry.paymentCode,
      ),
    ),
    icon: const Icon(TpIcons.wallet),
  ),
);
final _desktopEntries = _buildEntries();
List<Feature> get featureEntries =>
    supportsCampusCard() ? _mobileEntries : _desktopEntries;

List<Feature> _buildEntries({Feature? campusCard}) => [
  Feature(
    id: 'elrc_recordings',
    description: '课程录播',
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(
      context,
      builder: (_) => const ElrcRecordingsPage(),
    ),
    icon: const Icon(TpIcons.recordings),
  ),
  Feature(
    id: 'ecourse',
    description: 'E云课堂',
    mode: FeatureMode.webviewWithCookie,
    url: 'https://ecourse.shanghaitech.edu.cn:8080/',
    cookieType: CookieType.ecourse,
    icon: const Icon(TpIcons.classroom),
  ),
  Feature(
    id: 'student_leave',
    description: '学生请假',
    mode: FeatureMode.webviewWithCookie,
    url: 'https://egate.shanghaitech.edu.cn/xsfw/sys/ydxsqjxs/index.html#/',
    cookieType: CookieType.egateApp,
    icon: const Icon(TpIcons.building),
  ),
  if (campusCard != null) campusCard,
  Feature(
    id: 'oa_gym',
    description: '场馆预约',
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(
      context,
      builder: (_) => const OaGymPage(),
    ),
    icon: const Icon(TpIcons.gym),
  ),
  Feature(
    id: 'egate_xshd',
    description: '学生活动',
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(
      context,
      builder: (_) => const EgateAppPage(),
    ),
    icon: const Icon(TpIcons.scan),
  ),
  Feature(
    id: 'student_allowance',
    description: '学生津贴',
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(
      context,
      builder: (_) => const StudentAllowancePage(),
    ),
    icon: const Icon(TpIcons.allowance),
  ),
];

final moreFeature = Feature(
  id: 'more',
  description: '更多',
  mode: FeatureMode.native,
  nativeEntry: (context) {},
  icon: const Icon(TpIcons.more),
);
