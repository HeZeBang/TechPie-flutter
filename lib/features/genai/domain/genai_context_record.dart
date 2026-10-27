import 'dart:convert';

const genAiContextExtractionPrefix = '<techpie-context-extraction version="1">';

/// A self-describing housekeeping turn stored in the original remote chat.
/// Its answer is a disposable cache, never conversation evidence or authority.
String genAiContextExtractionPrompt(String sourceHash) => '$genAiContextExtractionPrefix\n'
    '${jsonEncode({'kind': 'extract_memory', 'sourceHash': sourceHash})}\n'
    '</techpie-context-extraction>\n'
    'Extract durable memory from the historical records above. Return JSON only.';

bool isGenAiContextExtraction(String prompt) => genAiContextExtractionHash(prompt) != null;

String? genAiContextExtractionHash(String prompt) {
  final match = RegExp(
    r'^<techpie-context-extraction version="1">\s*(\{[^\n]*\})\s*</techpie-context-extraction>\nExtract durable memory from the historical records above\. Return JSON only\.$',
  ).firstMatch(prompt);
  if (match == null) return null;
  try {
    final value = jsonDecode(match.group(1)!);
    return value is Map &&
            value.length == 2 &&
            value['kind'] == 'extract_memory' &&
            value['sourceHash'] is String &&
            RegExp(r'^[0-9a-f]{64}$').hasMatch(value['sourceHash'] as String)
        ? value['sourceHash'] as String
        : null;
  } on FormatException {
    return null;
  }
}
