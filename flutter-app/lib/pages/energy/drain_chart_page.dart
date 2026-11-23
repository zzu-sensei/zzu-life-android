import 'package:flutter/material.dart';

import '../../core/drain_estimator.dart';
import '../../core/formatters.dart';
import '../../core/native_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_components.dart';

/// 耗电速度可视化页面：展示采样折线、最小二乘拟合趋势线与采样清理功能。
class DrainChartPage extends StatefulWidget {
  const DrainChartPage({super.key, this.initialSamples = const []});

  final List<Map> initialSamples;

  @override
  State<DrainChartPage> createState() => _DrainChartPageState();
}

class _DrainChartPageState extends State<DrainChartPage> {
  late List<Map> samples = widget.initialSamples;
  bool loading = false;
  String? error;

  /// 时间窗口（天）。0 表示全部。
  int windowDays = drainWindowDays;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await NativeApi.call('getEnergySamples');
      if (!mounted) return;
      setState(() {
        samples = ((result['samples'] as List?) ?? const [])
            .whereType<Map>()
            .toList();
      });
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _confirmClearSamples() async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空采样历史？'),
        content: const Text('清空后将删除本地保存的电量采样点，并重新累计以估算耗电速度。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await NativeApi.call('clearEnergySamples');
      if (!mounted) return;
      setState(() => samples = const []);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空电量采样历史')),
      );
    } catch (caught) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(caught.toString())),
        );
      }
    }
  }

  /// 按电表把窗口内的采样分组并排序。
  Map<String, List<Map>> groupedSamples() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = windowDays == 0 ? 0 : now - windowDays * 86400 * 1000;
    final grouped = <String, List<Map>>{};
    for (final raw in samples) {
      final t = (raw['t'] as num?)?.toDouble();
      final q = (raw['q'] as num?)?.toDouble();
      if (t == null || q == null) continue;
      if (t < cutoff) continue;
      final id = (raw['id'] ?? '').toString();
      grouped.putIfAbsent(id, () => []).add(raw);
    }
    for (final items in grouped.values) {
      items.sort((a, b) => (a['t'] as num).compareTo(b['t'] as num));
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final grouped = groupedSamples();
    // 估算始终用固定窗口，保证与电量页上的数字一致。
    final estimates = {
      for (final e in estimateDrain(samples)) e.meterId: e,
    };

    return Scaffold(
      backgroundColor: palette.canvas,
      // 不要设 extendBodyBehindAppBar：那会让 AppBar 浮在内容之上并遮挡顶部选择器。
      appBar: AppBar(
        title: const Text('耗电速度'),
        actions: [
          if (samples.isNotEmpty)
            IconButton(
              onPressed: loading ? null : _confirmClearSamples,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: '清空采样历史',
            ),
          IconButton(
            onPressed: loading ? null : refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '重新读取采样',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: loading && samples.isEmpty
            ? const Center(child: Loader())
            : error != null && samples.isEmpty
            ? ErrorState(message: error!, retry: refresh)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  MiuixSegmentedControl<int>(
                    value: windowDays,
                    items: const [
                      (value: 1, label: '1 天'),
                      (value: 3, label: '3 天'),
                      (value: 7, label: '7 天'),
                      (value: 30, label: '30 天'),
                      (value: 0, label: '全部'),
                    ],
                    onChanged: (value) => setState(() => windowDays = value),
                  ),
                  const SizedBox(height: 14),
                  if (grouped.isEmpty)
                    const MiuixCard(
                      radius: 20,
                      child: EmptyState(
                        Icons.show_chart_rounded,
                        '还没有采样数据。\n多查几次电量（或开启后台巡检）即可看到耗电曲线。',
                      ),
                    )
                  else
                    for (final entry in grouped.entries) ...[
                      _meterCard(
                        entry.key,
                        entry.value,
                        estimates[entry.key],
                      ),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 4),
                  Text(
                    '趋势线由 7 天窗口内的采样做最小二乘拟合得到，斜率即日均耗电量。'
                    '采样点越多、时间跨度越长，估算越准。',
                    style: TextStyle(
                      color: palette.inkMuted,
                      fontSize: 11.5,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _meterCard(String meterId, List<Map> items, DrainEstimate? estimate) {
    final palette = context.palette;
    final latest = (items.last['q'] as num).toDouble();
    final label = (items.last['label'] ?? '寝室电表').toString();

    return MiuixCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${items.length} 个采样点',
                      style: TextStyle(
                        color: palette.inkSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${number(latest)} 度',
                style: TextStyle(
                  color: palette.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 180,
            child: items.length < 2
                ? Center(
                    child: Text(
                      '至少需要两个采样点才能画曲线',
                      style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
                    ),
                  )
                : CustomPaint(
                    painter: DrainChartPainter(
                      palette: palette,
                      points: [
                        for (final raw in items)
                          Offset(
                            (raw['t'] as num).toDouble(),
                            (raw['q'] as num).toDouble(),
                          ),
                      ],
                      fitLine: (estimate != null &&
                              estimate.ratePerDay.abs() >= drainNegligibleRate)
                          ? estimate
                          : null,
                    ),
                    size: Size.infinite,
                  ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: palette.divider),
          const SizedBox(height: 12),
          _estimateRow(estimate),
        ],
      ),
    );
  }

  Widget _estimateRow(DrainEstimate? estimate) {
    final palette = context.palette;
    if (estimate == null) {
      return Text(
        '暂无法估算',
        style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
      );
    }
    final rate = estimate.ratePerDay;
    final rateText = rate.abs() < drainNegligibleRate
        ? '几乎不耗电'
        : '${number(rate.abs())} 度/天';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _stat('日均耗电', rateText)),
            Expanded(
              child: _stat(
                '预计可用',
                estimate.daysLeft == null
                    ? '--'
                    : formatDays(estimate.daysLeft!),
              ),
            ),
          ],
        ),
        if (estimate.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            estimate.note,
            style: TextStyle(color: palette.inkSecondary, fontSize: 11.5),
          ),
        ],
      ],
    );
  }

  Widget _stat(String title, String value) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: palette.inkMuted, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: palette.ink,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

/// 画电量随时间变化的折线，并叠加拟合趋势线。
///
/// 时间轴用真实时间戳而不是序号，因此采样间隔不均匀时曲线形状仍然正确。
class DrainChartPainter extends CustomPainter {
  DrainChartPainter({
    required this.palette,
    required this.points,
    this.fitLine,
  });

  final AppPalette palette;

  /// (时间戳毫秒, 电量)，按时间升序。
  final List<Offset> points;

  /// 有估算且耗电不可忽略时画趋势线。
  final DrainEstimate? fitLine;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    const padLeft = 42.0;
    const padRight = 10.0;
    const padTop = 10.0;
    const padBottom = 22.0;
    final plotWidth = size.width - padLeft - padRight;
    final plotHeight = size.height - padTop - padBottom;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    final minT = points.first.dx;
    final maxT = points.last.dx;
    var minQ = points.first.dy;
    var maxQ = points.first.dy;
    for (final p in points) {
      if (p.dy < minQ) minQ = p.dy;
      if (p.dy > maxQ) maxQ = p.dy;
    }

    // 把趋势线端点纳入纵轴范围（最多向外扩展一倍数据跨度以免把曲线压扁），
    // 超出部分交由坐标区裁剪兜底。
    final fit = fitLine;
    double? trendQStart;
    double? trendQEnd;
    if (fit != null) {
      final perMs = fit.ratePerDay / (86400 * 1000);
      final start = fit.latest - perMs * (maxT - minT);
      final end = fit.latest;
      trendQStart = start;
      trendQEnd = end;
      final dataMin = minQ;
      final dataMax = maxQ;
      final dataSpan = dataMax - dataMin;
      final guard = dataSpan > 0 ? dataSpan : 1.0;
      for (final value in [start, end]) {
        if (value >= dataMin - guard && value <= dataMax + guard) {
          if (value < minQ) minQ = value;
          if (value > maxQ) maxQ = value;
        }
      }
    }

    // 电量几乎不变时给一个最小高度，否则曲线会贴在一条直线上看不出形状。
    var span = maxQ - minQ;
    if (span < 0.5) {
      final mid = (maxQ + minQ) / 2;
      minQ = mid - 0.25;
      maxQ = mid + 0.25;
    } else {
      minQ -= span * 0.08;
      maxQ += span * 0.08;
    }
    span = maxQ - minQ;
    final timeSpan = (maxT - minT) == 0 ? 1.0 : (maxT - minT);

    Offset toCanvas(double t, double q) => Offset(
      padLeft + (t - minT) / timeSpan * plotWidth,
      padTop + (1 - (q - minQ) / span) * plotHeight,
    );

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // 横向网格与左侧刻度
    final gridPaint = Paint()
      ..color = palette.divider
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final value = minQ + span * i / 3;
      final y = padTop + (1 - (value - minQ) / span) * plotHeight;
      canvas.drawLine(
        Offset(padLeft, y),
        Offset(size.width - padRight, y),
        gridPaint,
      );
      textPainter.text = TextSpan(
        text: value.toStringAsFixed(1),
        style: TextStyle(color: palette.inkMuted, fontSize: 9.5),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(padLeft - textPainter.width - 6, y - textPainter.height / 2),
      );
    }

    // 坐标区裁剪：填充、趋势线与实测曲线都只画在坐标区内。
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(padLeft, padTop, plotWidth, plotHeight));

    // 折线下方的渐变填充
    final linePath = Path();
    var first = true;
    for (final p in points) {
      final o = toCanvas(p.dx, p.dy);
      if (first) {
        linePath.moveTo(o.dx, o.dy);
        first = false;
      } else {
        linePath.lineTo(o.dx, o.dy);
      }
    }
    final fillPath = Path.from(linePath)
      ..lineTo(padLeft + plotWidth, padTop + plotHeight)
      ..lineTo(padLeft, padTop + plotHeight)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.primary.withValues(alpha: 0.24),
            palette.primary.withValues(alpha: 0.01),
          ],
        ).createShader(Rect.fromLTWH(padLeft, padTop, plotWidth, plotHeight)),
    );

    // 趋势线：q(t) = latest - rate * (tLast - t)
    if (fit != null && trendQStart != null && trendQEnd != null) {
      canvas.drawLine(
        toCanvas(minT, trendQStart),
        toCanvas(maxT, trendQEnd),
        Paint()
          ..color = palette.success.withValues(alpha: 0.9)
          ..strokeWidth = 2,
      );
    }

    // 实测折线
    canvas.drawPath(
      linePath,
      Paint()
        ..color = palette.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );

    // 采样点
    final dotFill = Paint()..color = palette.card;
    final dotStroke = Paint()
      ..color = palette.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final p in points) {
      final center = toCanvas(p.dx, p.dy);
      canvas.drawCircle(center, 3.0, dotFill);
      canvas.drawCircle(center, 3.0, dotStroke);
    }

    canvas.restore();

    // 时间轴首尾标签
    String stamp(double ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms.round());
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '${d.month}/${d.day} $hh:$mm';
    }

    textPainter.text = TextSpan(
      text: stamp(minT),
      style: TextStyle(color: palette.inkMuted, fontSize: 9.5),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(padLeft, size.height - textPainter.height),
    );
    textPainter.text = TextSpan(
      text: stamp(maxT),
      style: TextStyle(color: palette.inkMuted, fontSize: 9.5),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        size.width - padRight - textPainter.width,
        size.height - textPainter.height,
      ),
    );
  }

  @override
  bool shouldRepaint(DrainChartPainter old) =>
      old.points != points ||
      old.fitLine != fitLine ||
      old.palette != palette;
}
