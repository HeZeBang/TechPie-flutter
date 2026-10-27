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
        'instruction': 'Only visible_image is attached for actual vision. Other URLs are a '
            'catalog, not visible pictures. Call inspect_image to view an earlier image. '
            'Before switching, record what you actually see in observation, or state that '
            'it is unreadable. Those notes are assistant observations, not verified tool '
            'facts. Compare them with the next image; never substitute old answers or '
            'generation prompts for visual inspection. New generated images become visible.',
      };

  GenAiAgentTool get inspectionTool => GenAiAgentTool(
        name: 'inspect_image',
        description: 'View an existing conversation image on the next model step. '
            'Use image_context IDs; cannot fetch arbitrary URLs or generate images. '
            'For comparison, first record a concise visual observation of visible_image '
            'in the call arguments, then select another image. After viewing it, compare '
            'against those labelled observations or switch again if detail is missing.',
        parameters: {
          'type': 'object',
          'properties': {
            'image_id': {'type': 'string', 'maxLength': 40},
            'observed_image_id': {'type': 'string', 'maxLength': 40},
            'observation': {'type': 'string', 'minLength': 1, 'maxLength': 2400},
          },
          'required': ['image_id', 'observed_image_id', 'observation'],
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
            if (index == null || args['observed_image_id'] != currentId) {
              throw const GenAiAgentToolException(
                'invalid_image_selection',
                'Use an image_id from image_context and label the observation with '
                    'the current visible_image. No image has been changed.',
              );
            }
            _current = _urls[index];
            return {
              'status': 'selected',
              'image_id': currentId,
              'url': current,
              'instruction': 'Inspect the attached image now. Selection itself is not '
                  'evidence of its contents. Earlier observation arguments are assistant notes.',
            };
          },
        ),
      );
}
