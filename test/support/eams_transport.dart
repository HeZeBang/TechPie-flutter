import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

/// Send Dio requests through the same synthetic campus server as IDS and eGate.
Dio eamsTransport(http.Client server) => Dio()..httpClientAdapter = _Adapter(server);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.server);
  final http.Client server;
  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? data, Future<void>? cancel,) async {
    final request = http.Request(options.method, options.uri)
      ..headers.addAll(options.headers.map((key, value) => MapEntry(key, value.toString())));
    if (data != null) request.bodyBytes = await data.expand((chunk) => chunk).toList();
    final response = await server.send(request);
    return ResponseBody.fromBytes(await response.stream.toBytes(), response.statusCode,
        headers: response.headers.map((key, value) => MapEntry(key, [value])),);
  }

  @override
  void close({bool force = false}) {}
}

String scheduleEntry(String term) =>
    '<input name="ids" value="42"><input name="semester.id" value="$term">';
String semesterOptions(String year, String term) =>
    '<select><option value="$term">$year 秋</option></select>';
const emptyTimetable = '<table id="courseTable"></table>';
const emptyExamBatches = '<select name="examBatch.id"></select>';
const examBatches = '<select name="examBatch.id"><option value="1222">期中考试</option></select>';
const examTable = '''<table class="gridtable"><tr>
<th>课程代码</th><th>课程名称</th><th>考试类型</th><th>考试日期</th><th>考试时间</th><th>考试地点</th><th>座位号</th><th>考试情况</th></tr>
<tr><td>CS130.01</td><td>操作系统I</td><td>期中考试</td><td>2026-04-23</td><td>15:00~16:40</td><td>教学中心204</td><td><a href="/eams/seat?examRoom.id=7987">12</a></td><td>正常</td></tr></table>''';
