import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'genai_contract.dart';

/// Content addresses survive reconstruction from school history. They confer
/// no authority and are resolved only within the current conversation snapshot.
String genAiContextSourceId(GenAiMessage message) {
  final encoded = jsonEncode([message.role.name, message.content]);
  return 'r_${sha256.convert(utf8.encode(encoded)).toString().substring(0, 24)}';
}

const genAiHistoryToolNames = {'search_conversation', 'read_conversation_records'};
