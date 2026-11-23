import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/course_palette.dart';
import '../../core/formatters.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_components.dart';

/// 从本周课程数据推断周一到周日的日期；若当周无课且已知当前周，则按周差推算。
Map<int, DateTime> deriveWeekDates(
  List<Map> lessons, {
  int week = 0,
  int currentWeek = 0,
}) {
  DateTime? monday;
  for (final lesson in lessons) {
    final weekday = (lesson['weekday'] as num?)?.toInt() ?? 0;
    final date = DateTime.tryParse((lesson['date'] ?? '').toString());
    if (date != null && weekday >= 1 && weekday <= 7) {
      monday = date.subtract(Duration(days: weekday - 1));
      break;
    }
  }
  if (monday == null && week > 0 && currentWeek > 0) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    monday = thisMonday.add(Duration(days: (week - currentWeek) * 7));
  }
  if (monday == null) return const {};
  return {
    for (var day = 1; day <= 7; day++) day: monday.add(Duration(days: day - 1)),
  };
}

/// 周课表二维网格视图（Miuix 连续圆角卡片 + 高可读课程块）。
class ScheduleGrid extends StatelessWidget {
  const ScheduleGrid({
    super.key,
    required this.lessons,
    required this.isCurrentWeek,
    required this.weekDates,
    required this.onLessonTap,
  });

  final List<Map> lessons;
  final bool isCurrentWeek;
  final Map<int, DateTime> weekDates;
  final ValueChanged<Map> onLessonTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final brightness = Theme.of(context).brightness;
    const headerHeight = 48.0;
    const unitWidth = 28.0;
    const names = ['一', '二', '三', '四', '五', '六', '日'];

    var maxUnit = 10;
    for (final lesson in lessons) {
      final end = (lesson['end_unit'] as num?)?.toInt() ?? 0;
      if (end > maxUnit) maxUnit = end;
    }

    final today = DateTime.now();
    final stylesByCourse = assignCourseStyles(
      lessons.map((lesson) => (lesson['course'] ?? '未知课程').toString()),
      brightness,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final dayWidth = (constraints.maxWidth - unitWidth) / 7;
        final scheduleWidth = dayWidth * 7;
        final totalHeight = constraints.maxHeight;
        final unitHeight = math.max(
          26.0,
          (totalHeight - headerHeight) / maxUnit,
        );

        return MiuixCard(
          radius: 22,
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: totalHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: unitWidth,
                  child: Column(
                    children: [
                      const SizedBox(height: headerHeight),
                      for (var unit = 1; unit <= maxUnit; unit++)
                        Container(
                          height: unitHeight,
                          alignment: Alignment.topCenter,
                          padding: const EdgeInsets.only(top: 7),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: palette.divider),
                            ),
                          ),
                          child: Text(
                            '$unit',
                            style: TextStyle(
                              color: palette.inkMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    width: scheduleWidth,
                    height: totalHeight,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            for (var day = 1; day <= 7; day++)
                              _DayColumn(
                                dayLabel: '周${names[day - 1]}',
                                date: weekDates[day],
                                isToday:
                                    isCurrentWeek &&
                                    weekDates[day] != null &&
                                    DateUtils.isSameDay(weekDates[day], today),
                                dayWidth: dayWidth,
                                totalHeight: totalHeight,
                                headerHeight: headerHeight,
                                unitHeight: unitHeight,
                                maxUnit: maxUnit,
                              ),
                          ],
                        ),
                        for (final lesson in lessons)
                          _CourseTile(
                            lesson: lesson,
                            dayWidth: dayWidth,
                            headerHeight: headerHeight,
                            unitHeight: unitHeight,
                            maxUnit: maxUnit,
                            style: stylesByCourse[(lesson['course'] ?? '未知课程')
                                .toString()]!,
                            onTap: () => onLessonTap(lesson),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.dayLabel,
    required this.date,
    required this.isToday,
    required this.dayWidth,
    required this.totalHeight,
    required this.headerHeight,
    required this.unitHeight,
    required this.maxUnit,
  });

  final String dayLabel;
  final DateTime? date;
  final bool isToday;
  final double dayWidth;
  final double totalHeight;
  final double headerHeight;
  final double unitHeight;
  final int maxUnit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = context.isDark;

    return Container(
      width: dayWidth,
      height: totalHeight,
      decoration: BoxDecoration(
        color: isToday
            ? palette.primary.withValues(alpha: isDark ? 0.09 : 0.045)
            : null,
        border: Border(
          left: BorderSide(color: palette.divider),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: headerHeight,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: isToday
                  ? BoxDecoration(
                      color: palette.primary,
                      borderRadius: BorderRadius.circular(10),
                    )
                  : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dayLabel,
                    style: TextStyle(
                      color: isToday ? Colors.white : palette.ink,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date == null ? '--' : formatShortDate(date!),
                    style: TextStyle(
                      color: isToday
                          ? Colors.white.withValues(alpha: 0.9)
                          : palette.inkMuted,
                      fontSize: 9.5,
                      fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (var unit = 1; unit <= maxUnit; unit++)
            Container(
              height: unitHeight,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: palette.divider),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.lesson,
    required this.dayWidth,
    required this.headerHeight,
    required this.unitHeight,
    required this.maxUnit,
    required this.style,
    required this.onTap,
  });

  final Map lesson;
  final double dayWidth;
  final double headerHeight;
  final double unitHeight;
  final int maxUnit;
  final CourseColorStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekday = ((lesson['weekday'] as num?)?.toInt() ?? 1).clamp(1, 7);
    final start = ((lesson['start_unit'] as num?)?.toInt() ?? 1).clamp(
      1,
      maxUnit,
    );
    final end = ((lesson['end_unit'] as num?)?.toInt() ?? start).clamp(
      start,
      maxUnit,
    );
    final course = (lesson['course'] ?? '未知课程').toString();
    final place = fallback(lesson['place'], '地点未定');

    return Positioned(
      left: (weekday - 1) * dayWidth + 2.5,
      top: headerHeight + (start - 1) * unitHeight + 2.5,
      width: dayWidth - 5,
      height: (end - start + 1) * unitHeight - 5,
      child: Material(
        color: style.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: style.border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: ColoredBox(color: style.accent),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course,
                        maxLines: constraints.maxHeight > 86 ? 4 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: style.title,
                          fontSize: 9.5,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        place,
                        maxLines: constraints.maxHeight > 86 ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: style.subtitle,
                          fontSize: 8.2,
                          height: 1.1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (lesson['is_experiment'] == true)
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: Icon(
                      Icons.science_rounded,
                      color: style.accent,
                      size: 10.5,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
