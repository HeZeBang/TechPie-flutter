import 'package:flutter/foundation.dart';

// CanvasKit cannot resolve CSS system fonts. Reuse the monospace face already
// shipped by flutter_math_fork, rather than bundling another code font.
const kGenAiMonospaceFamily = kIsWeb ? 'packages/flutter_math_fork/KaTeX_Typewriter' : 'monospace';
const kGenAiMonospaceFallback = [
  'Menlo',
  'Consolas',
  'packages/flutter_math_fork/KaTeX_Typewriter',
];
