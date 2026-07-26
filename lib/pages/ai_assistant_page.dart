import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_client/flutter_ai_client.dart';
import 'package:flutter_ai_elements/flutter_ai_elements.dart';

import '../models/ai_chat.dart';
import '../services/ai_service.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/ai/ai_code_highlighter.dart';
import '../widgets/ai/ai_text_renderer.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';
import 'ai_config_page.dart';
import 'ai_gallery_page.dart';
import 'ai_history_page.dart';

/// The AI Assistant chat page — entered from the Home "应用" card.
///
/// Layout mirrors other TechPie feature pages: a platform-adaptive app bar
/// (Liquid Glass on iOS 26+, blurred bar elsewhere) over a body composed of
/// the flutter_ai library's chat widgets — [AiChat] for the transcript,
/// [AiPromptInput] for the composer, [AiErrorBanner] for failures. Only the
/// top bar, the not-configured banner, and the empty state are TechPie's own;
/// the conversation UI itself is the library's so that markdown, code blocks,
/// and future workflow/cite parts render through the library's part pipeline.
class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key, this.seedPrompt});

  /// Optional prompt pre-filled from the gallery. Written into the composer's
  /// text controller on first build.
  final String? seedPrompt;

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  /// Owns the composer's text so the gallery can pre-fill it. Passed to
  /// AiPromptInput.textController.
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.seedPrompt != null && widget.seedPrompt!.isNotEmpty) {
      _textController.text = widget.seedPrompt!;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _openGallery() async {
    final AiPromptTemplate? picked = await Navigator.of(context).push<
      AiPromptTemplate
    >(
      MaterialPageRoute<AiPromptTemplate>(
        builder: (_) => const AiGalleryPage(),
      ),
    );
    if (picked != null && mounted) {
      _textController.text = picked.prompt;
      _textController.selection = TextSelection.collapsed(
        offset: picked.prompt.length,
      );
    }
  }

  Future<void> _openHistory(AiService aiService) async {
    final String? selectedId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => AiHistoryPage(aiService: aiService),
      ),
    );
    if (selectedId != null && mounted) {
      aiService.selectConversation(selectedId);
    }
  }

  Future<void> _openConfig() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AiConfigPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final aiService = sp.aiService;
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset =
        useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: 'AI 助手',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: 'Home',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回 Home',
                  placementGroup: 'leading-main',
                ),
              ],
              trailingItems: const [
                IosNativeNavigationBarItem(
                  id: 'gallery',
                  title: 'Gallery',
                  sfSymbol: 'square.grid.2x2',
                  accessibilityLabel: '提示词画廊',
                  placementGroup: 'trailing-main',
                ),
                IosNativeNavigationBarItem(
                  id: 'history',
                  sfSymbol: 'clock.arrow.circlepath',
                  accessibilityLabel: '历史会话',
                  placementGroup: 'trailing-main',
                ),
                IosNativeNavigationBarItem(
                  id: 'config',
                  sfSymbol: 'gearshape',
                  accessibilityLabel: 'API 设置',
                  placementGroup: 'trailing-main',
                ),
              ],
              onItemPressed: (id) {
                switch (id) {
                  case 'back':
                    unawaited(Navigator.maybePop(context));
                  case 'gallery':
                    unawaited(_openGallery());
                  case 'history':
                    unawaited(_openHistory(aiService));
                  case 'config':
                    unawaited(_openConfig());
                }
              },
            )
          : BlurredAppBar(
              title: const Text('AI 助手'),
              actions: [
                IconButton(
                  tooltip: '提示词画廊',
                  icon: const Icon(Icons.auto_awesome_outlined),
                  onPressed: _openGallery,
                ),
                IconButton(
                  tooltip: '历史会话',
                  icon: const Icon(Icons.history),
                  onPressed: () => unawaited(_openHistory(aiService)),
                ),
                IconButton(
                  tooltip: 'API 设置',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _openConfig,
                ),
              ],
            ),
      // The transcript (AiChat) and composer (AiPromptInput) bind the
      // controller DIRECTLY and are NOT wrapped in a ListenableBuilder —
      // matching the flutter_ai demo. Wrapping them in ListenableBuilder(aiService)
      // rebuilds AiChat on every status change, which races AiChat's top-anchor
      // scroll logic (its anchor RenderBox goes missing mid-rebuild → trailingSpace
      // oscillates → the bottom padding flickers). Only the mutable banners listen
      // to aiService; AiChat listens to the controller itself.
      body: Column(
        children: [
          SizedBox(height: topInset),
          ListenableBuilder(
            listenable: aiService,
            builder: (context, _) {
              final notConfigured = !aiService.isConfigured;
              if (!notConfigured) return const SizedBox.shrink();
              return _configBanner(context, aiService);
            },
          ),
          Expanded(
            child: _AutoScrollChat(
              controller: aiService.controller,
              emptyState: Builder(
                builder: (context) =>
                    _emptyState(context, !aiService.isConfigured),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: aiService,
            builder: (context, _) {
              final error = aiService.streamingError;
              if (error == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: AiErrorBanner(
                  message: error,
                  onRetry:
                      aiService.isStreaming ? null : () => _retry(aiService),
                  onDismiss: () => _dismissError(aiService),
                ),
              );
            },
          ),
          // Composer appears only once configured; before that a button guides
          // the user to set a token. This toggle is the only composer-level
          // piece that needs aiService.
          ListenableBuilder(
            listenable: aiService,
            builder: (context, _) {
              if (!aiService.isConfigured) {
                return SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.tonalIcon(
                      onPressed: _openConfig,
                      icon: const Icon(Icons.key),
                      label: const Text('前往配置 API 令牌'),
                    ),
                  ),
                );
              }
              return AiPromptInput(
                controller: aiService.controller,
                hintText: '输入消息…',
                textController: _textController,
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _retry(AiService aiService) async {
    // Re-send an empty turn to regenerate the last assistant reply.
    await aiService.send('');
  }

  void _dismissError(AiService aiService) {
    // Clearing the transcript's error requires a fresh controller state; the
    // simplest portable way is to reload the current conversation, which
    // resets status to idle and drops the error.
    final conv = aiService.currentConversation;
    if (conv != null) {
      aiService.controller.stop();
    }
  }

  Widget _configBanner(BuildContext context, AiService aiService) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: InkWell(
        onTap: _openConfig,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.key,
                size: 18,
                color: theme.colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '尚未配置 API 令牌，点此填写以开始对话',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context, bool notConfigured) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              notConfigured ? '欢迎使用 AI 助手' : '开始一段新对话',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              notConfigured
                  ? '先配置 API 令牌，然后即可开始对话。也可以从画廊挑选一个提示词模板。'
                  : '在下方输入你的问题，或从画廊挑一个提示词模板快速开始。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: _openGallery,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('浏览提示词画廊'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A transcript bound to a [UseChatController] that scrolls to the bottom when a
/// message is sent — WITHOUT the library [AiChat]'s ChatGPT-style top-anchor.
///
/// Why not just use `AiChat(autoScroll: false)`: AiChat's ScrollController is
/// private, so we can't drive scroll-to-end from outside. This wrapper uses the
/// presentational [AiConversationView] with our own ScrollController, so we
/// control scrolling directly. Crucially it never sets `trailingSpace`, so
/// there is no dynamic bottom-padding (the source of the earlier flicker).
///
/// Scroll behavior:
/// - On a new message (count grows), animate to the bottom.
/// - While streaming, keep pinned to the bottom ONLY if the user is already
///   near the bottom — so scrolling up to read isn't yanked back down.
class _AutoScrollChat extends StatefulWidget {
  const _AutoScrollChat({required this.controller, this.emptyState});

  final UseChatController controller;
  final Widget? emptyState;

  @override
  State<_AutoScrollChat> createState() => _AutoScrollChatState();
}

class _AutoScrollChatState extends State<_AutoScrollChat> {
  final ScrollController _scrollController = ScrollController();
  int _lastCount = 0;
  /// First message id of the currently-shown thread. When it changes, the user
  /// switched conversations (the controller is a singleton that `load()`s a new
  /// transcript) — we jump to the bottom of the new thread.
  String? _firstMessageId;
  bool _nearBottom = true;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.controller.messages.length;
    _firstMessageId = widget.controller.messages.firstOrNull?.id;
    widget.controller.addListener(_onChanged);
    _scrollController.addListener(_onScroll);
    // On first open (or when re-entering a conversation), jump to the latest
    // message so the user lands at the bottom of the transcript.
    _jumpToEnd();
  }

  @override
  void didUpdateWidget(covariant _AutoScrollChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _lastCount = widget.controller.messages.length;
      _firstMessageId = widget.controller.messages.firstOrNull?.id;
      // Switched controllers — land at the bottom of the new thread.
      _jumpToEnd();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final near = (pos.maxScrollExtent - pos.pixels) <= 80;
    if (near != _nearBottom) {
      setState(() => _nearBottom = near);
    }
  }

  void _onChanged() {
    final messages = widget.controller.messages;
    final count = messages.length;
    final firstId = messages.firstOrNull?.id;
    // The controller is a singleton; a conversation switch swaps the transcript
    // in place via load(). Detect it by the first message id changing.
    final switched = firstId != _firstMessageId;
    _firstMessageId = firstId;
    final grew = count > _lastCount;
    _lastCount = count;
    if (!mounted) return;
    if (switched) {
      // New conversation — jump (no animation) to its latest message.
      _jumpToEnd();
      return;
    }
    // Scroll to end when a new message lands (user sent / assistant turn
    // started), or while streaming if the user is still pinned near the bottom.
    final streaming = widget.controller.status == ChatStatus.streaming;
    if (grew || (streaming && _nearBottom)) {
      _scrollToEnd();
    }
  }

  /// Animated scroll to the bottom — used while streaming / on send.
  void _scrollToEnd() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      unawaited(
        _scrollController.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  /// Instant jump to the bottom — used on init / conversation switch so the
  /// user lands at the latest message without a scroll animation.
  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// Builds a message bubble, pairing tool calls with their results across the
  /// whole transcript (the agent loop appends results as a separate
  /// AiRole.tool message, so per-message pairing would miss them).
  Widget _buildMessage(BuildContext context, AiMessage message) {
    // Tool-result messages are folded into the assistant turn's tool cards.
    if (message.role == AiRole.tool) return const SizedBox.shrink();
    // User messages render with the default bubble.
    if (message.role == AiRole.user) {
      return AiMessageBubble(message: message);
    }

    // Assistant: gather tool results across the whole transcript so each
    // ToolCallPart pairs with its result regardless of which message it's in.
    final results = <String, ToolResultPart>{
      for (final m in widget.controller.messages)
        for (final p in m.parts)
          if (p is ToolResultPart) p.toolCallId: p,
    };
    final toolCalls = message.parts.whereType<ToolCallPart>().toList();

    final children = <Widget>[];
    void add(Widget w) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(w);
    }

    var toolsRendered = false;
    for (final part in message.parts) {
      switch (part) {
        case TextPart(:final text):
          if (text.isNotEmpty) {
            add(AiResponse(text: text, codeHighlighter: techpieCodeHighlighter));
          }
        case ToolCallPart():
          // Render all tool calls once (a group when parallel, else one card),
          // each paired with its transcript-wide result.
          if (!toolsRendered) {
            toolsRendered = true;
            add(
              toolCalls.length > 1
                  ? AiToolGroup(calls: toolCalls, results: results)
                  : AiToolInvocation(
                      call: part,
                      result: results[part.toolCallId],
                    ),
            );
          }
        case ToolResultPart():
          break; // rendered within its AiToolInvocation card
        case ReasoningPart(:final text):
          if (text.isNotEmpty) add(AiReasoning(text: text));
        default:
          break; // FilePart/SourcePart/DataPart not used by TechPie tools yet
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final messages = widget.controller.messages;
        if (messages.isEmpty &&
            !widget.controller.status.isBusy &&
            widget.emptyState != null) {
          return widget.emptyState!;
        }
        final view = AiConversationView(
          messages: messages,
          scrollController: _scrollController,
          textRenderer: const StreamingMarkdownRenderer(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // Show the thinking loader while awaiting the first streamed token,
          // matching AiChat's behavior.
          showLoader: widget.controller.status == ChatStatus.submitted,
          // Custom builder pairs tool calls with their results across the whole
          // transcript (the agent loop lands ToolResultParts in a separate
          // AiRole.tool message; the default bubble only pairs within one
          // message). Tool-result messages are collapsed into the call card.
          messageBuilder: _buildMessage,
        );
        // Floating "scroll to end" button, shown only when not already at the
        // bottom (and there's content to scroll). Hidden once at the end.
        final showJump = !_nearBottom && messages.isNotEmpty;
        return Stack(
          children: [
            view,
            if (showJump)
              PositionedDirectional(
                bottom: 12,
                start: 0,
                end: 0,
                child: Center(child: _ScrollToEndButton(onTap: _scrollToEnd)),
              ),
          ],
        );
      },
    );
  }
}

/// A small circular "scroll to end" affordance. Styled to match the library's
/// jump button (AiChat._JumpButton) so it feels native to the chat surface.
class _ScrollToEndButton extends StatelessWidget {
  const _ScrollToEndButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '滚动到最新',
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 20,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}


