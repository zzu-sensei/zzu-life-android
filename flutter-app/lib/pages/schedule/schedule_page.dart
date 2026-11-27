import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/course_palette.dart';
import '../../core/formatters.dart';
import '../../core/native_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_components.dart';
import 'schedule_grid.dart';

/// 课表页面：支持周视图 / 日日程视图切换、教学周内存缓存、今日课程提醒与 ICS 导出。
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static const int _minWeek = 1;
  static const int _defaultMaxWeek = 30;

  int week = 0;
  int currentWeek = 0;
  int maxWeek = _defaultMaxWeek;
  bool loading = true;
  bool caching = false;
  bool hasOfflineCache = false;
  int cacheUpdatedAt = 0;
  String cacheSemesterName = '';
  int cacheTotalLessons = 0;
  bool showExperiments = true;
  bool exporting = false;
  bool isDayView = false;
  int selectedDay = DateTime.now().weekday;
  String? error;
  List<Map> lessons = const [];

  /// 已拉取过的教学周内存缓存，翻周时无需重复请求网络。
  final Map<int, List<Map>> _weekCache = {};

  @override
  void initState() {
    super.initState();
    _initSchedule();
  }

  Future<void> _initSchedule() async {
    try {
      final cached = await NativeApi.call('getCachedSchedule');
      if (!mounted) return;
      if (cached['cached'] == true && cached['data'] is Map) {
        final data = Map<String, dynamic>.from(cached['data'] as Map);
        setState(() {
          _applySemesterCache(data);
          loading = false;
        });
        return;
      }
    } catch (_) {}
    await load();
  }

  void _applySemesterCache(
    Map<String, dynamic> data, {
    bool keepSelectedWeek = false,
  }) {
    final resolvedMax = ((data['max_week'] as num?)?.toInt() ?? 20).clamp(
      _minWeek,
      _defaultMaxWeek,
    );
    final rawWeeks = (data['weeks'] as Map?) ?? const {};
    _weekCache.clear();
    for (var w = _minWeek; w <= resolvedMax; w++) {
      final list = rawWeeks['$w'];
      _weekCache[w] = list is List
          ? list.whereType<Map>().toList()
          : const <Map>[];
    }

    var computedCurrent = (data['current_week'] as num?)?.toInt() ?? 1;
    final startStr = (data['start_date'] ?? '').toString().trim();
    if (startStr.length >= 10) {
      final parsedStart = DateTime.tryParse(startStr.substring(0, 10));
      if (parsedStart != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final startDay = DateTime(
          parsedStart.year,
          parsedStart.month,
          parsedStart.day,
        );
        computedCurrent = today.difference(startDay).inDays ~/ 7 + 1;
      }
    }
    computedCurrent = computedCurrent.clamp(_minWeek, resolvedMax);
    final targetWeek = (keepSelectedWeek && week >= _minWeek)
        ? week.clamp(_minWeek, resolvedMax)
        : computedCurrent;

    maxWeek = resolvedMax;
    currentWeek = computedCurrent;
    week = targetWeek;
    lessons = _weekCache[targetWeek] ?? const [];
    hasOfflineCache = true;
    cacheUpdatedAt = (data['cached_at'] as num?)?.toInt() ?? 0;
    cacheSemesterName = (data['semester_name'] ?? '').toString();
    cacheTotalLessons = (data['total_lessons'] as num?)?.toInt() ?? 0;
    error = null;
  }

  Future<void> _cacheSemesterSchedule() async {
    if (caching) return;
    HapticFeedback.lightImpact();
    setState(() => caching = true);
    try {
      final result = await NativeApi.call('cacheSemesterSchedule');
      if (!mounted) return;
      setState(() {
        _applySemesterCache(result, keepSelectedWeek: week > 0);
        loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '整学期课表已离线缓存（共 $maxWeek 周 · $cacheTotalLessons 节），桌面小组件已同步',
          ),
        ),
      );
    } catch (caught) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('缓存失败：$caught')),
        );
      }
    }
    if (mounted) setState(() => caching = false);
  }

  Future<void> _openCacheSheet() async {
    await showMiuixSheet<void>(
      context,
      builder: (sheetContext) {
        final palette = sheetContext.palette;
        final cachedTimeText = formatTimestamp(cacheUpdatedAt);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MiuixSheetHeader(
              title: '离线课表缓存',
              subtitle: cacheSemesterName.isNotEmpty
                  ? '$cacheSemesterName · 已缓存整学期'
                  : '已缓存整学期课表，翻周与小组件免联网',
            ),
            const SizedBox(height: 14),
            MiuixCard(
              color: palette.cardSubtle,
              showShadow: false,
              radius: 16,
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  ConfirmRow('教学周范围', '第 1 – $maxWeek 周'),
                  ConfirmRow('课表条数', '共 $cacheTotalLessons 节次'),
                  if (cachedTimeText.isNotEmpty)
                    ConfirmRow('缓存时间', cachedTimeText),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '开启后应用内翻周和「今日课表 / 整周课表」小组件都会优先读取本地缓存；如需拉取最新调课，点击右上角刷新或下方更新缓存即可。',
              style: TextStyle(
                color: palette.inkSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.danger,
                      side: BorderSide(
                        color: palette.danger.withValues(alpha: 0.35),
                      ),
                    ),
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      try {
                        await NativeApi.call('clearCachedSchedule');
                      } catch (_) {}
                      if (!mounted) return;
                      setState(() {
                        hasOfflineCache = false;
                        cacheUpdatedAt = 0;
                        cacheSemesterName = '';
                        cacheTotalLessons = 0;
                        maxWeek = _defaultMaxWeek;
                        _weekCache.clear();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已清除整学期离线缓存')),
                      );
                      await load(week > 0 ? week : null, true);
                    },
                    child: const Text('清除缓存'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _cacheSemesterSchedule();
                    },
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('更新整学期缓存'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> load([int? target, bool force = false]) async {
    final normalizedTarget = target?.clamp(_minWeek, maxWeek);
    if (normalizedTarget != null &&
        !force &&
        _weekCache.containsKey(normalizedTarget)) {
      HapticFeedback.selectionClick();
      setState(() {
        week = normalizedTarget;
        lessons = _weekCache[normalizedTarget]!;
        error = null;
        loading = false;
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
      if (normalizedTarget != null) week = normalizedTarget;
    });

    try {
      final result = await NativeApi.call('getSchedule', {
        'week': normalizedTarget ?? week,
        'semester_id': 0,
      });
      if (!mounted) return;
      final fetchedWeek = ((result['week'] as num?)?.toInt() ?? 1).clamp(
        _minWeek,
        maxWeek,
      );
      final fetchedLessons = ((result['lessons'] as List?) ?? const [])
          .cast<Map>();
      _weekCache[fetchedWeek] = fetchedLessons;
      setState(() {
        week = fetchedWeek;
        if (currentWeek == 0) currentWeek = fetchedWeek;
        lessons = fetchedLessons;
      });
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> selectWeek() async {
    final selected = await showMiuixSheet<int>(
      context,
      builder: (sheetContext) {
        final palette = sheetContext.palette;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MiuixSheetHeader(
              title: '选择教学周',
              subtitle: currentWeek > 0 ? '当前为第 $currentWeek 周' : null,
              trailing: currentWeek > 0
                  ? TextButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, currentWeek),
                      icon: const Icon(Icons.today_rounded, size: 17),
                      label: const Text('回到本周'),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.45,
              ),
              itemCount: maxWeek,
              itemBuilder: (context, index) {
                final value = index + 1;
                final isSelected = value == week;
                final isCurrent = value == currentWeek;
                return Material(
                  color: isSelected
                      ? palette.primary
                      : isCurrent
                      ? palette.primarySoft
                      : palette.cardSubtle,
                  shape: miuixShape(
                    12,
                    side: BorderSide(
                      color: isCurrent && !isSelected
                          ? palette.primary.withValues(alpha: 0.45)
                          : Colors.transparent,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(sheetContext, value);
                    },
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$value',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : isCurrent
                                  ? palette.onPrimarySoft
                                  : palette.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          if (isCurrent)
                            Text(
                              '本周',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.9)
                                    : palette.primary,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
    if (selected != null && selected != week) await load(selected);
  }

  void showLesson(Map lesson) {
    final courseName = (lesson['course'] ?? '未知课程').toString();
    final place = fallback(lesson['place'], '地点未定');
    final teacher = fallback(lesson['teacher'], '教师未定');
    final code = fallback(lesson['code'], '');
    final timeRange =
        '${lesson['start_time'] ?? ''}–${lesson['end_time'] ?? ''} · '
        '第 ${lesson['start_unit'] ?? ''}–${lesson['end_unit'] ?? ''} 节';

    showMiuixSheet<void>(
      context,
      builder: (sheetContext) {
        final palette = sheetContext.palette;
        final accent = courseColor(courseName);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 5,
                  height: 28,
                  margin: const EdgeInsets.only(top: 2, right: 10),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Expanded(
                  child: Text(
                    courseName,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (lesson['is_experiment'] == true) ...[
                  const SizedBox(width: 8),
                  MiuixTag(
                    '实验课',
                    color: palette.info,
                    backgroundColor: palette.infoSoft,
                    icon: Icons.science_rounded,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            MiuixCard(
              color: palette.cardSubtle,
              showShadow: false,
              radius: 16,
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  InfoRow(Icons.schedule_rounded, timeRange),
                  const SizedBox(height: 12),
                  InfoRow(
                    Icons.location_on_outlined,
                    place,
                    trailing: place == '地点未定'
                        ? null
                        : IconButton(
                            tooltip: '复制上课地点',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: place),
                              );
                              if (sheetContext.mounted) {
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  const SnackBar(content: Text('上课地点已复制')),
                                );
                              }
                            },
                            icon: Icon(
                              Icons.copy_rounded,
                              size: 16,
                              color: palette.inkMuted,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  InfoRow(Icons.person_outline_rounded, teacher),
                  if (code.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    InfoRow(Icons.tag_rounded, code),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> exportAllSchedule() async {
    setState(() => exporting = true);
    try {
      final exported = await NativeApi.call('exportSchedule');
      final saved = await NativeApi.call('saveFile', {
        'filename': (exported['filename'] ?? '郑大课表.ics').toString(),
        'content': (exported['content'] ?? '').toString(),
      });
      if (mounted && saved['cancelled'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${saved['message'] ?? '完整课表已保存'} · ${exported['count'] ?? 0} 节课',
            ),
          ),
        );
      }
    } catch (caught) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(caught.toString())),
        );
      }
    }
    if (mounted) setState(() => exporting = false);
  }

  int? _parseMinutes(Object? raw) {
    final text = (raw ?? '').toString().trim();
    final parts = text.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  Widget _buildTodayBanner(List<Map> visibleLessons) {
    final palette = context.palette;
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final todayLessons = visibleLessons
        .where((item) => (item['weekday'] as num?)?.toInt() == now.weekday)
        .toList()
      ..sort(
        (a, b) => ((a['start_unit'] as num?)?.toInt() ?? 0).compareTo(
          (b['start_unit'] as num?)?.toInt() ?? 0,
        ),
      );

    if (todayLessons.isEmpty) {
      return MiuixCard(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(Icons.wb_sunny_outlined, size: 18, color: palette.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '今天没有排课，祝学习生活愉快',
                style: TextStyle(
                  color: palette.inkSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Map? ongoing;
    Map? nextLesson;
    var remainingCount = 0;

    for (final item in todayLessons) {
      final start = _parseMinutes(item['start_time']);
      final end = _parseMinutes(item['end_time']);
      if (start != null && end != null) {
        if (nowMinutes >= start && nowMinutes <= end) {
          ongoing ??= item;
        } else if (start > nowMinutes) {
          remainingCount++;
          nextLesson ??= item;
        }
      }
    }

    final target = ongoing ?? nextLesson;
    if (target == null) {
      return MiuixCard(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 18, color: palette.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '今日 ${todayLessons.length} 节课程已全部结束',
                style: TextStyle(
                  color: palette.inkSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isOngoing = ongoing != null;
    final tagText = isOngoing ? '正在上课' : '下一节';
    final tagColor = isOngoing ? palette.success : palette.primary;
    final tagBg = isOngoing ? palette.successSoft : palette.primarySoft;
    final courseName = (target['course'] ?? '未知课程').toString();
    final time = '${target['start_time'] ?? ''}-${target['end_time'] ?? ''}';
    final place = fallback(target['place'], '地点未定');

    return MiuixCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: () => showLesson(target),
      child: Row(
        children: [
          MiuixTag(tagText, color: tagColor, backgroundColor: tagBg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  courseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$time · $place',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.inkSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          if (!isOngoing && remainingCount > 1)
            Text(
              '余 $remainingCount 节',
              style: TextStyle(
                color: palette.inkMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 18, color: palette.inkMuted),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final visibleLessons = showExperiments
        ? lessons
        : lessons.where((lesson) => lesson['is_experiment'] != true).toList();
    final weekDates = deriveWeekDates(
      lessons,
      week: week,
      currentWeek: currentWeek,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: MiuixCard(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(
              children: [
                IconButton(
                  tooltip: '上一周',
                  onPressed: loading || week <= _minWeek
                      ? null
                      : () => load(week - 1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: loading ? null : selectWeek,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            week > 0 ? '第 $week 周' : '课表加载中',
                            style: TextStyle(
                              color: palette.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          if (week > 0 && week == currentWeek) ...[
                            const SizedBox(width: 6),
                            const MiuixTag('本周'),
                          ],
                          const SizedBox(width: 2),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: palette.inkMuted,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一周',
                  onPressed: loading || week >= maxWeek
                      ? null
                      : () => load(week + 1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                if (currentWeek > 0 && week != currentWeek)
                  IconButton(
                    tooltip: '回到本周',
                    onPressed: loading ? null : () => load(currentWeek),
                    icon: Icon(
                      Icons.today_rounded,
                      size: 20,
                      color: palette.primary,
                    ),
                  ),
                IconButton(
                  tooltip: '刷新课表',
                  onPressed: loading ? null : () => load(week, true),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: MiuixSegmentedControl<bool>(
                  height: 34,
                  value: isDayView,
                  items: const [
                    (value: false, label: '周表'),
                    (value: true, label: '日程'),
                  ],
                  onChanged: (value) => setState(() => isDayView = value),
                ),
              ),
              const SizedBox(width: 6),
              FilterChip(
                selected: showExperiments,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (value) => setState(() => showExperiments = value),
                avatar: Icon(
                  Icons.science_outlined,
                  size: 15,
                  color: showExperiments
                      ? palette.onPrimarySoft
                      : palette.inkSecondary,
                ),
                label: const Text('含实验', style: TextStyle(fontSize: 12.5)),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: hasOfflineCache
                      ? palette.success
                      : palette.primary,
                ),
                onPressed: caching
                    ? null
                    : (hasOfflineCache
                          ? _openCacheSheet
                          : _cacheSemesterSchedule),
                icon: caching
                    ? const Loader(size: 14)
                    : Icon(
                        hasOfflineCache
                            ? Icons.offline_pin_rounded
                            : Icons.cloud_download_outlined,
                        size: 16,
                      ),
                label: Text(
                  hasOfflineCache ? '已缓存' : '缓存课表',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '导出 ICS 日历',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                onPressed: loading || exporting ? null : exportAllSchedule,
                icon: exporting
                    ? const Loader(size: 15)
                    : const Icon(Icons.download_rounded, size: 18),
              ),
            ],
          ),
        ),
        if (!loading && error == null && week > 0 && week == currentWeek)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _buildTodayBanner(visibleLessons),
          ),
        Expanded(
          child: loading
              ? const Center(child: Loader())
              : error != null
              ? ErrorState(message: error!, retry: () => load(week, true))
              : isDayView
              ? _DayAgendaView(
                  lessons: visibleLessons,
                  weekDates: weekDates,
                  isCurrentWeek: week == currentWeek,
                  selectedDay: selectedDay,
                  onDayChanged: (day) => setState(() => selectedDay = day),
                  onLessonTap: showLesson,
                  onRefresh: () => load(week, true),
                )
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity.abs() < 260) return;
                    if (velocity < 0 && week < maxWeek) {
                      load(week + 1);
                    } else if (velocity > 0 && week > _minWeek) {
                      load(week - 1);
                    }
                  },
                  child: RefreshIndicator(
                    onRefresh: () => load(week, true),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                      children: [
                        if (visibleLessons.isNotEmpty)
                          SizedBox(
                            height: 700,
                            child: ScheduleGrid(
                              lessons: visibleLessons,
                              isCurrentWeek: week == currentWeek,
                              weekDates: weekDates,
                              onLessonTap: showLesson,
                            ),
                          )
                        else
                          const EmptyState(
                            Icons.free_breakfast_outlined,
                            '本周暂无符合条件的课程',
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// 日日程视图：7 日横条 + 当日课程详情列表。
class _DayAgendaView extends StatelessWidget {
  const _DayAgendaView({
    required this.lessons,
    required this.weekDates,
    required this.isCurrentWeek,
    required this.selectedDay,
    required this.onDayChanged,
    required this.onLessonTap,
    required this.onRefresh,
  });

  final List<Map> lessons;
  final Map<int, DateTime> weekDates;
  final bool isCurrentWeek;
  final int selectedDay;
  final ValueChanged<int> onDayChanged;
  final ValueChanged<Map> onLessonTap;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final brightness = Theme.of(context).brightness;
    final today = DateTime.now();
    const names = ['一', '二', '三', '四', '五', '六', '日'];

    final dayLessons = lessons
        .where((item) => (item['weekday'] as num?)?.toInt() == selectedDay)
        .toList()
      ..sort(
        (a, b) => ((a['start_unit'] as num?)?.toInt() ?? 0).compareTo(
          (b['start_unit'] as num?)?.toInt() ?? 0,
        ),
      );

    final stylesByCourse = assignCourseStyles(
      dayLessons.map((lesson) => (lesson['course'] ?? '未知课程').toString()),
      brightness,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: MiuixCard(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              children: [
                for (var day = 1; day <= 7; day++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onDayChanged(day);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: ShapeDecoration(
                          color: day == selectedDay
                              ? palette.primary
                              : Colors.transparent,
                          shape: miuixShape(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              names[day - 1],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: day == selectedDay
                                    ? Colors.white
                                    : (isCurrentWeek &&
                                              weekDates[day] != null &&
                                              DateUtils.isSameDay(
                                                weekDates[day],
                                                today,
                                              ))
                                    ? palette.primary
                                    : palette.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              weekDates[day] == null
                                  ? '--'
                                  : '${weekDates[day]!.day}',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: day == selectedDay
                                    ? Colors.white.withValues(alpha: 0.9)
                                    : palette.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: dayLessons.isEmpty
                ? ListView(
                    children: const [
                      EmptyState(
                        Icons.event_available_outlined,
                        '这一天没有安排课程',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
                    itemCount: dayLessons.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final lesson = dayLessons[index];
                      final courseName = (lesson['course'] ?? '未知课程')
                          .toString();
                      final style = stylesByCourse[courseName]!;
                      return MiuixCard(
                        radius: 18,
                        padding: const EdgeInsets.all(14),
                        onTap: () => onLessonTap(lesson),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 48,
                              decoration: BoxDecoration(
                                color: style.accent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          courseName,
                                          style: TextStyle(
                                            color: palette.ink,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (lesson['is_experiment'] == true)
                                        MiuixTag(
                                          '实验',
                                          color: palette.info,
                                          backgroundColor: palette.infoSoft,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${lesson['start_time'] ?? ''}–${lesson['end_time'] ?? ''} · '
                                    '第 ${lesson['start_unit'] ?? ''}–${lesson['end_unit'] ?? ''} 节',
                                    style: TextStyle(
                                      color: palette.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${fallback(lesson['place'], '地点未定')} · '
                                    '${fallback(lesson['teacher'], '教师未定')}',
                                    style: TextStyle(
                                      color: palette.inkSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: palette.inkMuted,
                              size: 20,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
