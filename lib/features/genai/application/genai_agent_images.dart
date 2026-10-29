import '../domain/genai_agent_contract.dart';
import '../domain/genai_agent_protocol.dart';

/// A per-run view over canonical conversation image URLs, not an image store.
/// The school endpoint reliably exposes one primary image. Explicit selection
/// lets the agent inspect older images without extra chats or hidden model calls.
final class GenAiAgentImages {
  GenAiAgentImages(Iterable<String> urls) {
    for (final url in urls) {
      _add(url);
    }
  }

  final _urls = <String>[];
  String? _current;
  String? get current => _current;
  String? get currentId => current == null ? null : 'image_${_urls.indexOf(current!) + 1}';

  void _add(String url) {
    if (!_urls.contains(url)) _urls.add(url);
    _current = url;
  }

  void addGenerated(Map<String, Object?>? result) {
    for (final url in genAiGeneratedImages(result)) {
      _add(url);
    }
  }

  Map<String, Object?> get manifest => {
        'images': [
          for (var i = 0; i < _urls.length; i++) {'id': 'image_${i + 1}', 'url': _urls[i]},
        ],
        'visible_image': currentId,
      };

  GenAiAgentTool inspectionTool({required bool imageAttached}) => GenAiAgentTool(
        name: 'inspect_image',
        description: 'Select an image_context ID to view on the next step. Only visible_image '
            'is attached for vision; other URLs are a catalog. New images become visible '
            'after generation. Compare actual observations, not generation prompts. '
            '${imageAttached ? 'Before switching, record your observation of visible_image (or that it is unreadable). These are assistant notes, not verified tool facts.' : 'No image is attached on this step; select one to inspect it next.'}',
        parameters: {
          'type': 'object',
          'properties': {
            'image_id': {'type': 'string', 'maxLength': 40},
            if (imageAttached) ...{
              'observed_image_id': {'type': 'string', 'maxLength': 40},
              'observation': {'type': 'string', 'minLength': 1, 'maxLength': 2400},
            },
          },
          'required': [
            'image_id',
            if (imageAttached) ...['observed_image_id', 'observation'],
          ],
          'additionalProperties': false,
        },
        prepare: (args, context) async => GenAiAgentPreparedTool(
          execute: () async {
            context.checkActive();
            final index = _urls
                .asMap()
                .entries
                .where(
                  (entry) => 'image_${entry.key + 1}' == args['image_id'],
                )
                .firstOrNull
                ?.key;
            if (index == null || imageAttached && args['observed_image_id'] != currentId) {
              throw const GenAiAgentToolException(
                'invalid_image_selection',
                'Use an image_id from image_context and, when an image is attached, label '
                    'the observation with visible_image. No image has been changed.',
              );
            }
            _current = _urls[index];
            return {
              'status': 'selected',
              'image_id': currentId,
              'url': current,
            };
          },
        ),
      );
}
