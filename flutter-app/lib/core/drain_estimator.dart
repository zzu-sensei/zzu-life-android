import 'formatters.dart';

/// 电量耗电速度的估算结果，字段含义与 Python 侧
/// `zzupy.energy_history.DrainEstimate` 保持一致。
class DrainEstimate {
  const DrainEstimate({
    required this.label,
    required this.meterId,
    required this.latest,
    required this.ratePerDay,
    required this.daysLeft,
    required this.samples,
    required this.windowHours,
    this.note = '',
  });

  final String label;
  final String meterId;
  final double latest;
  final double ratePerDay;
  final double? daysLeft;
  final int samples;
  final double windowHours;
  final String note;
}

/// 采样时间跨度下限（小时）。少于这个跨度不足以拟合。
const double drainMinWindowHours = 6;

/// 回看窗口（天）。
const int drainWindowDays = 7;

/// 拟合出的速度小于该值（度/天）时视为几乎不耗电。
const double drainNegligibleRate = 0.01;

/// 按电表分组估算耗电速度。
///
/// 算法与 Python 侧一致：以最早采样为原点做最小二乘拟合，斜率的相反数即日均
/// 耗电量；窗口内不足两点、跨度不足 6 小时、电量为上升趋势（刚充值）或几乎
/// 不耗电时都不给出天数估计，而是在 [DrainEstimate.note] 里说明原因。
List<DrainEstimate> estimateDrain(
  List<Map> samples, {
  int nowMillis = 0,
  int windowDays = drainWindowDays,
}) {
  final now = nowMillis == 0
      ? DateTime.now().millisecondsSinceEpoch
      : nowMillis;
  final cutoff = now - windowDays * 86400 * 1000;

  // 按电表归集窗口内的采样。
  final grouped = <String, List<Map>>{};
  for (final raw in samples) {
    final t = (raw['t'] as num?)?.toDouble();
    final q = (raw['q'] as num?)?.toDouble();
    if (t == null || q == null) continue;
    if (t < cutoff) continue;
    final id = (raw['id'] ?? '').toString();
    grouped.putIfAbsent(id, () => []).add({'t': t, 'q': q, 'label': raw['label']});
  }

  final results = <DrainEstimate>[];
  grouped.forEach((meterId, items) {
    items.sort((a, b) => (a['t'] as double).compareTo(b['t'] as double));
    final label = (items.last['label'] ?? '寝室电表').toString();
    final latest = items.last['q'] as double;

    if (items.length < 2) {
      results.add(
        DrainEstimate(
          label: label,
          meterId: meterId,
          latest: latest,
          ratePerDay: 0,
          daysLeft: null,
          samples: items.length,
          windowHours: 0,
          note: '只有一个采样点，多查几次即可估算',
        ),
      );
      return;
    }

    final origin = items.first['t'] as double;
    final windowHours =
        ((items.last['t'] as double) - origin) / 1000 / 3600;
    if (windowHours < drainMinWindowHours) {
      results.add(
        DrainEstimate(
          label: label,
          meterId: meterId,
          latest: latest,
          ratePerDay: 0,
          daysLeft: null,
          samples: items.length,
          windowHours: windowHours,
          note: '时间跨度不足 ${number(drainMinWindowHours)} 小时，继续采样中',
        ),
      );
      return;
    }

    final xs = items
        .map((item) => ((item['t'] as double) - origin) / 1000 / 86400)
        .toList();
    final ys = items.map((item) => item['q'] as double).toList();
    final count = xs.length;
    final meanX = xs.reduce((a, b) => a + b) / count;
    final meanY = ys.reduce((a, b) => a + b) / count;
    var denominator = 0.0;
    var numerator = 0.0;
    for (var i = 0; i < count; i++) {
      denominator += (xs[i] - meanX) * (xs[i] - meanX);
      numerator += (xs[i] - meanX) * (ys[i] - meanY);
    }
    if (denominator <= 0) {
      results.add(
        DrainEstimate(
          label: label,
          meterId: meterId,
          latest: latest,
          ratePerDay: 0,
          daysLeft: null,
          samples: count,
          windowHours: windowHours,
          note: '采样时间重合，无法拟合',
        ),
      );
      return;
    }

    final rate = -(numerator / denominator);
    if (rate.abs() < drainNegligibleRate) {
      results.add(
        DrainEstimate(
          label: label,
          meterId: meterId,
          latest: latest,
          ratePerDay: rate.abs(),
          daysLeft: null,
          samples: count,
          windowHours: windowHours,
          note: '几乎没有耗电',
        ),
      );
      return;
    }
    if (rate < 0) {
      results.add(
        DrainEstimate(
          label: label,
          meterId: meterId,
          latest: latest,
          ratePerDay: 0,
          daysLeft: null,
          samples: count,
          windowHours: windowHours,
          note: '期间电量没有下降（可能刚充值），暂不估算',
        ),
      );
      return;
    }

    results.add(
      DrainEstimate(
        label: label,
        meterId: meterId,
        latest: latest,
        ratePerDay: rate,
        daysLeft: latest > 0 ? latest / rate : 0,
        samples: count,
        windowHours: windowHours,
      ),
    );
  });

  results.sort((a, b) => a.label.compareTo(b.label));
  return results;
}

/// 把估算结果渲染成一行中文说明。
String formatDrainLine(DrainEstimate estimate) {
  if (estimate.daysLeft == null) {
    final detail = estimate.note.isEmpty ? '' : '（${estimate.note}）';
    return '${estimate.label}：${number(estimate.latest)} 度，暂无法估算耗电速度$detail';
  }
  return '${estimate.label}：${number(estimate.latest)} 度，'
      '日均 ${estimate.ratePerDay.toStringAsFixed(2)} 度，'
      '约还能用 ${formatDays(estimate.daysLeft!)}';
}
