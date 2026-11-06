/// Image sizing contract from the university reference, section 5.3.
final class GenAiImageSize {
  const GenAiImageSize(this.width, this.height);

  static const minPixels = 655360;
  static const maxPixels = 8294400;
  static const presets = <String, Map<String, String>>{
    '1:1': {'1K': '1024x1024', '2K': '2048x2048'},
    '3:2': {'1K': '1024x688', '2K': '2048x1360'},
    '2:3': {'1K': '688x1024', '2K': '1360x2048'},
    '4:3': {'1K': '1024x768', '2K': '2048x1536'},
    '3:4': {'1K': '768x1024', '2K': '1536x2048'},
    '5:4': {'1K': '1024x816', '2K': '2560x2048'},
    '4:5': {'1K': '816x1024', '2K': '2048x2560'},
    '16:9': {'1K': '1136x640', '2K': '2048x1152', '4K': '3840x2160'},
    '9:16': {'1K': '640x1136', '2K': '1152x2048', '4K': '2160x3840'},
    '2:1': {'1K': '1152x576', '2K': '2688x1344', '4K': '3840x1920'},
    '1:2': {'1K': '576x1152', '2K': '1344x2688', '4K': '1920x3840'},
    '21:9': {'1K': '1344x576', '2K': '2688x1152', '4K': '3840x1648'},
    '9:21': {'1K': '576x1344', '2K': '1152x2688', '4K': '1648x3840'},
  };

  final int width;
  final int height;
  int get pixels => width * height;
  bool get isValid =>
      width > 0 && height > 0 && pixels >= minPixels && pixels <= maxPixels;
  bool get isExperimental => width > 2560 || height > 1440;
  String get value => '${width}x$height';

  static GenAiImageSize? tryParse(String value) {
    final match =
        RegExp(r'^([1-9][0-9]{0,6})x([1-9][0-9]{0,6})$').firstMatch(value);
    if (match == null) return null;
    return GenAiImageSize(int.parse(match[1]!), int.parse(match[2]!));
  }
}
