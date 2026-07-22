import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_elements/flutter_ai_elements.dart';
import 'package:url_launcher/url_launcher.dart';

import 'code_highlighter.dart';
import 'demo_data.dart';
import 'demo_provider.dart';
import 'demo_tools.dart';
import 'feature_sections.dart';

/// A self-contained showcase of the `flutter_ai_elements` widget family, ported
/// from the flutter_ai demo.
///
/// Everything here is scripted ([DemoChatProvider]) and offline — no live
/// model, no network, no voice. It is surfaced from the home "应用" card as a
/// native feature entry (see `lib/models/feature.dart`).
class AiDemoPage extends StatefulWidget {
  /// Creates the AI demo page.
  const AiDemoPage({super.key});

  @override
  State<AiDemoPage> createState() => _AiDemoPageState();
}

class _AiDemoPageState extends State<AiDemoPage> {
  String _modelId = demoModels.first.id;
  final UseChatController _controller = UseChatController(
    provider: const DemoChatProvider(),
  );
  late final ToolRunner _toolRunner = ToolRunner(_controller);

  @override
  void initState() {
    super.initState();
    _controller.setTools(demoTools);
    _toolRunner.addListener(_onToolChange);
  }

  void _onToolChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _toolRunner.removeListener(_onToolChange);
    _toolRunner.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _selectModel(String id) {
    setState(() => _modelId = id);
    _controller.setOptions(AiRequestOptions(model: id));
  }

  void _openGallery() => unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: const Text('Every element'),
                scrolledUnderElevation: 0,
              ),
              body: const SafeArea(child: GalleryScreen()),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 900;
    final heroHeight = (media.size.height * 0.66).clamp(420.0, 620.0);

    // Inject the flutter_ai theme extension into techpie's inherited ThemeData
    // for this subtree only, picking light/dark to match the current brightness.
    final inherited = Theme.of(context);
    final aiExtension = inherited.brightness == Brightness.dark
        ? AiThemeExtension.dark()
        : AiThemeExtension.fallback();

    return Theme(
      data: inherited.copyWith(
        extensions: [...inherited.extensions.values, aiExtension],
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('AI 演示'), scrolledUnderElevation: 0),
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Centered(
                  child: _HeroHeader(
                    modelId: _modelId,
                    onSelectModel: _selectModel,
                    onNewChat: _controller.clear,
                    onOpenGallery: _openGallery,
                  ),
                ),
              ),
              // Hero: the live, scripted chat.
              SliverToBoxAdapter(
                child: SizedBox(
                  height: heroHeight,
                  child: ChatScreen(
                    controller: _controller,
                    toolRunner: _toolRunner,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _Centered(
                  child: FeatureSections(
                    isWide: isWide,
                    onOpenGallery: _openGallery,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centers its child at the package's reading width on wide screens.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxWidth = AiThemeExtension.of(context).maxContentWidth;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// The tight hero header: brand wordmark + value prop + badges.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.modelId,
    required this.onSelectModel,
    required this.onNewChat,
    required this.onOpenGallery,
  });

  final String modelId;
  final ValueChanged<String> onSelectModel;
  final VoidCallback onNewChat;
  final VoidCallback onOpenGallery;

  @override
  Widget build(BuildContext context) {
    final theme = AiThemeExtension.of(context);
    final subdued =
        DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.62);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _BrandGlyph(size: 30),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'flutter_ai',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_square),
                tooltip: 'New chat',
                onPressed: onNewChat,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A scripted AI chat toolkit showcase — streaming, tools, '
            'generative UI, citations.',
            style: TextStyle(fontSize: 16, height: 1.4, color: subdued),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AiModelSelector(
                models: demoModels,
                selectedId: modelId,
                onSelected: onSelectModel,
              ),
              const _Badge(label: '9 packages'),
              const _Badge(label: 'pub.dev'),
              const _Badge(label: 'zero lock-in'),
              _GalleryButton(theme: theme, onTap: onOpenGallery),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A small outlined badge chip used in the hero header.
class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = AiThemeExtension.of(context);
    final color = DefaultTextStyle.of(context).style.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: color?.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// A pill button that opens the full element gallery.
class _GalleryButton extends StatelessWidget {
  const _GalleryButton({required this.theme, required this.onTap});

  final AiThemeExtension theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.accentColor,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.grid_view_rounded,
                  size: 14, color: theme.onAccentColor),
              const SizedBox(width: 6),
              Text(
                'Every element',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.onAccentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A live chat backed by a [UseChatController].
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.controller,
    required this.toolRunner,
  });

  final UseChatController controller;
  final ToolRunner toolRunner;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  UseChatController get controller => widget.controller;
  ToolRunner get toolRunner => widget.toolRunner;

  Object? _dismissedError;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final messages = controller.messages.length;
            if (controller.status != ChatStatus.error) {
              _dismissedError = null;
            }
            final showError = controller.status == ChatStatus.error &&
                controller.error != _dismissedError;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    if (messages > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                        child: AiContextMeter(
                          usedTokens: 1200 + messages * 850,
                          totalTokens: 128000,
                        ),
                      ),
                    if (showError)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: AiErrorBanner(
                          message: '${controller.error}',
                          onRetry: () => unawaited(controller.regenerate()),
                          onDismiss: () => setState(
                            () => _dismissedError = controller.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        Expanded(
          child: AiChat(
            controller: controller,
            messageBuilder: _buildMessage,
            emptyState: _emptyState(),
            loadingBuilder: (_) =>
                const SizedBox(width: 220, child: AiShimmer()),
            maxContentWidth: 760,
          ),
        ),
        SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: AiPromptInput(
                controller: controller,
                onPickAttachment: _pickAttachment,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<List<FilePart>> _pickAttachment() async => [
        FilePart(
          mediaType: 'image/png',
          bytes: sampleImageBytes,
          name: 'photo.png',
        ),
      ];

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 1)),
      );

  Future<void> _editPrecedingUserMessage(
    BuildContext context,
    AiMessage assistant,
  ) async {
    final msgs = controller.messages;
    final i = msgs.indexWhere((m) => m.id == assistant.id);
    final userIndex = i == -1
        ? -1
        : msgs.sublist(0, i).lastIndexWhere((m) => m.role == AiRole.user);
    if (userIndex == -1) return;
    final user = msgs[userIndex];
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => _EditMessageDialog(initialText: user.text),
    );
    if (edited != null && edited.trim().isNotEmpty) {
      await controller.editMessage(user.id, edited.trim());
    }
  }

  AiWidgetRegistry get _genUi => AiWidgetRegistry()
    ..register(
      'chain_of_thought',
      (context, data) =>
          AiChainOfThought(initiallyExpanded: true, steps: _steps(data)),
    )
    ..register(
      'task',
      (context, data) => AiTask(
        title: data['title'] as String? ?? 'Task',
        items: _taskItems(data),
      ),
    )
    ..register(
      'confirmation',
      (context, data) => AiConfirmation(
        title: data['title'] as String? ?? 'Confirm?',
        description: data['description'] as String?,
        onConfirm: () => _snack(context, 'Done.'),
        onDeny: () => _snack(context, 'Cancelled.'),
      ),
    );

  Widget _buildMessage(BuildContext context, AiMessage message) {
    if (message.role == AiRole.user) return AiMessageBubble(message: message);
    if (message.role == AiRole.tool) return const SizedBox.shrink();

    final results = <String, ToolResultPart>{
      for (final m in controller.messages)
        for (final p in m.parts)
          if (p is ToolResultPart) p.toolCallId: p,
    };
    final sources = message.parts.whereType<SourcePart>().toList();
    final toolCalls = message.parts.whereType<ToolCallPart>().toList();
    final subdued =
        DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.6);
    var toolsRendered = false;

    final children = <Widget>[];
    void add(Widget w) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 12));
      children.add(w);
    }

    add(Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AiAvatar(role: AiRole.assistant, size: 24),
        const SizedBox(width: 8),
        Text('flutter_ai',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: subdued)),
      ],
    ));

    for (final part in message.parts) {
      switch (part) {
        case ReasoningPart(:final text):
          add(AiReasoning(text: text));
        case TextPart(:final text):
          add(AiResponse(text: text, codeHighlighter: demoCodeHighlighter));
        case ToolCallPart():
          if (!toolsRendered) {
            toolsRendered = true;
            add(
              toolCalls.length > 1
                  ? AiToolGroup(calls: toolCalls, results: results)
                  : AiToolInvocation(
                      call: part, result: results[part.toolCallId]),
            );
          }
        case ToolResultPart():
          break;
        case FilePart():
          if (part.mediaType.startsWith('image/')) {
            add(SizedBox(
              width: 260,
              child: AiImage(
                  url: part.url, bytes: part.bytes, aspectRatio: 16 / 9),
            ));
          } else {
            add(AiAttachment(file: part));
          }
        case SourcePart():
          break;
        case DataPart():
          add(AiDataView(part: part, registry: _genUi));
      }
    }

    for (final call in toolCalls) {
      final pending = toolRunner.pending[call.toolCallId];
      if (pending == null) continue;
      final info = toolRunner.confirmationFor(pending);
      add(AiConfirmation(
        title: info.title,
        description: info.description,
        onConfirm: () =>
            toolRunner.resolveConfirmation(call.toolCallId, approved: true),
        onDeny: () =>
            toolRunner.resolveConfirmation(call.toolCallId, approved: false),
      ));
    }

    if (sources.isNotEmpty) {
      add(AiSources(
        sources: sources,
        onTap: (source) => unawaited(
            launchUrl(source.url, mode: LaunchMode.externalApplication)),
      ));
    }

    if (message.status == AiMessageStatus.complete) {
      add(Row(
        children: [
          AiMessageActions(
            message: message,
            onGood: () => _snack(context, 'Thanks for the feedback!'),
            onBad: () => _snack(context, 'Thanks — we\'ll do better.'),
            onShare: () => _snack(context, 'Share sheet would open here.'),
            onRegenerate: () => unawaited(controller.regenerate()),
            onEdit: () =>
                unawaited(_editPrecedingUserMessage(context, message)),
          ),
          const Spacer(),
          if (message == controller.messages.last && controller.branchCount > 1)
            AiBranch(
              index: controller.branchIndex,
              total: controller.branchCount,
              onPrevious: () =>
                  controller.selectBranch(controller.branchIndex - 1),
              onNext: () => controller.selectBranch(controller.branchIndex + 1),
            ),
        ],
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  List<AiThoughtStep> _steps(Map<String, Object?> data) {
    final raw = (data['steps'] as List?) ?? const [];
    return raw.map((s) {
      final m = (s! as Map).cast<String, Object?>();
      return AiThoughtStep(
        label: m['label'] as String? ?? '',
        detail: m['detail'] as String?,
        isActive: m['active'] as bool? ?? false,
      );
    }).toList();
  }

  List<AiTaskItem> _taskItems(Map<String, Object?> data) {
    final raw = (data['items'] as List?) ?? const [];
    return raw.map((item) {
      final m = (item! as Map).cast<String, Object?>();
      return AiTaskItem(
        label: m['label'] as String? ?? '',
        status: switch (m['status']) {
          'complete' => AiTaskStatus.complete,
          'active' => AiTaskStatus.active,
          'error' => AiTaskStatus.error,
          _ => AiTaskStatus.pending,
        },
      );
    }).toList();
  }

  void _onSuggestion(String text) {
    if (text.startsWith('Summarize')) {
      unawaited(
        controller.sendText('Summarize this article', attachments: const [
          FilePart(mediaType: 'application/pdf', name: 'article.pdf'),
        ]),
      );
    } else {
      unawaited(controller.sendText(text));
    }
  }

  Widget _emptyState() => AiEmptyState(
        glyph: const _BrandGlyph(size: 56),
        title: 'Ask me anything',
        subtitle: 'A live, scripted demo — no API key required.',
        suggestions: const [
          'Plan a weekend in Lisbon',
          'Suggest a dinner recipe',
          'How do I center a widget?',
          'Summarize this article',
        ],
        onSuggestionTap: _onSuggestion,
      );
}

/// Edit-message dialog that owns its [TextEditingController].
class _EditMessageDialog extends StatefulWidget {
  const _EditMessageDialog({required this.initialText});

  final String initialText;

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _field =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit message'),
      content: TextField(controller: _field, autofocus: true, maxLines: null),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _field.text),
            child: const Text('Save')),
      ],
    );
  }
}

/// The `flutter_ai` brand glyph.
class _BrandGlyph extends StatelessWidget {
  const _BrandGlyph({this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = AiThemeExtension.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.orbColor,
            Color.lerp(theme.orbColor, theme.accentColor, 0.5)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: theme.orbColor.withValues(alpha: 0.35),
            blurRadius: size * 0.35,
            spreadRadius: size * 0.02,
          ),
        ],
      ),
      child: Icon(Icons.auto_awesome,
          size: size * 0.5, color: theme.onAccentColor),
    );
  }
}

/// A scrolling gallery of every element with sample data.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = galleryItems();
    final divider = AiThemeExtension.of(context).borderColor;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1, color: divider),
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9893A8),
                    letterSpacing: 0.2)),
            const SizedBox(height: 10),
            item.child,
          ],
        );
      },
    );
  }
}
