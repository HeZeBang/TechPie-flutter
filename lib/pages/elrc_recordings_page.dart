import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/elrc_course.dart';
import '../services/elrc_client.dart';
import '../services/elrc_session_service.dart';
import '../services/elrc_snapshot_catalog.dart';
import '../services/service_provider.dart';
import '../widgets/adaptive_page_navigation.dart';
import 'elrc_course_page.dart';

class ElrcRecordingsPage extends StatefulWidget {
  const ElrcRecordingsPage({
    super.key,
    this.session,
    this.client,
    this.catalogLoader = loadElrcCourseCatalog,
  });
  final ElrcSessionService? session;
  final ElrcClient? client;
  final Future<List<ElrcCourse>> Function() catalogLoader;

  @override
  State<ElrcRecordingsPage> createState() => _ElrcRecordingsPageState();
}

class _ElrcRecordingsPageState extends State<ElrcRecordingsPage> {
  late final Future<List<ElrcCourse>> _courses = widget.catalogLoader();
  ElrcSessionService? _session;
  late ElrcClient _client;
  bool _ownsSession = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session != null) return;
    final provider = context.dependOnInheritedWidgetOfExactType<ServiceProvider>();
    _session = widget.session ?? widget.client?.session ?? provider?.elrcSessionService;
    _ownsSession = _session == null;
    _session ??= ElrcSessionService();
    _client = widget.client ?? ElrcClient(_session!, catalog: ElrcSnapshotCatalog());
  }

  @override
  void dispose() {
    if (widget.client == null) _client.dispose();
    if (_ownsSession) _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('ELRC 录播'),
          actions: [
            ListenableBuilder(
              listenable: _session!,
              builder: (context, _) => IconButton(
                tooltip: '断开 ELRC',
                onPressed: !_session!.isConnected
                    ? null
                    : () {
                        _session!.disconnect();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已断开本机录播会话。学校网页可能仍保持登录。')),
                        );
                      },
                icon: const Icon(Icons.link_off),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: kIsWeb ||
                  (defaultTargetPlatform != TargetPlatform.iOS &&
                      defaultTargetPlatform != TargetPlatform.android)
              ? const ElrcStateMessage(
                  icon: Icons.phone_iphone,
                  title: '请在 iPhone 或 Android 手机中观看录播。',
                )
              : FutureBuilder<List<ElrcCourse>>(
                  future: _courses,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const ElrcStateMessage(
                        icon: Icons.error_outline,
                        title: '课程清单配置错误',
                        detail: '请联系 TechPie 项目组检查录播课程配置。',
                      );
                    }
                    final courses = snapshot.data ?? const <ElrcCourse>[];
                    if (courses.isEmpty) {
                      return const ElrcStateMessage(
                        icon: Icons.video_library_outlined,
                        title: '暂无已上架课程',
                        detail: '经过观看验证的课程会出现在这里。',
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: courses.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text('已收录课程可直接选择课次观看。录播清单按课程和学期整理，视频从学校服务器播放。'),
                          );
                        }
                        final course = courses[index - 1];
                        return Card.outlined(
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            leading: const Icon(Icons.video_library_outlined),
                            title: Text(course.name),
                            subtitle: course.description.isEmpty ? null : Text(course.description),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => unawaited(
                              pushAdaptivePage<void>(
                                context,
                                builder: (_) => ElrcCoursePage(course: course, client: _client),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      );
}
