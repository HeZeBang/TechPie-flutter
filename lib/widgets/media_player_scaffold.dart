import 'package:flutter/material.dart';

class MediaPlayerScaffold extends StatelessWidget {
  const MediaPlayerScaffold({
    super.key,
    required this.title,
    required this.sourceLabels,
    required this.selectedSource,
    required this.sourceEnabled,
    required this.onSourceSelected,
    required this.player,
    required this.loading,
    this.subtitle,
    this.error,
    this.onRetry,
  });

  final String title;
  final String? subtitle;
  final List<String> sourceLabels;
  final int selectedSource;
  final bool sourceEnabled;
  final ValueChanged<int> onSourceSelected;
  final Widget? player;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  Widget _sourceSelector() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            for (var index = 0; index < sourceLabels.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              ChoiceChip(
                label: Text(sourceLabels[index]),
                selected: index == selectedSource,
                onSelected: !sourceEnabled || index == selectedSource
                    ? null
                    : (_) => onSourceSelected(index),
              ),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(title),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle == null)
                const SizedBox(height: 12)
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(subtitle!, style: Theme.of(context).textTheme.titleMedium),
                ),
              if (sourceLabels.length > 1) _sourceSelector(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: Colors.black, child: player ?? const SizedBox.expand()),
                      if (loading && error == null)
                        const ColoredBox(
                          color: Colors.black,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (error != null)
                        ColoredBox(
                          color: Theme.of(context).colorScheme.surface,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, size: 40),
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Text(error!, textAlign: TextAlign.center),
                                ),
                                if (onRetry != null) ...[
                                  const SizedBox(height: 16),
                                  FilledButton(onPressed: onRetry, child: const Text('重试')),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
