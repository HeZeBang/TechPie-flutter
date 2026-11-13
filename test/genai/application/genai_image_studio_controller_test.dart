import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';

import '../support/workspace_server.dart';

void main() {
  for (final titled in [true, false]) {
    test('pending image preserves optional metadata, titled=$titled', () async {
      final demo = await TestGenAiWorkspace.create();
      addTearDown(demo.dispose);
      await demo.workspace.reloadModels();
      final studio = demo.workspace.imageStudio;
      final model = demo.workspace.imageModels.single;
      final request = titled
          ? GenAiImageRequest(
              prompt: 'A red square',
              title: '  Red square  ',
              model: model,
              groupId: 'image-job',
              quality: 'high',
            )
          : GenAiImageRequest(prompt: 'A red square', model: model, groupId: 'image-job');
      await studio.generate(request);
      final pending = studio.pending.single;
      expect(pending.prompt, 'A red square');
      expect(pending.title, titled ? 'Red square' : isNull);
      expect(pending.quality, titled ? 'high' : 'low');
    });
  }
}
