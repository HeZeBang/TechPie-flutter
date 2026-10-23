import 'package:flutter/material.dart';

import '../domain/genai_platform_contract.dart';

class GenAiWebSearchView extends StatefulWidget {
  const GenAiWebSearchView({
    super.key,
    required this.citations,
    this.isSearching = false,
    required this.onOpenLink,
    this.query,
  });

  final List<GenAiWebSearchCitation> citations;
  final bool isSearching;
  final String? query;
  final void Function(String url) onOpenLink;

  @override
  State<GenAiWebSearchView> createState() => _GenAiWebSearchViewState();
}

class _GenAiWebSearchViewState extends State<GenAiWebSearchView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.citations.isEmpty &&
        !widget.isSearching &&
        widget.query == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final accent = theme.brightness == Brightness.dark
        ? const Color(0xff67d4c2)
        : const Color(0xff167c6d);
    final muted = theme.colorScheme.onSurfaceVariant;
    final border = theme.colorScheme.outlineVariant.withValues(alpha: .4);

    if (widget.isSearching && widget.citations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: accent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '正在检索网页信息…',
              style: TextStyle(
                fontSize: 12,
                color: muted,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    Icon(
                      Icons.travel_explore_outlined,
                      size: 15,
                      color: accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.query == null
                            ? '已检索 ${widget.citations.length} 条网络参考来源'
                            : '搜索：${widget.query} · ${widget.citations.length} 条来源',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Column(
                  children: [
                    for (final citation in widget.citations)
                      InkWell(
                        onTap: () => widget.onOpenLink(citation.link),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 5,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                margin: const EdgeInsets.only(top: 2, right: 6),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${citation.num}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: accent,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      citation.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: accent,
                                      ),
                                    ),
                                    if (citation.snippet.isNotEmpty)
                                      Text(
                                        citation.snippet,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: muted,
                                          height: 1.4,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.open_in_new,
                                size: 12,
                                color: muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
