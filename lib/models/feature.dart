import 'dart:async';

import 'package:flutter/material.dart';

import '../features/campus_card/app/app_providers.dart';
import '../pages/academic_certificates_page.dart';
import '../pages/campus_card_page.dart';
import '../pages/campus_jobs_page.dart';
import '../pages/course_catalog_search_page.dart';
import '../pages/egate_app_page.dart';
import '../pages/elearning_hub_page.dart';
import '../pages/elrc_recordings_page.dart';
import '../pages/grades_page.dart';
import '../pages/holiday_travel_page.dart';
import '../pages/oa_gym_page.dart';
import '../pages/pnp_minor_page.dart';
import '../pages/student_allowance_page.dart';
import '../pages/student_leave_page.dart';
import '../pages/study_plan_page.dart';
import '../services/service_provider.dart';
import '../theme/tp_icons.dart';
import '../widgets/adaptive_page_navigation.dart';
import 'quick_shortcuts.dart';

enum CampusServiceCategory {
  academics('学业与课程'),
  activities('活动与岗位'),
  life('日常办事'),
  special('专项事务');

  const CampusServiceCategory(this.label);
  final String label;
}

enum FeatureMode {
  native,
  webviewWithCookie,
}

enum CookieType {
  ecourse,
  eams,
  egateApp,
  elearning,
}

class Feature {
  final String id;
  final String description;
  final FeatureMode mode;
  final String? url;
  final CookieType? cookieType;
  final CampusServiceCategory category;
  final List<String> keywords;
  final bool pinnedByDefault;
  final String subtitle;
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
    this.category = CampusServiceCategory.life,
    this.keywords = const [],
    this.pinnedByDefault = false,
    this.subtitle = '',
  });
}

final featureEntries = <Feature>[
  Feature(
    id: 'elrc_recordings',
    category: CampusServiceCategory.academics,
    subtitle: '按课程查找和播放录播',
    keywords: const ['elrc', 'recordings', 'lubo', '回放'],
    pinnedByDefault: true,
    description: '课程录播',
    mode: FeatureMode.native,
    nativeEntry: (context) {
      final visit = ServiceProvider.of(context).telemetry?.beginRecording();
      unawaited(pushAdaptivePage<void>(context, builder: (_) => ElrcRecordingsPage(visit: visit)));
    },
    icon: const Icon(TpIcons.recordings),
  ),
  Feature(
    id: 'ecourse',
    category: CampusServiceCategory.academics,
    subtitle: '进入 E 云课堂查看课程内容',
    keywords: const ['ecourse', 'classroom', 'yunketang'],
    pinnedByDefault: true,
    description: 'E云课堂',
    mode: FeatureMode.webviewWithCookie,
    url: 'https://ecourse.shanghaitech.edu.cn:8080/',
    cookieType: CookieType.ecourse,
    icon: const Icon(TpIcons.classroom),
  ),
  Feature(
    id: 'student_leave',
    category: CampusServiceCategory.life,
    subtitle: '提交和查看请假申请',
    keywords: const ['qingjia', 'leave'],
    pinnedByDefault: true,
    description: '学生请假',
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(
      context,
      builder: (_) => const StudentLeavePage(),
    ),
    icon: const Icon(TpIcons.building),
  ),
  Feature(
    id: 'campus_card',
    category: CampusServiceCategory.life,
    subtitle: '打开校园码与校园卡服务',
    keywords: const ['xiaoyuanka', 'ecard', '支付'],
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
  Feature(
    id: 'oa_gym',
    category: CampusServiceCategory.life,
    subtitle: '查询并预约体育场馆',
    keywords: const ['gym', 'changguan', '体育'],
    pinnedByDefault: true,
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
    category: CampusServiceCategory.activities,
    subtitle: '浏览校园活动与报名信息',
    keywords: const ['egate', 'huodong', '活动报名'],
    pinnedByDefault: true,
    description: '学生活动',
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(
      context,
      builder: (_) => const EgateAppPage(),
    ),
    icon: const Icon(TpIcons.scan),
  ),
  Feature(
    id: 'blackboard',
    category: CampusServiceCategory.academics,
    description: 'Blackboard 课程',
    subtitle: '课件、成绩与课程公告',
    keywords: const ['blackboard', 'bb', 'elearning', '课件', '作业', '公告'],
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(
      context,
      builder: (_) => const ElearningHubPage(),
    ),
    icon: const Icon(TpIcons.graduation),
  ),
  Feature(
    id: 'campus_jobs',
    category: CampusServiceCategory.activities,
    description: '校园岗位',
    subtitle: '勤工助学与助教岗位',
    keywords: const ['勤工', '助教', '兼职', 'ta', 'job', 'qingong', 'zhujiao', '工资'],
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(context, builder: (_) => const CampusJobsPage()),
    icon: const Icon(TpIcons.briefcase),
  ),
  Feature(
    id: 'study_plan',
    category: CampusServiceCategory.academics,
    description: '培养计划',
    subtitle: '查看学分进度与完整方案',
    keywords: const ['培养计划', '培养方案', '学分', 'study plan', 'peiyang'],
    mode: FeatureMode.native,
    nativeEntry: (context) =>
        pushAdaptivePage<void>(context, builder: (_) => const StudyPlanPage()),
    icon: const Icon(TpIcons.studyPlan),
  ),
  Feature(
    id: 'student_allowance',
    category: CampusServiceCategory.special,
    subtitle: '查看学生津贴发放记录',
    keywords: const ['jintie', 'allowance', '补助'],
    description: '学生津贴',
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(
      context,
      builder: (_) => const StudentAllowancePage(),
    ),
    icon: const Icon(TpIcons.allowance),
  ),
  Feature(
    id: 'holiday_travel',
    category: CampusServiceCategory.life,
    description: '节假日离返校',
    subtitle: '离返校登记与去向复用',
    keywords: const ['节假日', '离校', '返校', '假期', 'jiaqi', 'travel', 'holiday'],
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(
      context,
      builder: (_) => const HolidayTravelPage(),
    ),
    icon: const Icon(TpIcons.luggage),
  ),
  Feature(
    id: 'grades',
    category: CampusServiceCategory.academics,
    description: '成绩与 GPA',
    subtitle: '查询课程、英语成绩与试算绩点',
    keywords: const ['绩点', '成绩', 'gpa', 'chengji'],
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(context, builder: (_) => const GradesPage()),
    icon: const Icon(TpIcons.trophy),
  ),
  Feature(
    id: 'course_catalog',
    category: CampusServiceCategory.academics,
    description: '本科课程目录',
    subtitle: '按课程、院系和教师检索',
    keywords: const ['课程目录', '选课', 'catalog', 'course', '搜课', 'kecheng'],
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(context, builder: (_) => const CourseCatalogSearchPage()),
    icon: const Icon(TpIcons.course),
  ),
  Feature(
    id: 'pnp_minor',
    category: CampusServiceCategory.special,
    description: 'P/NP 与辅修',
    subtitle: '查看申请记录、报名和辅修方案',
    keywords: const ['pnp', 'p/np', '辅修', 'minor', 'fuxiu', '二专'],
    mode: FeatureMode.native,
    nativeEntry: (context) => pushAdaptivePage<void>(context, builder: (_) => const PnpMinorPage()),
    icon: const Icon(TpIcons.pnpMinor),
  ),
  Feature(
    id: 'academic_certificates',
    category: CampusServiceCategory.academics,
    description: '成绩单与证明',
    subtitle: '查看教务申请记录与 PDF',
    keywords: const ['成绩单', '排名', '证明', 'gpa', 'transcript', 'certificate', '平均分'],
    mode: FeatureMode.native,
    nativeEntry: (context) =>
        pushAdaptivePage<void>(context, builder: (_) => const AcademicCertificatesPage()),
    icon: const Icon(TpIcons.document),
  ),
];

final moreFeature = Feature(
  id: 'more',
  description: '更多',
  mode: FeatureMode.native,
  icon: const Icon(TpIcons.more),
);

/// Resolve saved IDs in display order and replace retired entries with defaults.
List<Feature> homeQuickFeatures(List<String>? saved) {
  final available = {
    for (final feature in featureEntries)
      if (feature.id != 'campus_card') feature.id: feature,
  };
  final ids = <String>{
    ...?saved?.where(available.containsKey),
    for (final feature in available.values)
      if (feature.pinnedByDefault) feature.id,
    ...available.keys,
  };
  return ids.take(maxPinnedQuickFeatures).map((id) => available[id]!).toList();
}
