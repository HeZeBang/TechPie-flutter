import 'package:flutter/foundation.dart';

import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
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
  String quality = 'low';
  final references = <GenAiReferenceImage>[];
  final previews = <GenAiReferenceImage, Uint8List>{};
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
