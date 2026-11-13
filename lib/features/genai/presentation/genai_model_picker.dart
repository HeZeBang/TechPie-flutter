import 'package:flutter/material.dart';

import '../domain/genai_contract.dart';
import 'genai_icons.dart';
import 'genai_theme.dart';

/// Quiet text button in the composer; the menu explains cost and thinking
/// support per model instead of decorating the button itself.
class GenAiModelPicker extends StatefulWidget {
  const GenAiModelPicker({
    super.key,
    required this.models,
    required this.selected,
    required this.loading,
    required this.enabled,
    required this.onSelected,
    this.maxWidth = double.infinity,
    this.workspaceWidth,
  });

  final List<GenAiModel> models;
  final GenAiModel? selected;
  final bool loading;
  final bool enabled;
  final ValueChanged<GenAiModel> onSelected;
  final double maxWidth;

  /// The workspace's layout width, used to cap the model popover the way the
  /// draft caps it at `100% - 24`. Falls back to the window width.
  final double? workspaceWidth;

  static const _labelStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0);

  /// The button's natural width, so the composer reserves only what the model
  /// name needs and gives the rest to the mode toggles. The sum mirrors the
  /// draft's row: 6 px padding each side, a 7 px gap and a 13 px chevron. The
  /// toolbar, not this measurement, is responsible for constraining the width
  /// to the row it actually has.
  static double widthFor(BuildContext context, String label, {double max = double.infinity}) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble() + 6 + 6 + 7 + 13 + 1;
    painter.dispose();
    return width.clamp(44.0, max);
  }

  static String cost(GenAiModel model) => switch (model.payType) {
    'FREE' => '免费',
    'PAID' => '付费',
    _ => '费用未知',
  };

  @override
  State<GenAiModelPicker> createState() => _GenAiModelPickerState();
}

class _GenAiModelPickerState extends State<GenAiModelPicker> {
  Future<void> _openMenu(BuildContext context, BuildContext anchorContext) async {
    final palette = GenAiPalette.of(context);
    final compact = GenAiLayout.of(context).compactControls;
    // Draft popover width: 220 px minimum, never wider than the workspace
    // minus the 12 px side insets.
    final menuWidth = ((widget.workspaceWidth ?? MediaQuery.sizeOf(context).width) - 24).clamp(
      220.0,
      300.0,
    );
    final picked = await genAiShowMenu<GenAiModel>(
      context: context,
      anchorContext: anchorContext,
      minWidth: menuWidth,
      semanticLabel: '选择模型',
      items: [
        if (!compact)
          PopupMenuItem<GenAiModel>(
            enabled: false,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text('选择模型', style: TextStyle(fontSize: 11, color: palette.muted)),
          ),
        for (final model in widget.models)
          PopupMenuItem<GenAiModel>(
            key: ValueKey('genai-model-${model.aiType}'),
            value: model,
            enabled: widget.enabled,
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 4 : 8),
            child: compact
                ? _compactRow(model, palette)
                : Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                model.name,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                [
                                  GenAiModelPicker.cost(model),
                                  if (model.supportsThinking) '支持深度思考',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: palette.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (model == widget.selected)
                        GenAiIcon(GenAiGlyph.check, size: 17, color: palette.accent)
                      else
                        const SizedBox(width: 17),
                    ],
                  ),
          ),
      ],
    );
    // The menu is a route: the picker may have been rebuilt, disabled or moved
    // to another account while it was open, so only deliver a still-valid pick.
    if (picked == null || !mounted || !widget.enabled || !widget.models.contains(picked)) return;
    widget.onSelected(picked);
  }

  Widget _compactRow(GenAiModel model, GenAiPalette palette) => Row(
    children: [
      Expanded(
        child: Text(model.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ),
      const SizedBox(width: 8),
      Text(GenAiModelPicker.cost(model), style: TextStyle(fontSize: 11, color: palette.muted)),
      const SizedBox(width: 8),
      SizedBox(
        width: 15,
        child: model.supportsThinking
            ? Semantics(
                label: '支持深度思考',
                child: GenAiIcon(GenAiGlyph.brain, size: 15, color: palette.muted),
              )
            : null,
      ),
      const SizedBox(width: 8),
      if (model == widget.selected)
        GenAiIcon(GenAiGlyph.check, size: 17, color: palette.accent)
      else
        const SizedBox(width: 17),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final palette = GenAiPalette.of(context);
    final label = widget.selected?.name ?? (widget.loading ? '正在加载模型…' : '选择模型');
    // The TextButton supplies the button role and tap action; this only
    // prefixes its visible model name with what the control does.
    return Semantics(
      container: true,
      label: '选择模型',
      child: Builder(
        builder: (anchorContext) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth, minHeight: 44),
          child: TextButton(
            key: const ValueKey('genai-model'),
            onPressed: widget.enabled && widget.models.isNotEmpty
                ? () => _openMenu(context, anchorContext)
                : null,
            style: TextButton.styleFrom(
              foregroundColor: palette.text,
              textStyle: GenAiModelPicker._labelStyle,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(44, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GenAiModelPicker._labelStyle,
                  ),
                ),
                const SizedBox(width: 7),
                GenAiIcon(GenAiGlyph.down, size: 13, color: palette.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
