import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'genai_copy_button.dart';

enum GenAiChartType {
  bar,
  line,
  pie,
}

class GenAiChartSeries {
  const GenAiChartSeries({
    required this.name,
    required this.values,
    this.color,
  });

  final String name;
  final List<double> values;
  final Color? color;
}

class GenAiChartSpec {
  const GenAiChartSpec({
    required this.type,
    this.title,
    required this.labels,
    required this.series,
  });

  final GenAiChartType type;
  final String? title;
  final List<String> labels;
  final List<GenAiChartSeries> series;

  static const List<Color> defaultPalette = [
    Color(0xFF3B82F6), // Blue
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFF8B5CF6), // Purple
    Color(0xFFF43F5E), // Rose
    Color(0xFF06B6D4), // Cyan
    Color(0xFFF97316), // Orange
    Color(0xFF6366F1), // Indigo
  ];

  static GenAiChartSpec? parse(String rawText, {String? defaultTypeHint}) {
    try {
      final decoded = jsonDecode(rawText);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return _fromMap(decoded, defaultTypeHint: defaultTypeHint);
    } catch (_) {
      return null;
    }
  }

  static GenAiChartSpec? _fromMap(
    Map<String, dynamic> map, {
    String? defaultTypeHint,
  }) {
    // 1. Detect type
    var typeStr =
        (map['type'] ?? defaultTypeHint ?? 'bar').toString().toLowerCase();
    if (typeStr.contains('line')) {
      typeStr = 'line';
    } else if (typeStr.contains('pie')) {
      typeStr = 'pie';
    } else {
      typeStr = 'bar';
    }

    final type = switch (typeStr) {
      'line' => GenAiChartType.line,
      'pie' => GenAiChartType.pie,
      _ => GenAiChartType.bar,
    };

    final title = map['title']?.toString();

    // 2. Extract labels
    List<String> labels = [];
    if (map['labels'] is List) {
      labels = (map['labels'] as List).map((e) => e.toString()).toList();
    } else if (map['x'] is List) {
      labels = (map['x'] as List).map((e) => e.toString()).toList();
    } else if (map['categories'] is List) {
      labels = (map['categories'] as List).map((e) => e.toString()).toList();
    }

    // 3. Extract series / datasets
    final series = <GenAiChartSeries>[];

    if (map['datasets'] is List) {
      final list = map['datasets'] as List;
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is Map) {
          final sName = item['label']?.toString() ??
              item['name']?.toString() ??
              '数据 ${i + 1}';
          final rawData = item['data'] ?? item['values'] ?? const <dynamic>[];
          final values = _toDoubleList(rawData);
          series.add(GenAiChartSeries(name: sName, values: values));
        }
      }
    } else if (map['series'] is List) {
      final list = map['series'] as List;
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is Map) {
          final sName = item['name']?.toString() ??
              item['label']?.toString() ??
              '数据 ${i + 1}';
          final rawData = item['data'] ?? item['values'] ?? const <dynamic>[];
          final values = _toDoubleList(rawData);
          series.add(GenAiChartSeries(name: sName, values: values));
        }
      }
    } else if (map['y'] != null) {
      final values = _toDoubleList(map['y']);
      series.add(GenAiChartSeries(name: title ?? '数值', values: values));
    } else if (map['values'] != null) {
      final values = _toDoubleList(map['values']);
      series.add(GenAiChartSeries(name: title ?? '数值', values: values));
    } else if (map['data'] is List) {
      final list = map['data'] as List;
      // Could be list of objects [{"name": "A", "value": 10}, ...] or list of numbers
      if (list.isNotEmpty && list.first is Map) {
        final parsedLabels = <String>[];
        final parsedValues = <double>[];
        for (final item in list) {
          if (item is Map) {
            parsedLabels.add(
              item['name']?.toString() ?? item['label']?.toString() ?? '',
            );
            final val = item['value'] ?? item['y'] ?? item['data'];
            parsedValues.add(_toDouble(val));
          }
        }
        if (labels.isEmpty) {
          labels = parsedLabels;
        }
        series.add(GenAiChartSeries(name: title ?? '数值', values: parsedValues));
      } else {
        final values = _toDoubleList(list);
        series.add(GenAiChartSeries(name: title ?? '数值', values: values));
      }
    }

    if (series.isEmpty || series.any((s) => s.values.isEmpty)) {
      return null;
    }
    // fl_chart computes padded bounds, ranges and pie totals during paint.
    // Finite inputs can still overflow these operations; show the source instead.
    final values = series.expand((s) => s.values);
    var min = 0.0;
    var max = 0.0;
    for (final value in values) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    final paddedMax = max == 0 ? 10.0 : max * 1.15;
    final span = paddedMax - min;
    if (!span.isFinite || span / 100 == 0) return null;
    if (type == GenAiChartType.pie) {
      final slices = series.first.values;
      final total = slices.fold<double>(0, (sum, value) => sum + value);
      if (slices.any((value) => value < 0) || !total.isFinite || total <= 0) {
        return null;
      }
    }

    // Ensure labels length matches longest series
    final maxLength = series.fold<int>(
      0,
      (max, s) => s.values.length > max ? s.values.length : max,
    );
    if (labels.length < maxLength) {
      final padded = List<String>.from(labels);
      for (var i = labels.length; i < maxLength; i++) {
        padded.add('${i + 1}');
      }
      labels = padded;
    }

    return GenAiChartSpec(
      type: type,
      title: title,
      labels: labels,
      series: series,
    );
  }

  static List<double> _toDoubleList(dynamic data) {
    if (data is! List) {
      return const [];
    }
    return data.map(_toDouble).toList();
  }

  static double _toDouble(dynamic val) {
    final value = val is num
        ? val.toDouble()
        : val is String
            ? double.tryParse(val)
            : null;
    // fl_chart's automatic interval rounding converts values to integers.
    // Keep padding/ranges within the exact-integer range on native and web;
    // enormous scientific values remain available in the source fallback.
    if (value == null || !value.isFinite || value.abs() > 1e15) {
      throw const FormatException('Chart value exceeds renderer bounds');
    }
    return value;
  }
}

class GenAiChartView extends StatefulWidget {
  const GenAiChartView({
    super.key,
    required this.code,
    this.typeHint,
  });

  final String code;
  final String? typeHint;

  @override
  State<GenAiChartView> createState() => _GenAiChartViewState();
}

class _GenAiChartViewState extends State<GenAiChartView> {
  bool _showCode = false;
  GenAiChartSpec? _spec;

  @override
  void initState() {
    super.initState();
    _parseSpec();
  }

  @override
  void didUpdateWidget(GenAiChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.typeHint != widget.typeHint) {
      _parseSpec();
    }
  }

  void _parseSpec() {
    _spec = GenAiChartSpec.parse(widget.code, defaultTypeHint: widget.typeHint);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: .08)
        : Colors.black.withValues(alpha: .06);
    final cardBg = isDark
        ? Colors.white.withValues(alpha: .03)
        : Colors.black.withValues(alpha: .02);

    final spec = _spec;

    if (spec == null) {
      // Invalid JSON: fallback to code card with error header
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(
              context,
              title: '图表数据',
              badge: '格式未识别',
              badgeColor: theme.colorScheme.error,
              showToggle: false,
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                widget.code,
                style: const TextStyle(
                  fontFamily: 'RobotoMono',
                  fontFamilyFallback: ['monospace', 'Menlo'],
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final typeLabel = switch (spec.type) {
      GenAiChartType.bar => '柱状图',
      GenAiChartType.line => '折线图',
      GenAiChartType.pie => '饼图',
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(
            context,
            title: spec.title ?? '数据图表',
            badge: typeLabel,
            badgeColor: theme.colorScheme.primary,
            showToggle: true,
          ),
          if (_showCode)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                widget.code,
                style: const TextStyle(
                  fontFamily: 'RobotoMono',
                  fontFamilyFallback: ['monospace', 'Menlo'],
                  fontSize: 12,
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: SizedBox(
                height: 240,
                child: switch (spec.type) {
                  GenAiChartType.bar => _buildBarChart(context, spec),
                  GenAiChartType.line => _buildLineChart(context, spec),
                  GenAiChartType.pie => _buildPieChart(context, spec),
                },
              ),
            ),
            _buildLegend(context, spec),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required String title,
    required String badge,
    required Color badgeColor,
    required bool showToggle,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: .06)
                : Colors.black.withValues(alpha: .04),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.insert_chart_outlined_rounded,
            size: 16,
            color: badgeColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showToggle)
            Tooltip(
              message: _showCode ? '切换到图表' : '查看数据代码',
              child: InkWell(
                onTap: () => setState(() => _showCode = !_showCode),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    _showCode ? Icons.bar_chart_rounded : Icons.code_rounded,
                    size: 16,
                    color: theme.hintColor,
                  ),
                ),
              ),
            ),
          GenAiCopyButton(
            text: widget.code,
            tooltip: '复制数据',
            showLabel: false,
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(BuildContext context, GenAiChartSpec spec) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gridColor = isDark
        ? Colors.white.withValues(alpha: .06)
        : Colors.black.withValues(alpha: .05);

    final numGroups = spec.labels.length;
    final numSeries = spec.series.length;

    var maxY = 0.0;
    for (final s in spec.series) {
      for (final v in s.values) {
        if (v > maxY) {
          maxY = v;
        }
      }
    }
    if (maxY == 0) {
      maxY = 10;
    } else {
      maxY = maxY * 1.15;
    }

    final barGroups = <BarChartGroupData>[];
    for (var i = 0; i < numGroups; i++) {
      final rods = <BarChartRodData>[];
      for (var sIdx = 0; sIdx < numSeries; sIdx++) {
        final s = spec.series[sIdx];
        final val = i < s.values.length ? s.values[i] : 0.0;
        final color = s.color ??
            GenAiChartSpec
                .defaultPalette[sIdx % GenAiChartSpec.defaultPalette.length];
        rods.add(
          BarChartRodData(
            toY: val,
            color: color,
            width: numSeries > 1 ? 10 : 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        );
      }
      barGroups.add(BarChartGroupData(x: i, barRods: rods));
    }

    return BarChart(
      BarChartData(
        maxY: maxY,
        barGroups: barGroups,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (val) => FlLine(
            color: gridColor,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) => Text(
                _formatNumber(value),
                style: TextStyle(
                  fontSize: 10,
                  color: theme.hintColor,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < spec.labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      spec.labels[idx],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.hintColor,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLineChart(BuildContext context, GenAiChartSpec spec) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gridColor = isDark
        ? Colors.white.withValues(alpha: .06)
        : Colors.black.withValues(alpha: .05);

    var maxY = 0.0;
    var minY = double.infinity;
    for (final s in spec.series) {
      for (final v in s.values) {
        if (v > maxY) {
          maxY = v;
        }
        if (v < minY) {
          minY = v;
        }
      }
    }
    if (minY == double.infinity) {
      minY = 0;
    }
    if (minY > 0) {
      minY = 0;
    }
    if (maxY == 0) {
      maxY = 10;
    } else {
      maxY = maxY * 1.15;
    }

    final lineBars = <LineChartBarData>[];
    for (var sIdx = 0; sIdx < spec.series.length; sIdx++) {
      final s = spec.series[sIdx];
      final color = s.color ??
          GenAiChartSpec
              .defaultPalette[sIdx % GenAiChartSpec.defaultPalette.length];
      final spots = <FlSpot>[];
      for (var i = 0; i < s.values.length; i++) {
        spots.add(FlSpot(i.toDouble(), s.values[i]));
      }

      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          barWidth: 2.5,
          color: color,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: color.withValues(alpha: .12),
          ),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        lineBarsData: lineBars,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (val) => FlLine(
            color: gridColor,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) => Text(
                _formatNumber(value),
                style: TextStyle(
                  fontSize: 10,
                  color: theme.hintColor,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < spec.labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      spec.labels[idx],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.hintColor,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPieChart(BuildContext context, GenAiChartSpec spec) {
    final sections = <PieChartSectionData>[];
    final series = spec.series.firstOrNull;
    if (series != null) {
      final total = series.values.fold<double>(0, (sum, v) => sum + v);
      for (var i = 0; i < series.values.length; i++) {
        final val = series.values[i];
        final pct = total > 0 ? (val / total * 100).round() : 0;
        final color = GenAiChartSpec
            .defaultPalette[i % GenAiChartSpec.defaultPalette.length];
        sections.add(
          PieChartSectionData(
            value: val,
            title: '$pct%',
            color: color,
            radius: 46,
            titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      }
    }

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 36,
        sectionsSpace: 2,
      ),
    );
  }

  Widget _buildLegend(BuildContext context, GenAiChartSpec spec) {
    final theme = Theme.of(context);
    final items = <Widget>[];

    if (spec.type == GenAiChartType.pie) {
      final series = spec.series.firstOrNull;
      if (series != null) {
        for (var i = 0; i < series.values.length; i++) {
          final label = i < spec.labels.length ? spec.labels[i] : '项目 ${i + 1}';
          final color = GenAiChartSpec
              .defaultPalette[i % GenAiChartSpec.defaultPalette.length];
          items.add(_buildLegendItem(color, label, theme));
        }
      }
    } else {
      for (var i = 0; i < spec.series.length; i++) {
        final s = spec.series[i];
        final color = s.color ??
            GenAiChartSpec
                .defaultPalette[i % GenAiChartSpec.defaultPalette.length];
        items.add(_buildLegendItem(color, s.name, theme));
      }
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: items,
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: theme.textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }

  static String _formatNumber(double val) {
    if (val >= 1000000) {
      return '${(val / 1000000).toStringAsFixed(1)}M';
    }
    if (val >= 1000) {
      return '${(val / 1000).toStringAsFixed(1)}k';
    }
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }
}
