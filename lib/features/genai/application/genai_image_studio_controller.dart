import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_image_size.dart';
import '../domain/genai_platform_contract.dart';
import '../domain/genai_reference_image.dart';
import 'genai_repository.dart';

/// In-memory, account-scoped draft. Navigation must not discard an image job.
final class GenAiImageDraft {
  String prompt = '';
  GenAiModel? model;
  String aspectRatio = '1:1';
  String resolution = '1K';
  String width = '1024';
  String height = '1024';
  bool linked = true;
  String quality = 'low';
  final references = <GenAiReferenceImage>[];
  final previews = <GenAiReferenceImage, Uint8List>{};
  bool get custom => resolution == 'custom';
  String get size => GenAiImageSize.presets[aspectRatio]?[resolution] ?? '${width}x$height';

  void selectResolution(String value) {
    if (resolution == value) return;
    if (value == 'custom') {
      final preset = GenAiImageSize.tryParse(size);
      if (preset != null) {
        width = preset.width.toString();
        height = preset.height.toString();
      }
    }
    resolution = value;
  }

  void toggleLinked() {
    linked = !linked;
    if (linked) _alignDimension((int.tryParse(width) ?? 0) > 0);
  }

  void editDimension(String value, {required bool isWidth}) {
    if (isWidth) {
      width = value;
    } else {
      height = value;
    }
    if (linked) {
      _alignDimension(isWidth);
      return;
    }
    final dimensions = GenAiImageSize.tryParse(size);
    if (dimensions == null) return;
    final w = dimensions.width;
    final h = dimensions.height;
    for (final entry in GenAiImageSize.presets.entries) {
      final sample = GenAiImageSize.tryParse(entry.value.values.first)!;
      if (sample.width * h == sample.height * w) {
        aspectRatio = entry.key;
        return;
      }
    }
    final divisor = w.gcd(h);
    aspectRatio = '${w ~/ divisor}:${h ~/ divisor}';
  }

  void _alignDimension(bool isWidth) {
    final ratio = aspectRatio.split(':').map(int.parse).toList();
    final amount = int.tryParse(isWidth ? width : height);
    final scale = isWidth ? ratio.last / ratio.first : ratio.first / ratio.last;
    final other = amount == null || amount <= 0
        ? ''
        : math.max(1, (amount * scale).round()).toString();
    if (isWidth) {
      height = other;
    } else {
      width = other;
    }
  }

  void selectAspectRatio(String value) {
    final options = GenAiImageSize.presets[value];
    if (options == null) return;
    aspectRatio = value;
    if (resolution != 'custom' && !options.containsKey(resolution)) resolution = options.keys.first;
    if (custom && (int.tryParse(width) ?? 0) > 0) _alignDimension(true);
  }

  void selectOrientation(String value) {
    if (value == 'square') {
      selectAspectRatio('1:1');
      return;
    }
    final opposite = aspectRatio.split(':').reversed.join(':');
    selectAspectRatio(
      GenAiImageSize.presets.containsKey(opposite) && orientationOf(opposite) == value
          ? opposite
          : value == 'landscape'
          ? '16:9'
          : '9:16',
    );
  }

  static String orientationOf(String ratio) {
    final sides = ratio.split(':').map(int.tryParse).toList();
    if (sides.length != 2 || sides[0] == null || sides[1] == null || sides[0] == sides[1]) {
      return 'square';
    }
    return sides[0]! > sides[1]! ? 'landscape' : 'portrait';
  }
}

final class GenAiImageStudioController extends ChangeNotifier {
  GenAiImageStudioController(this._repository);

  final GenAiRepository _repository;
  GenAiImageDraft draft = GenAiImageDraft();
  final _pending = <GenAiImageRecord>[];
  List<GenAiImageRecord> get pending => List.unmodifiable(_pending);
  GenAiFailure? failure;
  Object? _scope;
  GenAiCancellation? _operation;
  bool get generating => _operation != null;
  int completion = 0;

  void updateScope(Object scope) {
    if (_scope == scope) return;
    _scope = scope;
    _operation?.cancel(GenAiFailureKind.accountChanged);
    _operation = null;
    draft = GenAiImageDraft();
    _pending.clear();
    failure = null;
    notifyListeners();
  }

  Future<void> generate(GenAiImageRequest request) async {
    if (generating) return;
    final operation = GenAiCancellation();
    _operation = operation;
    failure = null;
    notifyListeners();
    try {
      final images = await _repository.generateImage(request, operation);
      operation.throwIfCancelled();
      _pending.insert(
        0,
        GenAiImageRecord(
          id: request.groupId,
          prompt: request.prompt,
          title: request.title,
          quality: request.quality,
          images: images,
        ),
      );
    } on GenAiFailure catch (error) {
      if (!operation.isCancelled) failure = error;
    } catch (_) {
      if (!operation.isCancelled) {
        failure = const GenAiFailure(GenAiFailureKind.transport);
      }
    } finally {
      if (identical(_operation, operation)) {
        _operation = null;
        completion++;
        notifyListeners();
      }
    }
  }

  /// The server may use a different record ID; match the returned image URLs.
  void reconcile(List<GenAiImageRecord> records) {
    final urls = records.expand((record) => record.images).toSet();
    _pending.removeWhere((record) => record.images.every(urls.contains));
  }

  @override
  void dispose() {
    _operation?.cancel();
    _operation = null;
    super.dispose();
  }
}
