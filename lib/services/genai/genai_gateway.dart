// GenAI request mapping adapted from GenAI2OpenAI.
// See third_party/GenAI2OpenAI/LICENSE.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'genai_tools.dart';

class GenaiGateway {
  GenaiGateway({
    Uri? upstream,
    HttpClient Function()? clientFactory,
    this.onDiagnostic,
    this.tokenProvider,
    this.heartbeatInterval = const Duration(seconds: 5),
  })  : upstream = upstream ?? Uri.parse('https://genai.shanghaitech.edu.cn'),
        _clientFactory = clientFactory ?? HttpClient.new;

  final void Function(Map<String, Object?>)? onDiagnostic;
  Future<String> Function()? tokenProvider;
  final Uri upstream;
  final HttpClient Function() _clientFactory;
  final Duration heartbeatInterval;
  final Set<HttpClient> _streams = {};
  HttpServer? _server;
  HttpClient? _client;
  String _genaiToken = '';
  String _apiToken = '';
  final Map<String, String> _routes = {};
  int? get port => _server?.port;
  bool get running => _server != null;

  Future<void> start({
    required String host,
    required int port,
    required String genaiToken,
    required String apiToken,
  }) async {
    if (_server != null) return;
    _genaiToken = genaiToken;
    _apiToken = apiToken;
    _client = _clientFactory()..connectionTimeout = const Duration(seconds: 15);
    try {
      _server = await HttpServer.bind(host, port);
      _server!.listen((request) => unawaited(_handle(request)));
    } catch (_) {
      _client!.close(force: true);
      _client = null;
      rethrow;
    }
  }

  void updateGenaiToken(String token) => _genaiToken = token;

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _client?.close(force: true);
    _client = null;
    for (final client in _streams) {
      client.close(force: true);
    }
    _streams.clear();
    _genaiToken = '';
    _apiToken = '';
    _routes.clear();
    await server?.close(force: true);
  }

  void _json(HttpResponse response, Object body, [int status = 200]) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
  }

  Future<HttpClientResponse> _upstream(String path, {Object? body, HttpClient? client}) async {
    final provider = tokenProvider;
    final token = provider == null ? _genaiToken : await provider();
    final uri = upstream.resolve(path);
    final request = await (client ?? _client!).openUrl(body == null ? 'GET' : 'POST', uri);
    request.headers.set('X-Access-Token', token);
    request.headers.set('Origin', 'https://genai.shanghaitech.edu.cn');
    request.headers.set('Referer', 'https://genai.shanghaitech.edu.cn/dialogue');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json, text/event-stream');
    request.headers.contentType = ContentType.json;
    if (body != null) request.write(jsonEncode(body));
    return request.close().timeout(const Duration(seconds: 180));
  }

  Future<List<Map<String, dynamic>>> _models() async {
    final res = await _upstream('/htk/ai/aiModel/list?pageNo=1&pageSize=999&showStatusList=2%2C3');
    final data = jsonDecode(await utf8.decoder.bind(res).join());
    if (res.statusCode != 200 ||
        data is! Map ||
        data['success'] != true ||
        data['result'] is! Map ||
        data['result']['records'] is! List) {
      throw const FormatException('获取模型失败，请重新登录');
    }
    final records = (data['result']['records'] as List).whereType<Map<String, dynamic>>();
    final models = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final record in records) {
      final id = record['aiType'];
      if (id is! String || id.isEmpty || !seen.add(id)) continue;
      if (record['rootAiType'] is String) {
        _routes[id] = record['rootAiType'] as String;
      }
      models.add({'id': id, 'object': 'model', 'owned_by': 'genai'});
    }
    return models;
  }

  Future<void> _handle(HttpRequest request) async {
    final watch = Stopwatch()..start();
    final diagnostic = <String, Object?>{
      'request_id': 'req_${DateTime.now().microsecondsSinceEpoch}',
      'path': request.uri.path,
      'cancelled': false,
      'call_count': 0,
      'content_chars': 0,
      'saw_done': false,
    };
    request.response.headers.set('X-Request-Id', diagnostic['request_id']!);
    var completed = false;
    var streaming = false;
    Timer? heartbeat;
    StreamController<List<int>>? sse;
    Future<void>? ssePump;
    final cancelled = Completer<void>();
    HttpClient? streamClient;
    void closeStream() {
      heartbeat?.cancel();
      streamClient?.close(force: true);
      _streams.remove(streamClient);
    }

    void cancelRequest() {
      if (completed) return;
      diagnostic['cancelled'] = true;
      if (!cancelled.isCompleted) cancelled.complete();
      closeStream();
    }

    void writeSse(String value) {
      if (cancelled.isCompleted) throw const HttpException('Client disconnected');
      sse!.add(utf8.encode(value));
    }

    try {
      final path = request.uri.path;
      if (path == '/health' && request.method == 'GET') {
        _json(request.response, {'status': 'ok'});
        return;
      }
      var key = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
      if (key.toLowerCase().startsWith('bearer ')) key = key.substring(7).trim();
      key = key.isNotEmpty
          ? key
          : request.headers.value('x-api-key') ?? request.headers.value('api-key') ?? '';
      if (key != _apiToken) {
        _json(
          request.response,
          {
            'error': {'message': 'API Token 不对', 'type': 'authentication_error'},
          },
          401,
        );
        return;
      }
      if (path == '/v1/models' && request.method == 'GET') {
        _json(request.response, {'object': 'list', 'data': await _models()});
        return;
      }
      if (request.method != 'POST' || (path != '/v1/chat/completions' && path != '/v1/responses')) {
        _json(
          request.response,
          {
            'error': {'message': '接口不存在'},
          },
          404,
        );
        return;
      }
      final data = jsonDecode(await utf8.decoder.bind(request).join());
      if (data is! Map<String, dynamic>) throw const FormatException('请求格式不对');
      final model = data['model'];
      if (model is! String || model.isEmpty) throw const FormatException('请选择模型');
      final isResponses = path == '/v1/responses';
      var messages = isResponses ? _responseMessages(data) : data['messages'];
      if (messages is! List || messages.isEmpty || messages.any((m) => m is! Map)) {
        throw const FormatException('消息不能为空');
      }
      messages = messages.map((m) => Map<String, dynamic>.from(m as Map)).toList();
      diagnostic.addAll({'model': model, 'message_count': messages.length});
      final tools = data['tools'];
      final toolList = tools is List
          ? tools.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      final allowed = toolList
          .map((t) => (t['function'] is Map ? t['function']['name'] : t['name']))
          .whereType<String>()
          .toSet();
      final choice = data['tool_choice'];
      final selected = choice is Map
          ? (choice['function'] is Map ? choice['function']['name'] : choice['name'])
          : null;
      if ((choice == 'required' && allowed.isEmpty) ||
          (selected != null && !allowed.contains(selected))) {
        throw const FormatException('请选择可用工具');
      }
      final limit = isResponses
          ? data['max_output_tokens'] ?? 30000
          : data['max_completion_tokens'] ?? data['max_tokens'] ?? 30000;
      if (limit is! int || limit < 1) throw const FormatException('输出上限必须是正整数');
      diagnostic.addAll({
        'tool_count': toolList.length,
        'tool_choice': selected ?? (choice is String ? choice : 'auto'),
        'output_limit': limit,
      });
      final hasTools = tools is List && tools.isNotEmpty && data['tool_choice'] != 'none';
      if (hasTools) {
        messages = [
          ...messages,
          {
            'role': 'system',
            'content': '需要调用工具时，只输出 JSON：'
                '{"tool_calls":[{"name":"工具名","arguments":{}}]}。'
                '如果需要通过工具查看文件或执行操作，本轮必须输出工具调用，不能只描述接下来要做什么；完成后再总结。'
                '不需要工具时正常回答。tool_choice: ${jsonEncode(data['tool_choice'] ?? 'auto')}。'
                '工具：${jsonEncode(tools)}',
          }
        ];
      }
      final upstreamMessages = messages.map((dynamic m) {
        if (m['role'] == 'tool') {
          return {
            'role': 'user',
            'content': '工具 ${m['name'] ?? m['tool_call_id']} 返回：${m['content']}',
          };
        }
        if (m['role'] == 'assistant' && m['tool_calls'] != null) {
          return {
            'role': 'assistant',
            'content': '${m['content'] ?? ''}\n已请求调用工具：${jsonEncode(m['tool_calls'])}',
          };
        }
        return m;
      }).toList();
      final root = _routes[model] ??
          (RegExp(r'^(gpt|o3|o4-mini)', caseSensitive: false).hasMatch(model)
              ? 'azure'
              : 'xinference');
      final wantsStream = data['stream'] == true;
      streamClient = _clientFactory()..connectionTimeout = const Duration(seconds: 10);
      _streams.add(streamClient);
      unawaited(
        request.response.done.then<void>(
          (_) {
            if (!completed) diagnostic['cancelled'] = true;
            closeStream();
          },
          onError: (Object error, StackTrace stack) {
            diagnostic['cancelled'] = true;
            closeStream();
          },
        ),
      );
      if (wantsStream) {
        streaming = true;
        request.response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        request.response.headers.set('X-Accel-Buffering', 'no');
        request.response.bufferOutput = false;
        sse = StreamController<List<int>>(onCancel: cancelRequest);
        ssePump = request.response.addStream(sse.stream).then<void>(
          (_) {
            if (!completed) cancelRequest();
          },
          onError: (Object error, StackTrace stack) => cancelRequest(),
        );
        writeSse(': keep-alive\n\n');
        heartbeat = Timer.periodic(heartbeatInterval, (timer) {
          if (!cancelled.isCompleted) writeSse(': keep-alive\n\n');
        });
      }
      final id = '${isResponses ? 'resp' : 'chatcmpl'}-${DateTime.now().microsecondsSinceEpoch}';
      final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final content = StringBuffer();
      final reasoning = StringBuffer();
      Future<void> emit(Object event, [String? name]) async {
        if (name != null) writeSse('event: $name\n');
        writeSse('data: ${event is String ? event : jsonEncode(event)}\n\n');
      }

      Map<String, dynamic> chunk(Map<String, dynamic> delta, [String? finish]) => {
            'id': id,
            'object': 'chat.completion.chunk',
            'created': created,
            'model': model,
            'choices': [
              {'index': 0, 'delta': delta, 'finish_reason': finish},
            ],
          };
      if (wantsStream && isResponses) {
        await emit(
          {
            'type': 'response.created',
            'sequence_number': 0,
            'response': {
              'id': id,
              'object': 'response',
              'status': 'in_progress',
              'output': <Object>[],
            },
          },
          'response.created',
        );
      }
      String? upstreamFinish;
      var sawDone = false;
      var nativeCalls = GenaiToolAccumulator();
      for (var attempt = 1; attempt <= 2; attempt++) {
        if (cancelled.isCompleted) throw const HttpException('Client disconnected');
        diagnostic['attempts'] = attempt;
        if (attempt > 1) {
          streamClient!.close(force: true);
          _streams.remove(streamClient);
          streamClient = _clientFactory()..connectionTimeout = const Duration(seconds: 10);
          _streams.add(streamClient);
          content.clear();
          reasoning.clear();
          nativeCalls = GenaiToolAccumulator();
          upstreamFinish = null;
          sawDone = false;
        }
        var published = false;
        final upstreamResponse = await Future.any<HttpClientResponse>([
          cancelled.future
              .then<HttpClientResponse>((_) => throw const HttpException('Client disconnected')),
          _upstream(
            '/htk/chat/start/chat',
            client: streamClient,
            body: {
              'chatInfo': '',
              'messages': upstreamMessages,
              'type': '3',
              'stream': true,
              'aiType': model,
              'aiSecType': '1',
              'promptTokens': 0,
              'rootAiType': root,
              'maxToken': limit,
            },
          ),
        ]);
        diagnostic['connect_ms'] = watch.elapsedMilliseconds;
        if (upstreamResponse.statusCode != 200) {
          await upstreamResponse.drain<void>();
          throw FormatException('GenAI 返回 ${upstreamResponse.statusCode}');
        }

        await for (final line in upstreamResponse
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(const Duration(seconds: 180))) {
          final text = line.startsWith('data:') ? line.substring(5).trim() : line.trim();
          if (text == '[DONE]') {
            sawDone = true;
            break;
          }
          if (text.isEmpty) continue;
          dynamic event;
          try {
            event = jsonDecode(text);
          } on FormatException {
            continue;
          }
          if (event is! Map) continue;
          if (event['errMsg'] != null || event['success'] == false || event['error'] != null) {
            throw FormatException('${event['errMsg'] ?? event['message'] ?? event['error']}');
          }
          final choices = event['choices'];
          if (choices is! List || choices.isEmpty) continue;
          final choice = choices.first as Map;
          final delta = choice['delta'] ?? choice['message'];
          if (delta is Map) {
            final fragments = delta['tool_calls'] ??
                (delta['function_call'] == null
                    ? null
                    : [
                        {'index': 0, 'function': delta['function_call']},
                      ]);
            nativeCalls.add(fragments);
            if (nativeCalls.isNotEmpty && !hasTools) throw const FormatException('本次请求未启用工具');
            final body = delta['content'];
            final thought = delta['reasoning'] ?? delta['reasoning_content'];
            if (body is String && body.isNotEmpty) {
              diagnostic.putIfAbsent('first_content_ms', () => watch.elapsedMilliseconds);
              content.write(body);
            }
            if (thought is String) reasoning.write(thought);
            if (wantsStream && !hasTools && !isResponses && content.toString().trim().isNotEmpty) {
              await emit(
                chunk({
                  'role': 'assistant',
                  if (body is String) 'content': published ? body : content.toString(),
                  if (reasoning.isNotEmpty)
                    'reasoning_content': published ? (thought ?? '') : reasoning.toString(),
                }),
              );
              published = true;
            }
          }
          if (choice['finish_reason'] != null) {
            upstreamFinish = choice['finish_reason'].toString();
            break;
          }
        }
        final empty = content.toString().trim().isEmpty && !nativeCalls.isNotEmpty;
        final normalEnd = upstreamFinish == 'stop' || (upstreamFinish == null && sawDone);
        if (empty && normalEnd && attempt == 1) continue;
        break;
      }
      diagnostic.addAll({
        'content_chars': content.length,
        'upstream_finish_reason': upstreamFinish,
        'saw_done': sawDone,
      });
      if (upstreamFinish == null && !sawDone) {
        throw const FormatException('GenAI 回复中断');
      }
      if (content.toString().trim().isEmpty && !nativeCalls.isNotEmpty) {
        throw const FormatException('GenAI 没有回复，请重试');
      }
      heartbeat?.cancel();
      final truncated = upstreamFinish != null &&
          upstreamFinish != 'stop' &&
          upstreamFinish != 'tool_calls' &&
          upstreamFinish != 'function_call';
      if (hasTools &&
          truncated &&
          (nativeCalls.isNotEmpty || looksLikeToolProtocol(content.toString()))) {
        throw const FormatException('工具调用未完成，请重试');
      }
      final calls = hasTools && !truncated
          ? parseGenaiToolCalls(
              nativeCalls.isNotEmpty
                  ? jsonEncode({'tool_calls': nativeCalls.result()})
                  : content.toString(),
              allowed,
              choice,
            )
          : <Map<String, dynamic>>[];
      if ((upstreamFinish == 'tool_calls' || upstreamFinish == 'function_call') && calls.isEmpty) {
        throw const FormatException('GenAI 未返回完整工具调用');
      }
      diagnostic['call_count'] = calls.length;
      final finish = truncated
          ? upstreamFinish
          : calls.isEmpty
              ? (upstreamFinish ?? 'stop')
              : 'tool_calls';
      if (isResponses) {
        final response = {
          'id': id,
          'object': 'response',
          'created_at': created,
          'status': truncated ? 'incomplete' : 'completed',
          if (truncated)
            'incomplete_details': {'reason': finish == 'length' ? 'max_output_tokens' : finish},
          'model': model,
          'output_text': calls.isEmpty ? content.toString() : '',
          'output': [
            for (final call in calls)
              {
                'id': 'fc_${call['id']}',
                'type': 'function_call',
                'status': 'completed',
                'call_id': call['id'],
                'name': call['function']['name'],
                'arguments': call['function']['arguments'],
              },
            if (calls.isEmpty)
              {
                'id': 'msg_$id',
                'type': 'message',
                'role': 'assistant',
                'status': truncated ? 'incomplete' : 'completed',
                'content': [
                  {'type': 'output_text', 'text': content.toString(), 'annotations': <Object>[]},
                ],
              },
          ],
        };
        if (wantsStream) {
          var sequence = 1;
          Future<void> responseEvent(String type, Map<String, dynamic> fields) =>
              emit({'type': type, 'sequence_number': sequence++, ...fields}, type);
          final output = response['output'] as List;
          for (var i = 0; i < output.length; i++) {
            final item = output[i] as Map<String, dynamic>;
            final isCall = item['type'] == 'function_call';
            await responseEvent('response.output_item.added', {
              'output_index': i,
              'item': {
                ...item,
                'status': 'in_progress',
                if (isCall) 'arguments': '',
                if (!isCall) 'content': <Object>[],
              },
            });
            if (isCall) {
              await responseEvent(
                'response.function_call_arguments.delta',
                {'item_id': item['id'], 'output_index': i, 'delta': item['arguments']},
              );
              await responseEvent(
                'response.function_call_arguments.done',
                {'item_id': item['id'], 'output_index': i, 'arguments': item['arguments']},
              );
            } else {
              final part = (item['content'] as List).first;
              final fields = {'item_id': item['id'], 'output_index': i, 'content_index': 0};
              await responseEvent('response.content_part.added', {
                ...fields,
                'part': {'type': 'output_text', 'text': '', 'annotations': <Object>[]},
              });
              await responseEvent(
                'response.output_text.delta',
                {...fields, 'delta': content.toString()},
              );
              await responseEvent(
                'response.output_text.done',
                {...fields, 'text': content.toString()},
              );
              await responseEvent('response.content_part.done', {...fields, 'part': part});
            }
            await responseEvent('response.output_item.done', {'output_index': i, 'item': item});
          }
          final terminal = truncated ? 'response.incomplete' : 'response.completed';
          await responseEvent(terminal, {'response': response});
        } else {
          _json(request.response, response);
        }
      } else if (wantsStream) {
        if (hasTools) {
          await emit(
            chunk(
              calls.isEmpty
                  ? {'content': content.toString()}
                  : {
                      'tool_calls': [
                        for (var i = 0; i < calls.length; i++) {'index': i, ...calls[i]},
                      ],
                    },
            ),
          );
        }
        await emit(chunk({}, finish));
        await emit('[DONE]');
      } else {
        _json(request.response, {
          'id': id,
          'object': 'chat.completion',
          'created': created,
          'model': model,
          'choices': [
            {
              'index': 0,
              'finish_reason': finish,
              'message': {
                'role': 'assistant',
                'content': calls.isEmpty ? content.toString() : null,
                if (calls.isNotEmpty) 'tool_calls': calls,
                if (reasoning.isNotEmpty) 'reasoning_content': reasoning.toString(),
              },
            }
          ],
        });
      }
      completed = true;
    } catch (e) {
      diagnostic['exception_category'] = e.runtimeType.toString();
      final message = e is FormatException ? e.message : '请求失败，请重试';
      try {
        if (streaming) {
          if (request.uri.path == '/v1/responses') {
            writeSse('event: response.failed\ndata: ${jsonEncode({
                  'type': 'response.failed',
                  'response': {
                    'object': 'response',
                    'status': 'failed',
                    'error': {'code': 'upstream_error', 'message': message},
                  },
                })}\n\n');
          } else {
            writeSse('data: ${jsonEncode({
                  'error': {'message': message, 'type': 'upstream_error'},
                })}\n\ndata: [DONE]\n\n');
          }
        } else {
          _json(
            request.response,
            {
              if (request.uri.path == '/v1/responses') ...{
                'id': 'resp_${diagnostic['request_id']}',
                'object': 'response',
                'status': 'failed',
                'output': <Object>[],
              },
              'error': {'message': message, 'code': 'upstream_error'},
            },
            e is FormatException ? 400 : 502,
          );
        }
      } catch (_) {/* Client already disconnected. */}
    } finally {
      completed = true;
      await sse?.close();
      await ssePump;
      diagnostic['completion_ms'] = watch.elapsedMilliseconds;
      try {
        onDiagnostic?.call(Map.unmodifiable(diagnostic));
      } catch (_) {}
      closeStream();
      try {
        await request.response.close();
      } catch (_) {/* Client disconnected. */}
    }
  }

  List<Map<String, dynamic>> _responseMessages(Map<String, dynamic> data) {
    final input = data['input'];
    return [
      if (data['instructions'] is String) {'role': 'system', 'content': data['instructions']},
      if (input is String) {'role': 'user', 'content': input},
      if (input is List)
        for (final m in input.whereType<Map<String, dynamic>>())
          if (m['type'] == 'function_call')
            {
              'role': 'assistant',
              'tool_calls': [
                {
                  'id': m['call_id'],
                  'type': 'function',
                  'function': {'name': m['name'], 'arguments': m['arguments']},
                }
              ],
            }
          else if (m['type'] == 'function_call_output')
            {
              'role': 'tool',
              'tool_call_id': m['call_id'],
              'content': m['output'] is String ? m['output'] : jsonEncode(m['output']),
            }
          else
            {
              'role': m['role'] ?? 'user',
              'content': m['content'] is List
                  ? (m['content'] as List)
                      .whereType<Map<String, dynamic>>()
                      .map((part) => part['text'] ?? '')
                      .join('\n')
                  : m['content'],
            },
    ];
  }
}
