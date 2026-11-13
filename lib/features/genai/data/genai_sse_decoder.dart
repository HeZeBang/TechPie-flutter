import 'dart:convert';

import '../domain/genai_failure.dart';

final class GenAiSseEvent {
  const GenAiSseEvent(this.data, this.type);
  final String data;
  final String type;
}

/// UTF-8 decoding precedes SSE framing; neither socket chunks nor lines are
/// complete events. EOF does not dispatch an unterminated event.
final class GenAiSseDecoder {
  const GenAiSseDecoder({this.maxEventBytes = 256 * 1024});

  final int maxEventBytes;

  Stream<GenAiSseEvent> decode(Stream<List<int>> bytes) async* {
    var data = <String>[];
    var type = 'message';
    var size = 0;
    try {
      final lines = _boundedLines(bytes)
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.isEmpty) {
          if (data.isNotEmpty) yield GenAiSseEvent(data.join('\n'), type);
          data = [];
          type = 'message';
          size = 0;
          continue;
        }
        size += utf8.encode(line).length + 1;
        if (size > maxEventBytes) {
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
        if (line.startsWith(':')) continue;
        final separator = line.indexOf(':');
        final field = separator < 0 ? line : line.substring(0, separator);
        var value = separator < 0 ? '' : line.substring(separator + 1);
        if (value.startsWith(' ')) value = value.substring(1);
        if (field == 'data') data.add(value);
        if (field == 'event') type = value;
      }
    } on FormatException {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
  }

  Stream<List<int>> _boundedLines(Stream<List<int>> bytes) async* {
    var size = 0;
    await for (final chunk in bytes) {
      for (final byte in chunk) {
        if (byte == 10 || byte == 13) {
          size = 0;
        } else if (++size > maxEventBytes) {
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
      }
      yield chunk;
    }
  }
}
