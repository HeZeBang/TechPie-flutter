import 'dart:convert';

import '../../../models/assignment.dart';
import '../../../models/course.dart';
import '../../../models/course_table.dart';
import '../../../models/custom_course.dart';
import '../../../models/oa_gym.dart';
import '../../../services/assignment_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/oa_gym_service.dart';
import '../../../services/schedule_service.dart';
import '../../../services/third_party_auth_service.dart';
import '../domain/genai_agent_contract.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_workspace_controller.dart';

/// Adapts the same services used by TechPie's pages. Tool results deliberately
/// exclude account identifiers, credentials, contact details and signed URLs.
final class TechPieGenAiTools {
  TechPieGenAiTools({
    required this.schedule,
    required this.assignments,
    required this.gym,
    required this.workspace,
    required this.auth,
    required this.thirdPartyAuth,
    bool Function()? isDemo,
    this.previewEnvironment = false,
    DateTime Function()? now,
  })  : _isDemo = isDemo ?? (() => false),
        _now = now ?? DateTime.now;

  final ScheduleService schedule;
  final AssignmentService assignments;
  final OaGymService gym;
  final GenAiWorkspaceController workspace;
  final AuthService auth;
  final ThirdPartyAuthService thirdPartyAuth;
  final bool Function() _isDemo;
  final DateTime Function() _now;
  final bool previewEnvironment;
  String? _verifiedAssignmentScope;

  GenAiAgentToolRegistry createRegistry() => GenAiAgentToolRegistry([
        GenAiAgentTool(
          name: 'get_current_time',
          description: 'Read the current device time and Shanghai campus time '
              '(UTC+08:00). Use this before interpreting today or booking dates.',
          parameters: _schema(const {}),
          prepare: (_, context) async => GenAiAgentPreparedTool(
            execute: () async {
              context.checkActive();
              final utc = _now().toUtc();
              return {
                'utc': utc.toIso8601String(),
                'campus_time':
                    '${utc.add(const Duration(hours: 8)).toIso8601String().replaceFirst('Z', '')}+08:00',
                'campus_timezone': 'Asia/Shanghai',
                'device_time': _now().toIso8601String(),
                'source': 'device_clock',
              };
            },
          ),
        ),
        GenAiAgentTool(
          name: 'get_semesters',
          description: 'Read TechPie academic semesters. Use current-account verified '
              'data from TechPie; refresh when unverified or refresh=true. Cached data may be stale.',
          parameters: _schema({'refresh': _boolean}),
          prepare: (args, context) async => GenAiAgentPreparedTool(
            execute: () => _semesters(args, context),
          ),
        ),
        GenAiAgentTool(
          name: 'get_week_schedule',
          description: 'Read courses and custom courses for a teaching week. '
              'semester_id defaults to the selected semester. week defaults to '
              'the current campus week only when a calendar is available. Other '
              'semesters must first be selected in TechPie. Unverified data is refreshed '
              'before reading; this does not change the selected semester. '
              'Use weekday to filter and next_offset with offset to read additional results.',
          parameters: _schema({
            'semester_id': _string(max: 100),
            'week': _integer(1, 60),
            'weekday': _integer(1, 7),
            'offset': _integer(0, 1000),
            'limit': _integer(1, 40),
            'refresh': _boolean,
          }),
          prepare: (args, context) async => GenAiAgentPreparedTool(
            execute: () => _weekSchedule(args, context),
          ),
        ),
        GenAiAgentTool(
          name: 'get_assignments',
          description: 'Read TechPie visible assignments and exams, respecting '
              'hidden and completed overrides. Includes overdue items. Optional '
              'due_before is inclusive YYYY-MM-DD in campus time. Cache data may '
              'be stale. First use refreshes connected services to verify ownership; '
              'refresh=true repeats that check. Use next_offset with offset to page results.',
          parameters: _schema({
            'include_completed': _boolean,
            'due_before': _dateSchema,
            'limit': _integer(1, 100),
            'offset': _integer(0, 1000),
            'refresh': _boolean,
          }),
          prepare: (args, context) async => GenAiAgentPreparedTool(
            execute: () => _getAssignments(args, context),
          ),
        ),
        GenAiAgentTool(
          name: 'reserve_court',
          maxApprovalsPerRun: 1,
          description: 'Check real OA court availability or book one concrete '
              'court after user approval. Only one booking proposal per user message; '
              'bulk bookings are prohibited, even if requested. '
              'action=availability is read-only. '
              'Slots 1..11 are 11:00-12:00 through 21:00-22:00, Shanghai time. '
              'book requires court_number and players_count, and uses the '
              'contact profile already saved in TechPie. Never guess availability, '
              'price, or success. Do not retry a booking with an unknown outcome.',
          parameters: _schema(
            {
              'action': _enum(['availability', 'book']),
              'sport': _enum(OaSport.values.map((sport) => sport.id).toList()),
              'date': _dateSchema,
              'time_slot': _integer(1, 11),
              'end_slot': _integer(1, 11),
              'court_number': _integer(1, 6),
              'players_count': _integer(1, 100),
            },
            required: [
              'action',
              'sport',
              'date',
              'time_slot',
            ],
          ),
          prepare: _prepareCourt,
        ),
        GenAiAgentTool(
          name: 'generate_image',
          description: 'Generate one PNG through the existing GenAI image '
              'service after user approval; may consume school quota. Optional '
              'model must match a currently available image model. Defaults: '
              '1024x1024, low quality. Custom dimensions must contain '
              '655360..8294400 pixels. Returns image URLs, not invented images. '
              'Available image model IDs: ${workspace.imageModels.map((m) => m.aiType).join(', ')}. '
              'Omit model to use the current first available image model.',
          parameters: _schema(
            {
              'prompt': _string(max: 6000),
              'model': _string(max: 120),
              'width': _integer(1, 8294400),
              'height': _integer(1, 8294400),
              'quality': _enum(['low', 'medium', 'high']),
            },
            required: [
              'prompt',
            ],
          ),
          prepare: _prepareImage,
        ),
      ]);

  String get _scope => jsonEncode([
        auth.session?.userId,
        for (final account in thirdPartyAuth.accounts)
          [
            account.platform.name,
            account.account,
            account.sid,
            account.boundAt.toIso8601String(),
          ],
      ]);

  void Function() _guard(GenAiAgentToolContext context) {
    context.checkActive();
    if (!auth.isLoggedIn || !thirdPartyAuth.hasCpdailyBinding) {
      throw const GenAiAgentToolException(
        'authentication_required',
        '请先登录 TechPie 并绑定校园 IDS 账号。',
      );
    }
    final scope = _scope;
    return () {
      context.checkActive();
      if (_scope != scope || !auth.isLoggedIn || !thirdPartyAuth.hasCpdailyBinding) {
        context.cancellation.cancel(GenAiFailureKind.accountChanged);
        context.checkActive();
      }
    };
  }

  Future<Object?> _semesters(
    Map<String, Object?> args,
    GenAiAgentToolContext context,
  ) async {
    final guard = _guard(context);
    await _refreshSchedule(args, context);
    guard();
    final info = schedule.semesterInfo;
    if (info == null) {
      throw const GenAiAgentToolException(
        'data_unavailable',
        '尚未加载学期，请在课表页刷新后重试。',
      );
    }
    return {
      'source': 'techpie_cache',
      'ownership_verified': !_isDemo(),
      'selected_semester_id': schedule.selectedSemesterId,
      'default_semester_id': info.defaultSemester,
      'semesters': [
        for (final year in info.semesters.entries)
          for (final term in year.value.entries)
            {'id': term.value, 'label': info.findSemesterLabel(term.value)},
      ],
      'refresh_failed': schedule.error != null,
      'loading': schedule.loading,
      'demo': _isDemo(),
    };
  }

  void _checkCampusPreview() {
    if (previewEnvironment && !_isDemo()) {
      throw const GenAiAgentToolException(
        'preview_unavailable',
        '浏览器预览没有真实课表与作业连接。请在正式 TechPie 中使用校园工具；不会把演示缓存当作真实数据。',
      );
    }
  }

  Future<void> _refreshSchedule(
    Map<String, Object?> args,
    GenAiAgentToolContext context,
  ) async {
    _checkCampusPreview();
    if (_isDemo()) {
      if (args['refresh'] == true) {
        throw const GenAiAgentToolException(
          'demo_unavailable',
          '本地演示只提供已载入的课表数据，不能刷新校园服务。',
        );
      }
      return;
    }
    if (schedule.loading) {
      throw const GenAiAgentToolException('busy', '课表正在刷新，请等待后重试。');
    }
    if (args['refresh'] != true && schedule.hasVerifiedAccountData) return;
    final guard = _guard(context);
    await context.cancellation.race(schedule.fetchAll());
    guard();
    if (schedule.error != null) {
      throw const GenAiAgentToolException(
        'service_unavailable',
        '课表刷新失败，请在课表页检查连接状态后重试。',
      );
    }
    if (!schedule.hasVerifiedAccountData) {
      throw const GenAiAgentToolException(
        'data_unverified',
        '无法确认课表属于当前校园账号，请在课表页刷新后重试。',
      );
    }
  }

  Future<Object?> _weekSchedule(
    Map<String, Object?> args,
    GenAiAgentToolContext context,
  ) async {
    final guard = _guard(context);
    await _refreshSchedule(args, context);
    guard();
    final semesterId = args['semester_id'] as String? ?? schedule.selectedSemesterId;
    if (semesterId == null || semesterId.isEmpty) {
      throw const GenAiAgentToolException('data_unavailable', '请先在课表页选择学期。');
    }
    if (semesterId != schedule.selectedSemesterId && !_isDemo()) {
      throw const GenAiAgentToolException(
        'semester_not_loaded',
        '只能读取已验证的当前学期。请先在课表页切换学期。',
      );
    }
    final table = schedule.courseTableFor(semesterId);
    final calendar = schedule.termCalendarFor(semesterId);
    if (table == null) {
      throw const GenAiAgentToolException(
        'data_unavailable',
        '该学期还没有课表缓存，请在课表页加载后重试。',
      );
    }
    var week = args['week'] as int?;
    if (week == null) {
      if (calendar == null) {
        throw const GenAiAgentToolException(
          'calendar_unavailable',
          '缺少校历，无法判断当前教学周。请明确指定 week。',
        );
      }
      final campus = _now().toUtc().add(const Duration(hours: 8));
      final day = DateTime.utc(campus.year, campus.month, campus.day);
      final begin = DateTime.utc(
        calendar.termBegin.year,
        calendar.termBegin.month,
        calendar.termBegin.day,
      );
      final days = day.difference(begin).inDays;
      final current = days ~/ 7 + 1;
      final total = calendar.allTermWeeks > calendar.allTeachWeeks
          ? calendar.allTermWeeks
          : calendar.allTeachWeeks;
      if (days < 0 || current > total) {
        throw const GenAiAgentToolException(
          'outside_term',
          '当前日期不在该学期内，请明确指定教学周 week。',
        );
      }
      week = current;
    }
    if (calendar != null) {
      final total = calendar.allTermWeeks > calendar.allTeachWeeks
          ? calendar.allTermWeeks
          : calendar.allTeachWeeks;
      if (total > 0 && week > total) {
        throw const GenAiAgentToolException(
          'invalid_arguments',
          '指定教学周超出该学期校历。',
        );
      }
    }
    final periods = table.periods.isEmpty
        ? defaultPeriods
        : table.periods.map((period) => period.toPeriod()).toList();
    final allCourses = withCustomCourses(
      eamsToDisplayCourses(table.courses, week, timetablePeriods: periods),
      schedule.customCoursesFor(semesterId),
      week,
      calendar?.termBegin,
      periods: periods,
    )..sort((a, b) {
        final day = a.dayOfWeek.compareTo(b.dayOfWeek);
        return day == 0 ? a.startTime.compareTo(b.startTime) : day;
      });
    final courses = allCourses
        .where(
          (course) => args['weekday'] == null || course.dayOfWeek == args['weekday'],
        )
        .toList();
    final offset = args['offset'] as int? ?? 0;
    final rows = _boundedRows(
      [
        for (final course in courses)
          {
            'name': _bounded(course.name),
            'location': _bounded(course.location),
            'weekday': course.dayOfWeek,
            'start_time': course.startTime,
            'end_time': course.endTime,
            'custom': course.isCustom,
          },
      ],
      offset,
      args['limit'] as int? ?? 12,
    );
    return {
      'source': 'techpie_cache',
      'ownership_verified': !_isDemo(),
      'semester_id': semesterId,
      'semester_label': schedule.semesterInfo?.findSemesterLabel(semesterId),
      'week': week,
      'term_begin': calendar == null ? null : _date(calendar.termBegin),
      'calendar_available': calendar != null,
      'refresh_failed': schedule.error != null,
      'loading': schedule.loading,
      'demo': _isDemo(),
      'courses': rows,
      'truncated': offset + rows.length < courses.length,
      'next_offset': offset + rows.length < courses.length ? offset + rows.length : null,
    };
  }

  Future<Object?> _getAssignments(
    Map<String, Object?> args,
    GenAiAgentToolContext context,
  ) async {
    final guard = _guard(context);
    final before = args['due_before'] as String?;
    if (before != null) _parseDate(before);
    _checkCampusPreview();
    final dataScope = '$_scope|${schedule.selectedSemesterId}';
    if (!_isDemo() &&
        (args['refresh'] == true ||
            _verifiedAssignmentScope != dataScope ||
            !assignments.hasVerifiedAccountData)) {
      if (assignments.loading) {
        throw const GenAiAgentToolException('busy', '作业正在刷新，请等待后重试。');
      }
      await context.cancellation.race(assignments.fetchAssignments());
      guard();
      if (!assignments.hasVerifiedAccountData) {
        throw const GenAiAgentToolException(
          'data_unverified',
          '无法确认作业数据属于当前绑定账号，请在作业页完成同步后重试。',
        );
      }
      _verifiedAssignmentScope = dataScope;
    } else if (_isDemo() && args['refresh'] == true) {
      throw const GenAiAgentToolException(
        'demo_unavailable',
        '本地演示只提供缓存作业，不能刷新校园服务。',
      );
    }
    guard();
    final values = (_isDemo()
            ? assignments.visibleAssignments
            : assignments.verifiedVisibleAssignments)
        .where((assignment) {
      if (args['include_completed'] != true && assignments.isCompleted(assignment)) {
        return false;
      }
      if (before != null &&
          _date(assignment.due.toUtc().add(const Duration(hours: 8))).compareTo(before) > 0) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    final offset = args['offset'] as int? ?? 0;
    final rows = _boundedRows(
      [
        for (final assignment in values)
          {
            'id': assignment.id,
            'title': _bounded(assignment.title),
            'course': _bounded(assignment.course),
            'kind': assignment.kind.id,
            'due': assignment.due.toUtc().toIso8601String(),
            'completed': assignments.isCompleted(assignment),
            if (assignment case ExamAssignment(:final location)) 'location': _bounded(location),
          },
      ],
      offset,
      args['limit'] as int? ?? 30,
    );
    return {
      'source': 'techpie_cache',
      'ownership_verified': !_isDemo(),
      'loading': assignments.loading,
      'partial': assignments.error != null || assignments.platformErrors.isNotEmpty,
      'unavailable_platforms': assignments.platformErrors.keys.toList(),
      'demo': _isDemo(),
      'assignments': rows,
      'truncated': offset + rows.length < values.length,
      'next_offset': offset + rows.length < values.length ? offset + rows.length : null,
    };
  }

  Future<GenAiAgentPreparedTool> _prepareCourt(
    Map<String, Object?> args,
    GenAiAgentToolContext context,
  ) async {
    final guard = _guard(context);
    if (_isDemo()) {
      throw const GenAiAgentToolException(
        'demo_unavailable',
        '本地演示没有真实 OA 场地数据，不能查询或提交预约。请连接真实校园账号。',
      );
    }
    final sport = OaSport.values.firstWhere((value) => value.id == args['sport']);
    final date = args['date']! as String;
    final day = _parseDate(date);
    final slot = args['time_slot']! as int;
    final end = args['end_slot'] as int? ?? slot;
    if (end < slot) {
      throw const GenAiAgentToolException(
        'invalid_arguments',
        'end_slot 不能早于 time_slot。',
      );
    }
    final book = args['action'] == 'book';
    final number = args['court_number'] as int?;
    final players = args['players_count'] as int?;
    final court = oaCourtsForSport(sport).where((value) => value.number == number).firstOrNull;
    if (book && (court == null || players == null || end != slot)) {
      throw const GenAiAgentToolException(
        'invalid_arguments',
        '预约需要有效 court_number、players_count，且只能预约一个时间段。',
      );
    }
    void validateStart() {
      final campusNow = _now().toUtc().add(const Duration(hours: 8));
      final start = DateTime.utc(day.year, day.month, day.day, slot + 10);
      if (!start.isAfter(campusNow)) {
        throw const GenAiAgentToolException(
          'invalid_arguments',
          '只能查询或预约尚未开始的时间段。',
        );
      }
    }

    validateStart();
    Future<List<OaAvailability>> availability() async {
      guard();
      validateStart();
      try {
        final result = await context.cancellation.race(
          gym.checkAvailability(
            sports: {sport},
            date: date,
            startSlot: slot,
            endSlot: end,
            shouldContinue: () {
              guard();
              return true;
            },
          ),
        );
        guard();
        return result;
      } on OaGymException {
        throw const GenAiAgentToolException(
          'court_unavailable',
          '未能获取场地状态，请在场馆预约页检查校园绑定和服务状态。',
        );
      }
    }

    final checked = await availability();
    if (!book) {
      return GenAiAgentPreparedTool(
        execute: () async {
          guard();
          return {
            'status': 'availability',
            'sport': sport.id,
            'availability': [
              for (final row in checked)
                {
                  'date': row.date,
                  'time_slot': row.timeSlot,
                  'time_range': oaTimeSlots[row.timeSlot - 1].range,
                  'available_courts': [
                    for (final value in oaCourtsForSport(sport))
                      if (row.availableCourts.contains(value.number))
                        {'number': value.number, 'label': value.label},
                  ],
                },
            ],
            'price': '平台未提供价格；请以学校预约结果为准',
          };
        },
      );
    }
    void requireAvailable(List<OaAvailability> rows) {
      if (!rows.any(
        (row) =>
            row.sport == sport &&
            row.date == date &&
            row.timeSlot == slot &&
            row.availableCourts.contains(number),
      )) {
        throw const GenAiAgentToolException(
          'court_not_available',
          '所选场地当前不可预约，请重新查询。',
        );
      }
    }

    void requireProfile() {
      final profile = gym.bookingProfile();
      if (profile.name.trim().isEmpty ||
          profile.phone.trim().isEmpty ||
          gym.bookingStudentId.isEmpty) {
        throw const GenAiAgentToolException(
          'profile_required',
          '请先在场馆预约的个人信息中补全姓名、手机号与校园身份。',
        );
      }
    }

    requireAvailable(checked);
    requireProfile();
    final approvedProfile = gym.bookingProfile().toJson();
    final approvedStudent = gym.bookingStudentId;
    final preparedAt = _now();
    var executionClaimed = false;
    void requireFreshApproval() {
      final age = _now().difference(preparedAt);
      if (age.isNegative || age >= const Duration(minutes: 2)) {
        throw const GenAiAgentToolException(
          'approval_expired',
          '预约确认已过期，请重新发起请求并核对场地和时间。',
          effectNotDispatched: true,
        );
      }
    }

    final details = <String, Object?>{
      'date': date,
      'sport': sport.label,
      'court': court!.label,
      'time': oaTimeSlots[slot - 1].range,
      'players': players,
      'price': '平台未提供价格；请以学校预约结果为准',
      'contact': '使用场馆预约中已保存的联系信息',
      'policy': '仅预约此场地的这一个时段；每条消息最多一次预约确认，2 分钟内有效。',
    };
    return GenAiAgentPreparedTool(
      requiresApproval: true,
      effectKey: jsonEncode(
        [court.bookingSport.id, date, slot, court.bookingNumber],
      ),
      summary: '预约 $date ${oaTimeSlots[slot - 1].range} ${court.label}，$players 人',
      details: details,
      execute: () async {
        guard();
        requireFreshApproval();
        if (executionClaimed) {
          throw const GenAiAgentToolException(
            'booking_already_attempted',
            '此预约已处理，不能重复提交。请在场馆预约页核实结果。',
          );
        }
        // Claim synchronously before any await so concurrent callbacks cannot
        // dispatch the same approval twice, even when its outcome is unknown.
        executionClaimed = true;
        try {
          requireAvailable(await availability());
          requireFreshApproval();
          guard();
          requireProfile();
          if (jsonEncode(gym.bookingProfile().toJson()) != jsonEncode(approvedProfile) ||
              gym.bookingStudentId != approvedStudent) {
            throw const GenAiAgentToolException(
              'profile_changed',
              '预约联系信息已变更，请重新确认预约。',
            );
          }
          validateStart();
        } on GenAiAgentToolException catch (error) {
          // No booking POST is reachable until all preparation checks pass.
          throw GenAiAgentToolException(error.code, error.message, effectNotDispatched: true);
        }
        OaBookingResult result;
        try {
          result = await gym.bookCourt(
            sport: sport,
            date: date,
            timeSlot: slot,
            courtNumber: number!,
            playersCount: players!,
            shouldContinue: () {
              guard();
              requireFreshApproval();
              return true;
            },
          );
        } on OaGymException {
          throw const GenAiAgentToolException(
            'outcome_unknown',
            '预约提交未能确认结果。请到场馆预约页查询记录，不要自动重复提交。',
          );
        }
        guard();
        return {
          'status': result.success ? 'booked' : 'rejected',
          'success': result.success,
          'date': date,
          'sport': sport.id,
          'court_number': number,
          'time_slot': slot,
          'players_count': players,
          'message': result.success ? '学校服务确认预约成功。' : '学校服务未确认预约成功，请查看场馆预约页。',
        };
      },
    );
  }

  Future<GenAiAgentPreparedTool> _prepareImage(
    Map<String, Object?> args,
    GenAiAgentToolContext context,
  ) async {
    final guard = _guard(context);
    final modelName = args['model'] as String?;
    final models = workspace.imageModels;
    final GenAiModel? model = modelName == null
        ? models.firstOrNull
        : models
            .where(
              (model) => model.aiType == modelName || model.name == modelName,
            )
            .firstOrNull;
    if (model == null) {
      throw GenAiAgentToolException(
        'model_unavailable',
        models.isEmpty
            ? '当前没有可用的生图模型，请先连接 GenAI 并加载模型。'
            : '指定模型不可用。可用生图模型：${models.map((m) => m.aiType).join(', ')}',
      );
    }
    final prompt = (args['prompt']! as String).trim();
    final width = args['width'] as int? ?? 1024;
    final height = args['height'] as int? ?? 1024;
    final quality = args['quality'] as String? ?? 'low';
    final GenAiImageRequest request;
    try {
      request = GenAiImageRequest(
        prompt: prompt,
        model: model,
        groupId: GenAiWorkspaceController.createGroupId(),
        size: '${width}x$height',
        quality: quality,
      );
    } on ArgumentError {
      throw const GenAiAgentToolException(
        'invalid_arguments',
        '请提供有效提示词与分辨率，总像素需在 655360 到 8294400 之间。',
      );
    }
    return GenAiAgentPreparedTool(
      requiresApproval: true,
      effectKey: jsonEncode(
        [model.aiType, model.rootAiType, prompt, request.size, quality],
      ),
      executionTimeout: const Duration(minutes: 6),
      summary: '生成 1 张图片 · ${model.name} · ${request.size} · $quality',
      details: {
        'prompt': prompt,
        'model': model.name,
        'size': request.size,
        'quality': quality,
        'count': 1,
        'quota': _isDemo() ? '本地演示，不消耗校园额度' : '将使用校园生图额度，实际费用以平台结算为准',
      },
      execute: () async {
        guard();
        if (!workspace.imageModels.any(
          (value) => value.aiType == model.aiType && value.rootAiType == model.rootAiType,
        )) {
          throw const GenAiAgentToolException(
            'model_unavailable',
            '生图模型已变更，请重新发起请求。',
          );
        }
        final List<Uri> images;
        try {
          images = await workspace.repository.generateImage(request, context.cancellation);
        } on GenAiFailure catch (failure) {
          if (failure.kind == GenAiFailureKind.cancelled ||
              failure.kind == GenAiFailureKind.accountChanged ||
              failure.kind == GenAiFailureKind.authenticationRequired) {
            rethrow;
          }
          throw const GenAiAgentToolException(
            'outcome_unknown',
            '未能确认生图结果；平台可能已扣除额度。请先查看图片历史，不要自动重试。',
          );
        }
        guard();
        if (images.isEmpty) {
          throw const GenAiAgentToolException(
            'outcome_unknown',
            '平台未返回图片，请先查看图片历史与用量记录。',
          );
        }
        return {
          'status': 'generated',
          'model': model.name,
          'size': request.size,
          'quality': quality,
          'images': images.map((uri) => uri.toString()).toList(),
          'demo': _isDemo(),
        };
      },
    );
  }
}

Map<String, Object?> _schema(
  Map<String, Object?> properties, {
  List<String> required = const [],
}) =>
    {
      'type': 'object',
      'properties': properties,
      'required': required,
      'additionalProperties': false,
    };
const _boolean = {'type': 'boolean'};
const _dateSchema = {'type': 'string', 'pattern': r'^\d{4}-\d{2}-\d{2}$'};
Map<String, Object?> _string({required int max}) =>
    {'type': 'string', 'minLength': 1, 'maxLength': max};
Map<String, Object?> _integer(int min, int max) =>
    {'type': 'integer', 'minimum': min, 'maximum': max};
Map<String, Object?> _enum(List<String> values) => {'type': 'string', 'enum': values};
DateTime _parseDate(String value) {
  final day = DateTime.tryParse(value);
  if (day == null || _date(day) != value) {
    throw const GenAiAgentToolException(
      'invalid_arguments',
      '日期必须是有效的 YYYY-MM-DD。',
    );
  }
  return day;
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _bounded(String value) => value.length <= 240 ? value : value.substring(0, 240);

List<Map<String, Object?>> _boundedRows(
  List<Map<String, Object?>> rows,
  int offset,
  int limit,
) {
  final result = <Map<String, Object?>>[];
  var bytes = 0;
  for (final row in rows.skip(offset).take(limit)) {
    final length = jsonEncode(row).length;
    if (bytes + length > 4000) break;
    result.add(row);
    bytes += length;
  }
  return result;
}
