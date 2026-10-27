import '../../../models/oa_gym.dart';
import '../domain/genai_agent_contract.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_chat_service.dart';
import 'genai_conversation_archive.dart';

/// A user-readable snapshot, never a replayable protocol or credential export.
String exportGenAiTranscript(GenAiConversationArchive archive) {
  final out = StringBuffer('# ${_line(archive.title)}\n\n');
  for (final turn in archive.restoreTurns()) {
    if (turn.isHistoryGap) {
      out.writeln('（服务器返回的一条历史记录无法读取，部分上下文可能缺失。）\n\n---\n');
      continue;
    }
    out.writeln('## 你\n\n${turn.prompt}\n');
    if (turn.attachedFileNames.isNotEmpty) {
      out.writeln('附件：${turn.attachedFileNames.map(_line).join('、')}\n');
    }
    for (final url in <String>{
      ...turn.attachedImageUrls,
      if (turn.attachedImageUrl != null) turn.attachedImageUrl!,
    }) {
      _writeImage(out, url, reference: true);
    }
    out.writeln('## TechPie${turn.isAgent ? ' Agent' : ''}\n');
    for (final event in turn.agentEvents.values) {
      final call = event.call;
      if (call == null) continue;
      final result = event.result;
      final error = result?['error'];
      final finished = event.kind == GenAiAgentEventKind.toolFinished;
      final unknown = error is Map && error['code'] == 'outcome_unknown' ||
          !finished && event.kind == GenAiAgentEventKind.toolStarted;
      final payload = result?['result'];
      final rejected = payload is Map &&
          call.name == 'reserve_court' &&
          (payload['status'] == 'rejected' || payload['success'] == false);
      final denied = error is Map && error['code'] == 'approval_denied';
      final status = unknown
          ? '结果待核实'
          : denied
              ? '已拒绝'
              : rejected
                  ? '未预约成功'
                  : finished && result?['ok'] == true
                      ? '已完成'
                      : finished
                          ? '未完成'
                          : '已停止，未执行';
      out.writeln('### ${_label(call.name)} · $status\n');
      final summary = event.prepared?.summary;
      if (summary != null) out.writeln('$summary\n');
      if (error is Map && error['message'] is String) {
        out.writeln('${error['message']}\n');
      }
      if (result?['reused'] == true) out.writeln('复用已保存的结果，没有重复执行。\n');
      if (payload is Map && result?['ok'] == true) {
        _writeToolResult(out, call.name, payload);
        out.writeln();
      }
    }
    if (turn.answer.isNotEmpty) out.writeln('${turn.answer}\n');
    if (turn.phase == GenAiChatPhase.cancelled) out.writeln('（此轮已停止）\n');
    if (turn.phase == GenAiChatPhase.failed) out.writeln('（此轮未完成）\n');
    if (turn.phase == GenAiChatPhase.interrupted) {
      out.writeln('（历史记录不完整，请核实工具结果）\n');
    }
    if (turn.citations.isNotEmpty) {
      out.writeln('来源：');
      for (final citation in turn.citations) {
        final uri = Uri.tryParse(citation.link);
        if (uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.userInfo.isEmpty) {
          out.writeln('- ${_line(citation.title)}：<$uri>');
        }
      }
      out.writeln();
    }
    out.writeln('---\n');
  }
  return out.toString().trimRight();
}

String _line(String text) => text.replaceAll(RegExp(r'[\r\n]+'), ' ');
String _label(String name) => switch (name) {
      'get_current_time' => '当前时间',
      'get_semesters' => '学期',
      'get_week_schedule' => '课表',
      'get_assignments' => '作业',
      'reserve_court' => '场地预约',
      'generate_image' => '图片创作',
      _ => '工具',
    };

String _text(Object? value) => value == null ? '' : _line('$value').trim();

void _field(StringBuffer out, String label, Object? value) {
  final text = _text(value);
  if (text.isNotEmpty) out.writeln('- $label：$text');
}

Iterable<Map<dynamic, dynamic>> _rows(Object? value) =>
    value is List ? value.whereType<Map<dynamic, dynamic>>() : const [];

String _joined(Iterable<Object?> values) =>
    values.map(_text).where((value) => value.isNotEmpty).join(' · ');

String _campusTime(Object? value) {
  final raw = _text(value);
  if (raw.isEmpty) return '';
  // Tool timestamps have explicit UTC/offset information. Do not guess the
  // timezone of unzoned imported text; preserve it verbatim instead.
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw)) return raw;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final date = parsed.toUtc().add(const Duration(hours: 8));
  String two(int number) => '$number'.padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}（上海时间）';
}

void _writeToolResult(
  StringBuffer out,
  String name,
  Map<dynamic, dynamic> value,
) {
  if (value['demo'] == true) out.writeln('本地演示数据。\n');
  if (value['refresh_failed'] == true) out.writeln('刷新失败，以下为已保存的数据。\n');
  if (value['partial'] == true) out.writeln('部分数据未能加载，以下结果可能不完整。\n');
  if (value['loading'] == true) out.writeln('数据仍在刷新。\n');
  if (value['ownership_verified'] == false && value['demo'] != true) {
    out.writeln('数据归属尚未验证。\n');
  }
  switch (name) {
    case 'get_current_time':
      _field(out, '校区时间', _campusTime(value['campus_time']));
      _field(out, '设备时间', value['device_time']);
      _field(out, 'UTC 时间', value['utc']);
    case 'get_semesters':
      for (final term in _rows(value['semesters'])) {
        final label = _text(term['label']);
        if (label.isEmpty) continue;
        final tags = <String>[
          if (term['id'] == value['selected_semester_id']) '当前选择',
          if (term['id'] == value['default_semester_id']) '默认学期',
        ];
        out.writeln('- $label${tags.isEmpty ? '' : '（${tags.join('、')}）'}');
      }
    case 'get_week_schedule':
      _field(out, '学期', value['semester_label']);
      if (value['week'] != null) _field(out, '教学周', '第 ${value['week']} 周');
      final courses = _rows(value['courses']).toList();
      if (courses.isEmpty) out.writeln('本次查询没有课程。');
      for (final course in courses) {
        final day = course['weekday'];
        final weekday = day is int && day >= 1 && day <= 7
            ? ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day - 1]
            : '';
        final start = _text(course['start_time']);
        final end = _text(course['end_time']);
        out.writeln('- ${_joined([
              course['name'],
              weekday,
              start.isNotEmpty && end.isNotEmpty ? '$start–$end' : start,
              course['location'],
              if (course['custom'] == true) '自定义课程',
            ])}');
      }
    case 'get_assignments':
      final assignments = _rows(value['assignments']).toList();
      if (assignments.isEmpty) out.writeln('本次查询没有作业或考试。');
      for (final assignment in assignments) {
        out.writeln('- ${_joined([
              assignment['title'],
              assignment['course'],
              assignment['kind'] == 'exam' ? '考试' : '作业',
              if (_text(assignment['due']).isNotEmpty) '截止 ${_campusTime(assignment['due'])}',
              assignment['completed'] == true ? '已完成' : '未完成',
              assignment['location'],
            ])}');
      }
    case 'reserve_court':
      _writeCourt(out, value);
    case 'generate_image':
      _field(out, '模型', value['model']);
      _field(out, '分辨率', value['size']);
      _field(
        out,
        '质量',
        const {
              'low': '普通',
              'medium': '标准',
              'high': '精细',
            }[value['quality']] ??
            value['quality'],
      );
      if (value['status'] == 'generated' && value['images'] is List) {
        for (final image in (value['images'] as List).whereType<String>()) {
          _writeImage(out, image, demo: value['demo'] == true);
        }
      }
    default:
      // Future tools need an explicit readable adapter. Never dump arbitrary
      // result maps, which may contain internal identifiers or debug fields.
      out.writeln('工具结果已保存，可在 TechPie 中查看详细信息。');
  }
  if (value['truncated'] == true) out.writeln('还有更多记录未包含在本次结果中。');
}

void _writeCourt(StringBuffer out, Map<dynamic, dynamic> value) {
  final sport = OaSport.values.where((sport) => sport.id == value['sport']).firstOrNull;
  _field(out, '运动', sport?.label);
  if (value['status'] == 'availability') {
    for (final row in _rows(value['availability'])) {
      final labels = _rows(row['available_courts'])
          .map((court) => _text(court['label']))
          .where((label) => label.isNotEmpty)
          .toList();
      out.writeln('- ${_joined([
            row['date'],
            row['time_range'],
            labels.isEmpty ? '暂无可预约场地' : labels.join('、'),
          ])}');
    }
  } else {
    _field(out, '日期', value['date']);
    if (value['court_number'] != null) {
      _field(out, '场地', '${value['court_number']} 号场地');
    }
    final slot = oaTimeSlots.where((slot) => slot.id == value['time_slot']).firstOrNull;
    _field(out, '时段', slot?.range);
    if (value['players_count'] != null) {
      _field(out, '人数', '${value['players_count']} 人');
    }
    _field(out, '结果', value['message']);
  }
  _field(out, '费用', value['price']);
}

void _writeImage(
  StringBuffer out,
  String value, {
  bool reference = false,
  bool demo = false,
}) {
  final parsed = Uri.tryParse(value);
  final local = demo ||
      parsed != null &&
          (parsed.pathSegments.any((part) => part.startsWith('techpie-preview')) ||
              parsed.path.contains('/temp/demo-upload-'));
  if (local) {
    out.writeln(
      '${reference ? '参考图片' : '生成图片'}：本地测试图片（仅随 TechPie 演示提供，不是可访问的校园图片链接）。\n',
    );
    return;
  }
  final uri = _imageUri(value);
  if (uri != null) {
    out.writeln('![${reference ? '参考图片' : '生成图片'}](<$uri>)\n');
  }
}

Uri? _imageUri(String value) {
  try {
    var raw = Uri.parse(value);
    // The development proxy has already resolved generated image URLs locally.
    // Export their canonical static CDN path, never a loopback-only link.
    if (raw.scheme == 'http' &&
        const ['127.0.0.1', 'localhost', '::1'].contains(raw.host) &&
        raw.userInfo.isEmpty &&
        !raw.hasQuery &&
        !raw.hasFragment &&
        raw.path.startsWith('/sys/common/static/')) {
      raw = Uri(
        scheme: 'https',
        host: 'genaipic.shanghaitech.edu.cn',
        path: raw.path,
      );
    }
    return genAiImageUri(raw.toString());
  } catch (_) {
    return null;
  }
}
