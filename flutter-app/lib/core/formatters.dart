import 'package:flutter/material.dart';

/// 格式化数字，保留最多两位有效小数；整值不带小数点。
String number(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  if (parsed == null) return '--';
  if (parsed == parsed.roundToDouble()) return parsed.toInt().toString();
  return parsed
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// 固定保留 4 位小数（用于累计绩点）。
String fixed4(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  return parsed == null ? '--' : parsed.toStringAsFixed(4);
}

/// 空字符串回退文本。
String fallback(Object? value, String replacement) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? replacement : text;
}

/// 把天数格式化成人能读的时长文本。
String formatDays(double days) {
  if (days < 1) {
    final hours = days * 24;
    if (hours < 1) return '${(hours * 60).round()} 分钟';
    return '${hours.toStringAsFixed(1)} 小时';
  }
  if (days < 10) return '${days.toStringAsFixed(1)} 天';
  return '${days.round()} 天';
}

/// 把毫秒时间戳格式化为 `YYYY-MM-DD HH:mm`。
String formatTimestamp(int millis) {
  if (millis <= 0) return '';
  final at = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)} '
      '${two(at.hour)}:${two(at.minute)}';
}

/// 格式化短日期 `M/d`。
String formatShortDate(DateTime date) => '${date.month}/${date.day}';

/// 按电表名称选择图标。
IconData meterIcon(String label) {
  if (label.contains('空调')) return Icons.ac_unit_rounded;
  if (label.contains('照明') || label.contains('灯')) {
    return Icons.lightbulb_outline_rounded;
  }
  return Icons.electric_meter_outlined;
}

/// 计算学分加权平均绩点（与 Python 侧 `mobile_bridge.py` 口径一致）。
///
/// 同课程代码/名称存在多条成绩时保留最高绩点（同绩点取更高分数），再仅对
/// `gp != null && credits > 0` 的课程做学分加权。
({double? gpa, double credits}) computeWeightedGpaStats(Iterable<Map> grades) {
  final selected = <String, ({double gpRank, double scoreRank, Map grade})>{};
  final scoreRegex = RegExp(r'\d+(?:\.\d+)?');

  for (final grade in grades) {
    final code = (grade['code'] ?? '').toString().trim();
    final course = (grade['course'] ?? '').toString().trim();
    final key = code.isNotEmpty ? code : course;
    final gp = (grade['gp'] as num?)?.toDouble();
    final scoreMatch = scoreRegex.firstMatch((grade['score'] ?? '').toString());
    final score = scoreMatch != null
        ? (double.tryParse(scoreMatch.group(0)!) ?? -1.0)
        : -1.0;
    final gpRank = gp ?? -1.0;

    final current = selected[key];
    if (current == null ||
        gpRank > current.gpRank ||
        (gpRank == current.gpRank && score > current.scoreRank)) {
      selected[key] = (gpRank: gpRank, scoreRank: score, grade: grade);
    }
  }

  var totalCredits = 0.0;
  var weightedSum = 0.0;
  for (final item in selected.values) {
    final gp = (item.grade['gp'] as num?)?.toDouble();
    final credits = (item.grade['credits'] as num?)?.toDouble() ?? 0.0;
    if (gp != null && credits > 0) {
      totalCredits += credits;
      weightedSum += gp * credits;
    }
  }

  return (
    gpa: totalCredits > 0 ? weightedSum / totalCredits : null,
    credits: totalCredits,
  );
}

/// 计算学分加权平均绩点（便捷返回）。
double? computeWeightedGpa(Iterable<Map> grades) =>
    computeWeightedGpaStats(grades).gpa;
