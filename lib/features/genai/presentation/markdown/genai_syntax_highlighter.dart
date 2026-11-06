import 'package:flutter/material.dart';

import 'genai_code_font.dart';

/// Syntax token classification for code highlighting.
enum SyntaxTokenType {
  keyword,
  type,
  string,
  comment,
  number,
  functionName,
  variable,
  annotation,
  property,
  operator,
  punctuation,
  tag,
  attribute,
  plain,
}

/// Color theme definition for syntax highlighting.
class SyntaxTheme {
  const SyntaxTheme({
    required this.keyword,
    required this.type,
    required this.string,
    required this.comment,
    required this.number,
    required this.functionName,
    required this.variable,
    required this.annotation,
    required this.property,
    required this.operator,
    required this.plain,
  });

  final Color keyword;
  final Color type;
  final Color string;
  final Color comment;
  final Color number;
  final Color functionName;
  final Color variable;
  final Color annotation;
  final Color property;
  final Color operator;
  final Color plain;

  Color get tag => keyword;
  Color get attribute => type;

  /// Dark theme palette (VS Code Dark+ / One Dark inspired).
  static const dark = SyntaxTheme(
    keyword: Color(0xFFC586C0),
    type: Color(0xFF4EC9B0),
    string: Color(0xFFCE9178),
    comment: Color(0xFF6A9955),
    number: Color(0xFFB5CEA8),
    functionName: Color(0xFFDCDCAA),
    variable: Color(0xFF9CDCFE),
    annotation: Color(0xFFD7BA7D),
    property: Color(0xFF9CDCFE),
    operator: Color(0xFFD4D4D4),
    plain: Color(0xFFD4D4D4),
  );

  /// Light theme palette (GitHub Light / One Light inspired).
  static const light = SyntaxTheme(
    keyword: Color(0xFFA626A4),
    type: Color(0xFF0184BC),
    string: Color(0xFF50A14F),
    comment: Color(0xFFA0A1A7),
    number: Color(0xFF986801),
    functionName: Color(0xFF4078F2),
    variable: Color(0xFFE45649),
    annotation: Color(0xFFC18401),
    property: Color(0xFF0184BC),
    operator: Color(0xFF383A42),
    plain: Color(0xFF383A42),
  );

  Color colorFor(SyntaxTokenType type) {
    switch (type) {
      case SyntaxTokenType.keyword:
        return keyword;
      case SyntaxTokenType.type:
        return this.type;
      case SyntaxTokenType.string:
        return string;
      case SyntaxTokenType.comment:
        return comment;
      case SyntaxTokenType.number:
        return number;
      case SyntaxTokenType.functionName:
        return functionName;
      case SyntaxTokenType.variable:
        return variable;
      case SyntaxTokenType.annotation:
        return annotation;
      case SyntaxTokenType.property:
        return property;
      case SyntaxTokenType.tag:
        return keyword;
      case SyntaxTokenType.attribute:
        return this.type;
      case SyntaxTokenType.operator:
        return operator;
      case SyntaxTokenType.punctuation:
      case SyntaxTokenType.plain:
        return plain;
    }
  }
}

/// A lightweight, robust, streaming-safe syntax highlighter for common programming languages.
class GenAiSyntaxHighlighter {
  const GenAiSyntaxHighlighter({
    required this.brightness,
    this.customTheme,
  });

  final Brightness brightness;
  final SyntaxTheme? customTheme;

  SyntaxTheme get theme =>
      customTheme ?? (brightness == Brightness.dark ? SyntaxTheme.dark : SyntaxTheme.light);

  static const Set<String> _dartKeywords = {
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'base',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'function',
    'get',
    'hide',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'of',
    'on',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'sealed',
    'set',
    'show',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'var',
    'void',
    'when',
    'with',
    'yield',
  };

  static const Set<String> _dartTypes = {
    'int',
    'double',
    'num',
    'bool',
    'String',
    'List',
    'Map',
    'Set',
    'Future',
    'Stream',
    'Iterable',
    'Duration',
    'DateTime',
    'Uri',
    'RegExp',
    'Widget',
    'StatelessWidget',
    'StatefulWidget',
    'State',
    'BuildContext',
    'Key',
    'Color',
    'Colors',
    'Theme',
    'ThemeData',
    'TextStyle',
    'Container',
    'Column',
    'Row',
    'Text',
    'Icon',
    'Icons',
    'Scaffold',
    'Center',
    'Padding',
    'SizedBox',
    'Expanded',
    'Align',
    'MaterialApp',
    'Object',
    'Never',
  };

  static const Set<String> _pythonKeywords = {
    'and',
    'as',
    'assert',
    'async',
    'await',
    'break',
    'case',
    'class',
    'continue',
    'def',
    'del',
    'elif',
    'else',
    'except',
    'finally',
    'for',
    'from',
    'global',
    'if',
    'import',
    'in',
    'is',
    'lambda',
    'match',
    'nonlocal',
    'not',
    'or',
    'pass',
    'raise',
    'return',
    'try',
    'while',
    'with',
    'yield',
  };

  static const Set<String> _pythonTypes = {
    'True',
    'False',
    'None',
    'int',
    'float',
    'str',
    'bool',
    'list',
    'dict',
    'set',
    'tuple',
    'bytes',
    'len',
    'range',
    'print',
    'type',
    'enumerate',
    'zip',
    'isinstance',
    'issubclass',
    'map',
    'filter',
    'sum',
    'min',
    'max',
    'abs',
    'open',
    'input',
    'super',
    'self',
    'cls',
  };

  static const Set<String> _jsKeywords = {
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'debugger',
    'default',
    'delete',
    'do',
    'else',
    'export',
    'extends',
    'finally',
    'for',
    'from',
    'function',
    'get',
    'if',
    'import',
    'in',
    'instanceof',
    'interface',
    'let',
    'new',
    'of',
    'return',
    'set',
    'static',
    'super',
    'switch',
    'this',
    'throw',
    'try',
    'typeof',
    'var',
    'void',
    'while',
    'with',
    'yield',
    'type',
    'namespace',
    'declare',
    'module',
    'as',
    'is',
    'keyof',
    'readonly',
    'public',
    'private',
    'protected',
    'implements',
  };

  static const Set<String> _jsTypes = {
    'true',
    'false',
    'null',
    'undefined',
    'NaN',
    'Infinity',
    'string',
    'number',
    'boolean',
    'any',
    'unknown',
    'never',
    'symbol',
    'bigint',
    'void',
    'object',
    'Array',
    'Object',
    'Function',
    'Promise',
    'Map',
    'Set',
    'Date',
    'RegExp',
    'Error',
    'JSON',
    'Math',
    'console',
    'window',
    'document',
  };

  static const Set<String> _sqlKeywords = {
    'select',
    'from',
    'where',
    'insert',
    'into',
    'values',
    'update',
    'set',
    'delete',
    'create',
    'table',
    'drop',
    'alter',
    'view',
    'index',
    'join',
    'inner',
    'left',
    'right',
    'full',
    'outer',
    'cross',
    'on',
    'group',
    'by',
    'order',
    'having',
    'limit',
    'offset',
    'and',
    'or',
    'not',
    'in',
    'is',
    'null',
    'like',
    'between',
    'union',
    'all',
    'as',
    'distinct',
    'case',
    'when',
    'then',
    'else',
    'end',
    'primary',
    'key',
    'foreign',
    'references',
    'default',
    'check',
    'cascade',
    'with',
    'recursive',
  };

  static const Set<String> _sqlTypes = {
    'count',
    'sum',
    'avg',
    'min',
    'max',
    'coalesce',
    'now',
    'int',
    'integer',
    'varchar',
    'char',
    'text',
    'boolean',
    'timestamp',
    'date',
    'float',
    'numeric',
    'decimal',
  };

  static const Set<String> _bashKeywords = {
    'if',
    'then',
    'elif',
    'else',
    'fi',
    'for',
    'in',
    'do',
    'done',
    'while',
    'until',
    'case',
    'esac',
    'function',
    'select',
    'time',
    'return',
    'exit',
    'echo',
    'cd',
    'pwd',
    'ls',
    'cat',
    'grep',
    'sed',
    'awk',
    'find',
    'curl',
    'wget',
    'mkdir',
    'rm',
    'cp',
    'mv',
    'chmod',
    'chown',
    'sudo',
    'export',
    'source',
    'alias',
    'tar',
    'git',
    'npm',
    'yarn',
    'flutter',
    'dart',
    'python',
    'pip',
    'docker',
  };

  static const Set<String> _cppKeywords = {
    'auto',
    'break',
    'case',
    'char',
    'const',
    'continue',
    'default',
    'do',
    'double',
    'else',
    'enum',
    'extern',
    'float',
    'for',
    'goto',
    'if',
    'inline',
    'int',
    'long',
    'register',
    'restrict',
    'return',
    'short',
    'signed',
    'sizeof',
    'static',
    'struct',
    'switch',
    'typedef',
    'union',
    'unsigned',
    'void',
    'volatile',
    'while',
    'class',
    'public',
    'private',
    'protected',
    'virtual',
    'friend',
    'template',
    'typename',
    'namespace',
    'using',
    'new',
    'delete',
    'this',
    'operator',
    'explicit',
    'nullptr',
    'true',
    'false',
    'try',
    'catch',
    'throw',
    'constexpr',
    'decltype',
    'noexcept',
    'override',
    'final',
  };

  /// Tokenizes [code] into highlighted [TextSpan]s.
  List<TextSpan> highlight({
    required String code,
    String? language,
    TextStyle? baseStyle,
  }) {
    if (code.isEmpty) return const [];

    final lang = language?.toLowerCase().trim() ?? '';
    final defaultStyle = (baseStyle ??
            const TextStyle(
              fontFamily: kGenAiMonospaceFamily,
              fontFamilyFallback: kGenAiMonospaceFallback,
            ))
        .copyWith(color: theme.plain);

    final spans = <TextSpan>[];
    final isPython = lang == 'python' || lang == 'py';
    final isDart = lang == 'dart';
    final isJsOrTs = lang == 'javascript' ||
        lang == 'js' ||
        lang == 'typescript' ||
        lang == 'ts' ||
        lang == 'jsx' ||
        lang == 'tsx' ||
        lang == 'mjs';
    final isJson = lang == 'json';
    final isSql = lang == 'sql';
    final isBash = lang == 'bash' || lang == 'sh' || lang == 'zsh' || lang == 'shell';
    final isCpp = lang == 'c' ||
        lang == 'cpp' ||
        lang == 'cxx' ||
        lang == 'cc' ||
        lang == 'h' ||
        lang == 'hpp';
    final isHtmlOrXml = lang == 'html' || lang == 'xml' || lang == 'svg' || lang == 'htm';

    // Build regular expression for language tokens
    final patterns = <String>[];

    // 1. Comments
    if (isHtmlOrXml) {
      patterns.add(r'<!--[\s\S]*?(?:-->|$)');
    } else if (isPython || isBash) {
      patterns.add(r'#[^\r\n]*');
    } else if (isSql) {
      patterns.add(r'--[^\r\n]*');
      patterns.add(r'/\*[\s\S]*?(?:\*/|$)');
    } else {
      // Dart, JS/TS, C++, general
      patterns.add(r'//[^\r\n]*');
      patterns.add(r'/\*[\s\S]*?(?:\*/|$)');
    }

    // 2. Triple quotes / Template strings
    if (isPython || isDart) {
      patterns.add(r'"""[\s\S]*?(?:"""|$)');
      patterns.add(r"'''[\s\S]*?(?:'''|$)");
    }
    if (isJsOrTs) {
      patterns.add(r'`[\s\S]*?(?:`|$)');
    }

    // 3. Single / Double quoted strings
    patterns.add(r'"(?:[^"\\\r\n]|\\.)*"?');
    patterns.add(r"'(?:[^'\\\r\n]|\\.)*'?");

    // 4. HTML/XML Tags and attributes
    if (isHtmlOrXml) {
      patterns.add(r'</?[a-zA-Z0-9_\-]+>?');
      patterns.add(r'[a-zA-Z0-9_\-]+(?=\s*=)');
    }

    // 5. Annotations / Preprocessor
    if (isCpp) {
      patterns.add(r'#[a-zA-Z_]\w*');
    } else if (isDart || isPython) {
      patterns.add(r'@[a-zA-Z_]\w*');
    }

    // 6. Shell / Bash Variables
    if (isBash) {
      patterns.add(r'\$[a-zA-Z_0-9]+|\$\{[^}]*\}?');
    }

    // 7. Numbers
    patterns.add(r'\b0x[0-9a-fA-F]+\b');
    patterns.add(r'\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b');

    // 8. Word identifiers
    patterns.add(r'[a-zA-Z_$][a-zA-Z0-9_$]*');

    // 9. Multi-char operators
    patterns.add(r'=>|->|::|==|!=|<=|>=|&&|\|\||\+\+|--|\+=|-=|\*=|/=|%=');

    // 10. Whitespace and all other chars
    patterns.add(r'\s+');
    patterns.add(r'.');

    final masterRegex = RegExp(patterns.join('|'), multiLine: true);
    final matches = masterRegex.allMatches(code);

    for (final match in matches) {
      final token = match.group(0)!;
      if (token.isEmpty) continue;

      final firstChar = token[0];

      // Whitespace
      if (token.trim().isEmpty) {
        spans.add(TextSpan(text: token, style: defaultStyle));
        continue;
      }

      // Comments
      if (token.startsWith('//') ||
          token.startsWith('/*') ||
          token.startsWith('<!--') ||
          ((isPython || isBash) && token.startsWith('#')) ||
          (isSql && token.startsWith('--'))) {
        spans.add(
          TextSpan(
            text: token,
            style: defaultStyle.copyWith(
              color: theme.comment,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
        continue;
      }

      // Strings
      if (token.startsWith('"') || token.startsWith("'") || token.startsWith('`')) {
        // Special JSON property check: "key":
        if (isJson && token.startsWith('"')) {
          final nextIndex = match.end;
          final remaining = code.substring(nextIndex);
          if (remaining.trimLeft().startsWith(':')) {
            spans.add(
              TextSpan(
                text: token,
                style: defaultStyle.copyWith(color: theme.property),
              ),
            );
            continue;
          }
        }
        spans.add(
          TextSpan(
            text: token,
            style: defaultStyle.copyWith(color: theme.string),
          ),
        );
        continue;
      }

      // HTML Tag
      if (isHtmlOrXml && token.startsWith('<')) {
        spans.add(
          TextSpan(
            text: token,
            style: defaultStyle.copyWith(
              color: theme.tag,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        continue;
      }

      // Annotations / Preprocessor
      if (token.startsWith('@') || (isCpp && token.startsWith('#'))) {
        spans.add(
          TextSpan(
            text: token,
            style: defaultStyle.copyWith(color: theme.annotation),
          ),
        );
        continue;
      }

      // Shell Variables
      if (isBash && token.startsWith(r'$')) {
        spans.add(
          TextSpan(
            text: token,
            style: defaultStyle.copyWith(color: theme.variable),
          ),
        );
        continue;
      }

      // Numbers
      if (RegExp(r'^(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)$').hasMatch(token)) {
        spans.add(
          TextSpan(
            text: token,
            style: defaultStyle.copyWith(color: theme.number),
          ),
        );
        continue;
      }

      // Identifiers / Words
      if (RegExp(r'^[a-zA-Z_$][a-zA-Z0-9_$]*$').hasMatch(token)) {
        final lower = token.toLowerCase();

        // 1. Keywords
        var isKeyword = false;
        if (isDart && _dartKeywords.contains(token)) {
          isKeyword = true;
        } else if (isPython && _pythonKeywords.contains(token)) {
          isKeyword = true;
        } else if (isJsOrTs && _jsKeywords.contains(token)) {
          isKeyword = true;
        } else if (isSql && _sqlKeywords.contains(lower)) {
          isKeyword = true;
        } else if (isBash && _bashKeywords.contains(lower)) {
          isKeyword = true;
        } else if (isCpp && _cppKeywords.contains(token)) {
          isKeyword = true;
        } else if (token == 'true' || token == 'false' || token == 'null' || token == 'undefined') {
          isKeyword = true;
        }

        if (isKeyword) {
          spans.add(
            TextSpan(
              text: token,
              style: defaultStyle.copyWith(
                color: theme.keyword,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
          continue;
        }

        // 2. Types / Built-ins
        var isType = false;
        if (isDart && _dartTypes.contains(token)) {
          isType = true;
        } else if (isPython && _pythonTypes.contains(token)) {
          isType = true;
        } else if (isJsOrTs && _jsTypes.contains(token)) {
          isType = true;
        } else if (isSql && _sqlTypes.contains(lower)) {
          isType = true;
        } else if (RegExp(r'^[A-Z][a-zA-Z0-9_$]*$').hasMatch(token)) {
          // PascalCase convention is universally a Type/Class across languages
          isType = true;
        }

        if (isType) {
          spans.add(
            TextSpan(
              text: token,
              style: defaultStyle.copyWith(
                color: theme.type,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
          continue;
        }

        // 3. HTML Attribute
        if (isHtmlOrXml) {
          final nextIndex = match.end;
          final remaining = code.substring(nextIndex);
          if (remaining.trimLeft().startsWith('=')) {
            spans.add(
              TextSpan(
                text: token,
                style: defaultStyle.copyWith(color: theme.attribute),
              ),
            );
            continue;
          }
        }

        // 4. Function call check: identifier followed by '('
        final nextIndex = match.end;
        if (nextIndex < code.length) {
          final remaining = code.substring(nextIndex);
          if (remaining.trimLeft().startsWith('(')) {
            spans.add(
              TextSpan(
                text: token,
                style: defaultStyle.copyWith(color: theme.functionName),
              ),
            );
            continue;
          }
        }

        // Default identifier
        spans.add(TextSpan(text: token, style: defaultStyle));
        continue;
      }

      // Operators and punctuation
      if (r'=+-*/%!<>|&~^?:'.contains(firstChar)) {
        spans.add(
          TextSpan(
            text: token,
            style: defaultStyle.copyWith(color: theme.operator),
          ),
        );
        continue;
      }

      // Default fallback
      spans.add(TextSpan(text: token, style: defaultStyle));
    }

    return spans;
  }
}
