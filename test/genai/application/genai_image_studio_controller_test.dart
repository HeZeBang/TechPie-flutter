import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';

import '../support/workspace_server.dart';

void main() {
  test('pending image records retain request title and quality', () async {
    final demo = await TestGenAiWorkspace.create();
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    final studio = demo.workspace.imageStudio;
    final model = demo.workspace.imageModels.single;

    await studio.generate(
      GenAiImageRequest(
        prompt: 'A red square',
        title: '  Red square  ',
        model: model,
        groupId: 'titled-job',
        quality: 'high',
      ),
    );

    expect(studio.pending, hasLength(1));
    expect(studio.pending.single.title, 'Red square');
    expect(studio.pending.single.quality, 'high');
    expect(studio.pending.single.prompt, 'A red square');
  });

  test('pending image records stay empty-safe when no title is provided', () async {
    final demo = await TestGenAiWorkspace.create();
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    final studio = demo.workspace.imageStudio;

    await studio.generate(
      GenAiImageRequest(
        prompt: 'A blue circle',
        model: demo.workspace.imageModels.single,
        groupId: 'untitled-job',
      ),
    );

    expect(studio.pending.single.title, isNull);
    expect(studio.pending.single.quality, 'low');
  });
}
