// Supply credentials as one JSON line on stdin; nothing sensitive is printed.
// Performs fixture calls only: no filesystem or command execution tools.
import 'dart:convert';
import 'dart:io';
import 'package:techpie/services/genai/genai_gateway.dart';

Future<void> main(List<String> args) async {
  final credentials =
      jsonDecode(await stdin.transform(utf8.decoder).transform(const LineSplitter()).first)
          as Map<String, dynamic>;
  final gateway = GenaiGateway(onDiagnostic: (d) => stdout.writeln(jsonEncode(d)));
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final existing = args.contains('--installed');
  try {
    if (!existing) {
      await gateway.start(
        host: '127.0.0.1',
        port: 0,
        genaiToken: credentials['upstream'] as String,
        apiToken: credentials['local'] as String,
      );
    }
    final base = 'http://127.0.0.1:${existing ? 5000 : gateway.port}';
    Future<dynamic> send(String path, [Map<String, dynamic>? body]) async {
      final req = await client.openUrl(body == null ? 'GET' : 'POST', Uri.parse('$base$path'));
      req.headers.set('Authorization', 'Bearer ${credentials['local']}');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join().timeout(const Duration(seconds: 180));
      if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
      if (body?['stream'] == true) {
        final events = const LineSplitter()
            .convert(text)
            .where((l) => l.startsWith('data:') && !l.contains('[DONE]'))
            .map((l) => jsonDecode(l.substring(5)))
            .toList();
        if (events.any((e) => e['error'] != null || e['type'] == 'response.failed')) {
          throw StateError('SSE error');
        }
        if (path.endsWith('responses')) return events.last['response'];
        final calls = <dynamic>[];
        final content = StringBuffer();
        String? finish;
        for (final e in events) {
          final c = e['choices'][0];
          final d = c['delta'];
          if (d['tool_calls'] is List) calls.addAll(d['tool_calls'] as List);
          if (d['content'] is String) content.write(d['content']);
          finish = c['finish_reason'] as String? ?? finish;
        }
        return {
          'choices': [
            {
              'finish_reason': finish,
              'message': {
                'role': 'assistant',
                'content': content.toString(),
                if (calls.isNotEmpty) 'tool_calls': calls,
              },
            }
          ],
        };
      }
      return jsonDecode(text);
    }

    final models = await send('/v1/models');
    final model = (models['data'] as List)
        .map((m) => m['id'] as String)
        .firstWhere((m) => m.toLowerCase().contains('chatglm'));
    for (final responses in [false, true]) {
      final path = responses ? '/v1/responses' : '/v1/chat/completions';
      final tools = [
        responses
            ? {
                'type': 'function',
                'name': 'fixture_read',
                'description': '读取测试夹具编号',
                'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
              }
            : {
                'type': 'function',
                'function': {
                  'name': 'fixture_read',
                  'description': '读取测试夹具编号',
                  'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
                },
              },
      ];
      final prompt = '调用 fixture_read 获取测试编号。收到结果后用一句话原样报告编号。工具只读取测试夹具。';
      final initial = {'role': 'user', 'content': prompt};
      final first = await send(path, {
        'model': model,
        'stream': true,
        'tools': tools,
        'tool_choice': 'required',
        if (responses) 'input': prompt else 'messages': [initial],
        if (responses) 'max_output_tokens': 1024 else 'max_completion_tokens': 1024,
      });
      dynamic call;
      if (responses) {
        if (first['status'] != 'completed') throw StateError('incomplete response');
        call = (first['output'] as List).singleWhere((x) => x['type'] == 'function_call');
        if (call['name'] != 'fixture_read') throw StateError('unexpected tool');
      } else {
        if (first['choices'][0]['finish_reason'] != 'tool_calls') {
          throw StateError('missing tool finish');
        }
        call = first['choices'][0]['message']['tool_calls'][0];
        if (call['function']['name'] != 'fixture_read') throw StateError('unexpected tool');
      }
      final second = await send(path, {
        'model': model,
        'stream': false,
        'tools': tools,
        'tool_choice': 'auto',
        if (responses)
          'input': [
            initial,
            call,
            {
              'type': 'function_call_output',
              'call_id': call['call_id'],
              'output': '测试编号：FIXTURE-731',
            }
          ]
        else
          'messages': [
            initial,
            first['choices'][0]['message'],
            {
              'role': 'tool',
              'tool_call_id': call['id'],
              'name': 'fixture_read',
              'content': '测试编号：FIXTURE-731',
            }
          ],
        if (responses) 'max_output_tokens': 1024 else 'max_completion_tokens': 1024,
      });
      final answer = responses ? second['output_text'] : second['choices'][0]['message']['content'];
      if (answer is! String || !answer.contains('FIXTURE-731')) {
        throw StateError('fixture summary missing');
      }
      stdout.writeln(
        jsonEncode(
          {'api': path, 'model': model, 'fixture_round_trip': 'passed', 'installed': existing},
        ),
      );
    }
  } finally {
    client.close(force: true);
    await gateway.stop();
  }
}
