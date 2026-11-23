import 'package:flutter/material.dart';

/// 课程卡片配色方案（同时适配浅色与深色模式，保证高对比度与可读性）。
class CourseColorStyle {
  const CourseColorStyle({
    required this.background,
    required this.border,
    required this.accent,
    required this.title,
    required this.subtitle,
  });

  final Color background;
  final Color border;
  final Color accent;
  final Color title;
  final Color subtitle;
}

/// HyperOS / Material 3 调色板种子。
const List<Color> coursePalette = [
  Color(0xFF3482FF), // HyperOS Blue
  Color(0xFF14A38B), // Teal
  Color(0xFFE5646B), // Coral
  Color(0xFFD98A1C), // Amber
  Color(0xFF5D6FE8), // Indigo
  Color(0xFF935EE2), // Violet
  Color(0xFF1AA35E), // Emerald
  Color(0xFFD95B96), // Rose
  Color(0xFFE06D3B), // Terracotta
  Color(0xFF0E94C4), // Cyan
  Color(0xFF6B9C32), // Olive
  Color(0xFFAF5A82), // Plum
  Color(0xFF4267D6), // Cobalt
  Color(0xFFB88322), // Ochre
  Color(0xFF288FA8), // Cerulean
  Color(0xFF7B61C9), // Iris
  Color(0xFF279976), // Jade
  Color(0xFFCC4F73), // Berry
  Color(0xFF608C4B), // Moss
  Color(0xFFBD584D), // Rust
];

/// FNV-1a 课程名哈希，保证同一门课跨周颜色稳定。
int courseHash(String course) {
  var value = 2166136261;
  for (final unit in course.codeUnits) {
    value = ((value ^ unit) * 16777619) & 0x7fffffff;
  }
  return value;
}

/// 根据课程名返回代表色。
Color courseColor(String course) =>
    coursePalette[courseHash(course) % coursePalette.length];

/// 根据种子色与当前亮度生成课程卡片的完整配色。
CourseColorStyle courseStyleForSeed(Color seed, Brightness brightness) {
  if (brightness == Brightness.dark) {
    final accent = HSLColor.fromColor(seed).withLightness(0.68).toColor();
    return CourseColorStyle(
      background: Color.alphaBlend(
        seed.withValues(alpha: 0.24),
        const Color(0xFF16181D),
      ),
      border: accent.withValues(alpha: 0.36),
      accent: accent,
      title: const Color(0xFFF3F6FA),
      subtitle: const Color(0xFFB9C4D4),
    );
  }
  final titleColor = HSLColor.fromColor(seed).withLightness(0.24).toColor();
  final subtitleColor = HSLColor.fromColor(seed).withLightness(0.36).toColor();
  return CourseColorStyle(
    background: Color.alphaBlend(
      seed.withValues(alpha: 0.14),
      const Color(0xFFFFFFFF),
    ),
    border: seed.withValues(alpha: 0.28),
    accent: seed,
    title: titleColor,
    subtitle: subtitleColor,
  );
}

/// 为当前周的所有课程分配互不冲突的配色（若课程数超过调色板长度则循环）。
Map<String, CourseColorStyle> assignCourseStyles(
  Iterable<String> courseNames,
  Brightness brightness,
) {
  final unique = courseNames.toSet().toList()..sort();
  final used = <int>{};
  final styles = <String, CourseColorStyle>{};
  for (final name in unique) {
    var index = courseHash(name) % coursePalette.length;
    while (used.contains(index) && used.length < coursePalette.length) {
      index = (index + 1) % coursePalette.length;
    }
    used.add(index);
    styles[name] = courseStyleForSeed(coursePalette[index], brightness);
  }
  return styles;
}
