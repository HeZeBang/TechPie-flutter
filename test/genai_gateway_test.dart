import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/services/genai/genai_gateway.dart';
import 'package:techpie/services/genai/genai_login.dart';
import 'package:techpie/services/genai/genai_tools.dart';

void main() {
  late HttpServer upstream;
  late GenaiGateway gateway;
  late HttpClient client;
  final received = <String, dynamic>{};
  String reply = '你好';
  bool businessError = false;
  String? finishReason = 'stop';
  bool done = false;
  List<List<Map<String, dynamic>>>? attemptPackets;
  final bodies = <dynamic>[];
  final diagnostics = <Map<String, Object?>>[];
  Completer<void>? upstreamGate;

  setUp(() async {
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    received.clear();
    reply = '你好';
    businessError = false;
    finishReason = 'stop';
    done = false;
    diagnostics.clear();
    attemptPackets = null;
    bodies.clear();
    upstreamGate = null;
    upstream.listen((request) async {
      received['token'] = request.headers.value('x-access-token');
      if (request.uri.path.endsWith('/list')) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'success': true,
            'result': {
              'records': [
                {'aiType': 'test-model', 'rootAiType': 'azure'},
                {'aiType': 'test-model'},
              ],
            },
          }),
        );
      } else {
        await upstreamGate?.future;
        received['body'] = jsonDecode(await utf8.decoder.bind(request).join());
        bodies.add(received['body']);
        request.response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        if (attemptPackets != null) {
          final index = bodies.length - 1;
          final packets =
              attemptPackets![index < attemptPackets!.length ? index : attemptPackets!.length - 1];
          for (final packet in packets) {
            request.response.write('data: ${jsonEncode(packet)}\n\n');
          }
        } else if (businessError) {
          request.response
              .write('data: ${jsonEncode({'success': false, 'message': 'Token失效'})}\n\n');
        } else {
          // The final text shares an event with finish_reason.
          request.response.write('data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': reply, 'reasoning': '思考'},
                    'finish_reason': finishReason,
                  }
                ],
              })}\n\n');
        }
      }
      if (done) request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    gateway = GenaiGateway(
      onDiagnostic: diagnostics.add,
      upstream: Uri.parse('http://127.0.0.1:${upstream.port}'),
      heartbeatInterval: const Duration(milliseconds: 30),
    );
    await gateway.start(
      host: '127.0.0.1',
      port: 0,
      genaiToken: 'upstream-token',
      apiToken: 'local-token',
    );
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await gateway.stop();
    await upstream.close(force: true);
  });

  Future<({int status, String body})> request(
    String path, {
    Object? body,
    String? token = 'local-token',
  }) async {
    final req = await client.openUrl(
      body == null ? 'GET' : 'POST',
      Uri.parse('http://127.0.0.1:${gateway.port}$path'),
    );
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    return (status: res.statusCode, body: await utf8.decoder.bind(res).join());
  }

  test('local token is separate from the upstream token', () async {
    expect((await request('/v1/models', token: null)).status, 401);
    expect((await request('/v1/models', token: 'upstream-token')).status, 401);
    final res = await request('/v1/models');
    expect(res.status, 200);
    expect((jsonDecode(res.body)['data'] as List).length, 1);
    expect(received['token'], 'upstream-token');
  });

  test('nonstream reply preserves final text and model routing', () async {
    await request('/v1/models');
    final res = await request(
      '/v1/chat/completions',
      body: {
        'model': 'test-model',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      },
    );
    expect(res.status, 200);
    expect(jsonDecode(res.body)['choices'][0]['message']['content'], '你好');
    expect(received['body']['rootAiType'], 'azure');
    expect(received['token'], 'upstream-token');
  });

  test('SSE contains text, reasoning and completion', () async {
    final res = await request(
      '/v1/chat/completions',
      body: {
        'model': 'test-model',
        'stream': true,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      },
    );
    expect(res.status, 200);
    expect(res.body, contains('你好'));
    expect(res.body, contains('reasoning_content'));
    expect(res.body, contains('[DONE]'));
  });

  test('tool JSON becomes tool_calls', () async {
    reply = '{"tool_calls":[{"name":"weather","arguments":{"city":"上海"}}]}';
    final res = await request(
      '/v1/chat/completions',
      body: {
        'model': 'test-model',
        'messages': [
          {'role': 'user', 'content': '天气'},
        ],
        'tools': [
          {
            'type': 'function',
            'function': {'name': 'weather'},
          }
        ],
      },
    );
    final choice = jsonDecode(res.body)['choices'][0];
    expect(choice['finish_reason'], 'tool_calls');
    expect(choice['message']['tool_calls'][0]['function']['arguments'], '{"city":"上海"}');
  });

  test('Responses endpoint accepts instructions and input', () async {
    final res = await request(
      '/v1/responses',
      body: {'model': 'test-model', 'input': 'hi', 'instructions': 'test'},
    );
    expect(jsonDecode(res.body)['output_text'], '你好');
    expect(received['body']['messages'][0]['role'], 'system');
  });

  test('business errors are returned instead of empty replies', () async {
    businessError = true;
    final res = await request(
      '/v1/chat/completions',
      body: {
        'model': 'test-model',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      },
    );
    expect(res.status, isNot(200));
    expect(res.body, contains('Token失效'));
  });

  test('server releases the port when stopped', () async {
    final port = gateway.port!;
    await gateway.stop();
    final replacement = await HttpServer.bind('127.0.0.1', port);
    await replacement.close(force: true);
    expect(gateway.running, false);
  });

  test('CAS fields accept either attribute order and quote style', () {
    expect(GenaiLogin.field('<input value="salt" id="pwdEncryptSalt"/>', 'pwdEncryptSalt'), 'salt');
    expect(GenaiLogin.field("<input name='execution' value='e1s1'>", 'execution'), 'e1s1');
  });
  test('CAS password encryption matches GenAI2OpenAI', () {
    expect(
      GenaiLogin.encryptPassword('test-password', '1234567890123456'),
      '2LWYSMdnDJSym1TSN54ueiM+MTqBzvtIizRb62ttRF7LHyqJnnRF7TSKdRbojVUw0FcpVIctqIMgcad48Yo0iXPW9Ddd5+5IsUJRylmMEbw=',
    );
  });

  test('CAS login follows cookies and extracts token from redirect', () async {
    final ids = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => ids.close(force: true));
    ids.listen((req) async {
      if (req.uri.path == '/htk/user/login') {
        req.response.statusCode = 302;
        req.response.headers.set('location', '/authserver/login');
      } else if (req.method == 'GET') {
        req.response.cookies.add(Cookie('session', 'fixture'));
        req.response.headers.contentType = ContentType.html;
        req.response.write('<input id="pwdEncryptSalt" value="1234567890123456"/>'
            '<input name="execution" value="e1s1"/>');
      } else {
        expect(req.cookies.single.value, 'fixture');
        final form = Uri.splitQueryString(await utf8.decoder.bind(req).join());
        expect(form['username'], 'test-student');
        expect(form['password'], GenaiLogin.encryptPassword('test-password', '1234567890123456'));
        req.response.statusCode = HttpStatus.found;
        req.response.headers.set('location', '/dialogue?token=fixture-token');
      }
      await req.response.close();
    });
    final login = GenaiLogin(genaiBase: Uri.parse('http://127.0.0.1:${ids.port}'));
    expect(await login.login('test-student', 'test-password'), 'fixture-token');
  });
  test('tool SSE sends heartbeats before upstream headers arrive', () async {
    upstreamGate = Completer<void>();
    final req =
        await client.postUrl(Uri.parse('http://127.0.0.1:${gateway.port}/v1/chat/completions'));
    req.headers.set('Authorization', 'Bearer local-token');
    req.headers.contentType = ContentType.json;
    req.write(
      jsonEncode({
        'model': 'test-model',
        'stream': true,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
        'tools': [
          {
            'type': 'function',
            'function': {'name': 'weather'},
          }
        ],
      }),
    );
    final res = await req.close().timeout(const Duration(seconds: 2));
    expect(res.statusCode, 200);
    final lines = StreamIterator(res.transform(utf8.decoder).transform(const LineSplitter()));
    try {
      expect(await lines.moveNext().timeout(const Duration(seconds: 2)), true);
      expect(lines.current, ': keep-alive');
      expect(upstreamGate!.isCompleted, false);
      await lines.moveNext(); // Empty separator.
      expect(await lines.moveNext().timeout(const Duration(seconds: 2)), true);
      expect(lines.current, ': keep-alive');
      upstreamGate!.complete();
      final text = StringBuffer();
      while (await lines.moveNext()) {
        text.writeln(lines.current);
      }
      expect(text.toString(), contains('[DONE]'));
      expect(text.toString(), contains('你好'));
    } finally {
      if (!upstreamGate!.isCompleted) upstreamGate!.complete();
      await lines.cancel();
    }
  });

  test('empty tool streams return an error and terminate', () async {
    reply = '';
    final res = await request(
      '/v1/chat/completions',
      body: {
        'model': 'test-model',
        'stream': true,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
        'tools': [
          {
            'type': 'function',
            'function': {'name': 'weather'},
          }
        ],
      },
    );
    expect(res.body, contains('upstream_error'));
    expect(res.body, contains('[DONE]'));
    expect(res.body, isNot(contains('"finish_reason":"stop"')));
  });
  final tool = {
    'type': 'function',
    'function': {'name': 'weather'},
  };
  Map<String, dynamic> payload({bool stream = false, bool tools = false}) => {
        'model': 'test-model',
        'stream': stream,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
        if (tools) 'tools': [tool],
      };
  for (final stream in [false, true]) {
    for (final reason in ['length', 'content_filter']) {
      test('$reason is preserved, stream=$stream', () async {
        finishReason = reason;
        final res = await request('/v1/chat/completions', body: payload(stream: stream));
        expect(res.body, contains('"finish_reason":"$reason"'));
        expect(res.body, contains('你好'));
      });
    }
    test('EOF is an error, stream=$stream', () async {
      finishReason = null;
      final res = await request('/v1/chat/completions', body: payload(stream: stream));
      expect(res.body, contains('回复中断'));
      expect(res.body, isNot(contains('"finish_reason":"stop"')));
    });
    test('explicit DONE succeeds, stream=$stream', () async {
      finishReason = null;
      done = true;
      final res = await request('/v1/chat/completions', body: payload(stream: stream));
      expect(res.body, contains('"finish_reason":"stop"'));
      expect(diagnostics.last['saw_done'], true);
    });
    test('truncated tool is never executed, stream=$stream', () async {
      finishReason = 'length';
      reply = '{"name":"weather","arguments":{}}';
      final res = await request('/v1/chat/completions', body: payload(stream: stream, tools: true));
      expect(res.body, contains('工具调用未完成'));
      expect(res.body, isNot(contains('"finish_reason":"tool_calls"')));
    });
    test('multiple tools survive HTTP, stream=$stream', () async {
      reply =
          '[{"function":{"name":"weather","arguments":"{}"}},{"name":"weather","arguments":{}}] https://example.org';
      final res = await request('/v1/chat/completions', body: payload(stream: stream, tools: true));
      expect(res.body, contains('"finish_reason":"tool_calls"'));
      expect(diagnostics.last['call_count'], 2);
    });
    test('invalid tools fail HTTP, stream=$stream', () async {
      reply = '[{"name":"unknown","arguments":{}}]';
      final res = await request('/v1/chat/completions', body: payload(stream: stream, tools: true));
      expect(res.body, contains('工具名称不在本次请求中'));
    });
    test('Responses tools native lifecycle, stream=$stream', () async {
      reply = '{"function":{"name":"weather","arguments":"{}"}}';
      final res = await request(
        '/v1/responses',
        body: {
          'model': 'test-model',
          'stream': stream,
          'input': '天气',
          'tools': [
            {
              'type': 'function',
              'name': 'weather',
              'parameters': {'type': 'object'},
            }
          ],
        },
      );
      expect(res.body, contains('"type":"function_call"'));
      expect(res.body, isNot(contains('"type":"message"')));
      if (stream) {
        expect(res.body, contains('response.function_call_arguments.delta'));
        expect(res.body, contains('response.output_item.done'));
        expect(res.body, contains('response.completed'));
      }
    });
  }
  final goodCalls = [
    '{"tool_calls":[{"name":"weather","arguments":{}}]}',
    '[{"id":"call_x","type":"function","function":{"name":"weather","arguments":"{}"}}] link',
    '{"function":{"name":"weather","arguments":{}}}',
    '<tool_call>{"name":"weather"}</tool_call><tool_call>{"name":"weather"}</tool_call>',
    '{"name":"weather","arguments":{}} {"name":"weather","arguments":{}}',
  ];
  for (var i = 0; i < goodCalls.length; i++) {
    test('parser supported format $i', () {
      final calls = parseGenaiToolCalls(goodCalls[i], {'weather'}, null);
      expect(calls.length, i >= 3 ? 2 : 1);
      expect(calls.first['function']['arguments'], '{}');
      if (i == 1) expect(calls.first['id'], 'call_x');
    });
  }
  final badCalls = [
    '{"tool_calls":[{"name":"weather"},',
    '<tool_call>{"name":"weather"}',
    '{"name":"unknown","arguments":{}}',
    '{"name":"weather","arguments":"oops"}',
    '{"name":"weather","arguments":[]}',
    '{"name":"weather","arguments":"[]"}',
    '{"tool_calls":"oops"}',
    '[{"name":"weather","arguments":{}},4]',
  ];
  for (var i = 0; i < badCalls.length; i++) {
    test('parser rejects invalid format $i', () {
      expect(() => parseGenaiToolCalls(badCalls[i], {'weather'}, null), throwsFormatException);
    });
  }
  test('required and selected tools are enforced; final text stays valid', () async {
    expect(parseGenaiToolCalls('已完成', {'weather'}, null), isEmpty);
    for (final choice in [
      'required',
      {
        'type': 'function',
        'function': {'name': 'weather'},
      }
    ]) {
      final res = await request(
        '/v1/chat/completions',
        body: {...payload(tools: true), 'tool_choice': choice},
      );
      expect(res.body, contains('未返回指定工具调用'));
    }
  });
  test('completion limit precedence and diagnostics contain metadata only', () async {
    await request(
      '/v1/chat/completions',
      body: {...payload(), 'max_completion_tokens': 321, 'max_tokens': 12},
    );
    expect(received['body']['maxToken'], 321);
    expect(diagnostics.last['output_limit'], 321);
    expect(jsonEncode(diagnostics), isNot(contains('你好')));
    expect(jsonEncode(diagnostics), isNot(contains('upstream-token')));
  });
  test('Responses history preserves call IDs, arguments, output and assistant content', () async {
    final res = await request(
      '/v1/responses',
      body: {
        'model': 'test-model',
        'input': [
          {
            'type': 'message',
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': '天气'},
            ],
          },
          {'type': 'function_call', 'call_id': 'call_x', 'name': 'weather', 'arguments': '{}'},
          {'type': 'function_call_output', 'call_id': 'call_x', 'output': '夹具：晴'},
        ],
        'max_output_tokens': 77,
      },
    );
    expect(jsonDecode(res.body)['output_text'], '你好');
    expect(jsonEncode(received['body']['messages']), contains('call_x'));
    expect(jsonEncode(received['body']['messages']), contains('夹具：晴'));
    expect(received['body']['maxToken'], 77);
    await request(
      '/v1/chat/completions',
      body: {
        ...payload(),
        'messages': [
          {
            'role': 'assistant',
            'content': '先看天气',
            'tool_calls': [
              {
                'id': 'call_x',
                'function': {'name': 'weather', 'arguments': '{}'},
              }
            ],
          },
          {'role': 'tool', 'tool_call_id': 'call_x', 'content': '晴'},
        ],
      },
    );
    expect(received['body']['messages'][0]['content'], contains('先看天气'));
  });
  test('Responses length is incomplete and EOF streaming is failed', () async {
    finishReason = 'length';
    var res = await request('/v1/responses', body: {'model': 'test-model', 'input': 'hi'});
    expect(jsonDecode(res.body)['status'], 'incomplete');
    finishReason = null;
    res = await request(
      '/v1/responses',
      body: {'model': 'test-model', 'input': 'hi', 'stream': true},
    );
    expect(res.body, contains('response.failed'));
    expect(res.body, isNot(contains('response.completed')));
  });
  test('client cancellation closes the pending upstream request', () async {
    upstreamGate = Completer<void>();
    final req =
        await client.postUrl(Uri.parse('http://127.0.0.1:${gateway.port}/v1/chat/completions'));
    req.headers.set('Authorization', 'Bearer local-token');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(payload(stream: true)));
    final res = await req.close();
    final subscription = res.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await subscription.cancel();
    client.close(force: true);
    try {
      for (var i = 0; i < 100 && diagnostics.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(diagnostics, isNotEmpty);
      expect(diagnostics.last['cancelled'], true);
    } finally {
      upstreamGate!.complete();
      await subscription.cancel();
    }
  });
  test('Responses text lifecycle orders added, delta, done, completed', () async {
    final res = await request(
      '/v1/responses',
      body: {'model': 'test-model', 'input': 'hi', 'stream': true},
    );
    final events = const LineSplitter()
        .convert(res.body)
        .where((l) => l.startsWith('data:'))
        .map((l) => jsonDecode(l.substring(5)))
        .toList();
    expect(events.map((e) => e['type']).toList(), [
      'response.created',
      'response.output_item.added',
      'response.content_part.added',
      'response.output_text.delta',
      'response.output_text.done',
      'response.content_part.done',
      'response.output_item.done',
      'response.completed',
    ]);
    expect(events.map((e) => e['sequence_number']).toList(), List.generate(8, (i) => i));
    finishReason = 'length';
    final incomplete = await request(
      '/v1/responses',
      body: {'model': 'test-model', 'input': 'hi', 'stream': true},
    );
    expect(incomplete.body, contains('response.incomplete'));
    expect(incomplete.body, isNot(contains('response.completed')));
  });
  test('Responses EOF nonstream has failed status', () async {
    finishReason = null;
    final res = await request('/v1/responses', body: {'model': 'test-model', 'input': 'hi'});
    expect(jsonDecode(res.body)['status'], 'failed');
  });
  test('only complete calls with missing outer wrappers are repaired', () {
    const full = '{"tool_calls":[{"id":"call_x","function":{"name":"weather","arguments":"{}"}}]}';
    for (final text in [
      full.substring(0, full.length - 1),
      full.substring(0, full.length - 2),
      '[{"name":"weather","arguments":{}}',
    ]) {
      expect(parseGenaiToolCalls(text, {'weather'}, null).length, 1);
    }
    for (final text in [
      full.substring(0, full.length - 3),
      '${full.substring(0, full.length - 2)},',
      '{"tool_calls":[{"name":"weather","arguments":{"path":"abc',
      '[{"name":"weather","arguments":{"path":"abc"}',
      '${full.substring(0, full.length - 1)},"other":[',
    ]) {
      expect(() => parseGenaiToolCalls(text, {'weather'}, null), throwsFormatException);
    }
  });
  test('normal JSON and field explanations are final answers', () {
    for (final text in [
      '已完成，字段为 `"name": "demo"`。',
      '```json\n{"name":"demo","version":"1.0"}\n```',
      '检查结果：{"ok":true}\n字段示例包含 "name": "weather"。',
      '{"tool_calls":[]}',
      '{"function":"documentation","description":"API 示例"}',
      '[{"name":"demo","version":"1.0"}]',
    ]) {
      expect(parseGenaiToolCalls(text, {'weather'}, null), isEmpty);
    }
  });
  Map<String, dynamic> packet(Map<String, dynamic> delta, [String? finish]) => {
        'choices': [
          {'delta': delta, 'finish_reason': finish},
        ],
      };
  for (final stream in [false, true]) {
    test('empty generation retries once with identical history, stream=$stream', () async {
      attemptPackets = [
        [
          packet({'reasoning': 'discard this thought'}, 'stop'),
        ],
        [
          packet({'content': 'recovered'}, 'stop'),
        ]
      ];
      final res = await request('/v1/chat/completions', body: payload(stream: stream));
      expect(res.body, contains('recovered'));
      expect(res.body, isNot(contains('discard this thought')));
      expect(bodies.length, 2);
      expect(bodies[0], bodies[1]);
      expect(diagnostics.last['attempts'], 2);
    });
    test('two empty generations stop, stream=$stream', () async {
      reply = '';
      final res = await request('/v1/chat/completions', body: payload(stream: stream, tools: true));
      expect(res.body, contains('没有回复'));
      expect(bodies.length, 2);
    });
    test('errors, EOF, length and partial output never retry, stream=$stream', () async {
      for (final scenario in ['error', 'eof', 'length', 'partial']) {
        bodies.clear();
        attemptPackets = [
          [
            if (scenario == 'error')
              {
                'error': 'fixture failure',
              }
            else
              packet(
                {'content': scenario == 'partial' ? 'partial' : ''},
                scenario == 'length' ? 'length' : null,
              ),
          ]
        ];
        await request('/v1/chat/completions', body: payload(stream: stream));
        expect(bodies.length, 1, reason: scenario);
      }
    });
    test('native tool fragments accumulate and do not retry, stream=$stream', () async {
      attemptPackets = [
        [
          packet({
            'tool_calls': [
              {
                'index': 0,
                'id': 'call_native',
                'function': {'name': 'wea', 'arguments': '{"city":'},
              }
            ],
          }),
          packet(
            {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'name': 'ther', 'arguments': '"上海"}'},
                }
              ],
            },
            'tool_calls',
          ),
        ]
      ];
      final res = await request('/v1/chat/completions', body: payload(stream: stream, tools: true));
      expect(res.body, contains('call_native'));
      expect(res.body, contains('weather'));
      expect(res.body, contains('上海'));
      expect(bodies.length, 1);
      expect(diagnostics.last['call_count'], 1);
    });
    test('native calls with disabled tools or bad arguments fail, stream=$stream', () async {
      for (final tools in [false, true]) {
        attemptPackets = [
          [
            packet(
              {
                'tool_calls': [
                  {
                    'function': {'name': 'weather', 'arguments': '[]'},
                  }
                ],
              },
              'tool_calls',
            ),
          ]
        ];
        final res =
            await request('/v1/chat/completions', body: payload(stream: stream, tools: tools));
        expect(res.body, contains('error'));
        expect(res.body, isNot(contains('"finish_reason":"tool_calls"')));
      }
    });
  }
  test('native message fallback and legacy function call', () async {
    for (final legacy in [false, true]) {
      attemptPackets = [
        [
          {
            'choices': [
              {
                'message': legacy
                    ? <String, dynamic>{
                        'function_call': {'name': 'weather', 'arguments': '{}'},
                      }
                    : <String, dynamic>{
                        'tool_calls': [
                          {
                            'id': 'call_message',
                            'function': {'name': 'weather', 'arguments': <String, dynamic>{}},
                          }
                        ],
                      },
                'finish_reason': legacy ? 'function_call' : 'tool_calls',
              }
            ],
          }
        ]
      ];
      final res = await request('/v1/chat/completions', body: payload(tools: true));
      expect(jsonDecode(res.body)['choices'][0]['finish_reason'], 'tool_calls');
    }
  });
  test('Responses supports native calls after empty retry', () async {
    attemptPackets = [
      [packet({}, 'stop')],
      [
        packet(
          {
            'tool_calls': [
              {
                'id': 'call_r',
                'function': {'name': 'weather', 'arguments': '{}'},
              }
            ],
          },
          'tool_calls',
        ),
      ]
    ];
    final res = await request(
      '/v1/responses',
      body: {
        'model': 'test-model',
        'input': 'hi',
        'stream': true,
        'tools': [
          {'type': 'function', 'name': 'weather'},
        ],
      },
    );
    expect(res.body, contains('"type":"function_call"'));
    expect(res.body, contains('call_r'));
    expect(bodies.length, 2);
  });
}
