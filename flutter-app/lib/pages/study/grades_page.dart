import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/native_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_components.dart';

enum _GradeSortMode { semester, gpDesc, creditsDesc }

/// 学业成绩页面：累计加权绩点、按学期加权绩点、搜索排序、成绩单打印与后台监测设置。
class GradesPage extends StatefulWidget {
  const GradesPage({super.key});

  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  static const List<({int minutes, String label})> _intervalOptions = [
    (minutes: 15, label: '每 15 分钟'),
    (minutes: 30, label: '每 30 分钟'),
    (minutes: 60, label: '每 1 小时'),
    (minutes: 180, label: '每 3 小时'),
    (minutes: 360, label: '每 6 小时'),
    (minutes: 720, label: '每 12 小时'),
    (minutes: 1440, label: '每天'),
  ];

  Map<String, dynamic>? data;
  String? error;
  bool loading = true;
  bool printing = false;
  bool gradeMonitorEnabled = false;
  int gradeIntervalMinutes = 720;
  String lastGradeCheck = '';
  String lastGradeMessage = '尚未检查';
  String? semesterFilter;
  String searchQuery = '';
  _GradeSortMode sortMode = _GradeSortMode.semester;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
    loadMonitorSettings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadMonitorSettings() async {
    try {
      final settings = await NativeApi.call('getMonitorSettings');
      if (!mounted) return;
      setState(() {
        gradeMonitorEnabled = settings['grade_enabled'] == true;
        gradeIntervalMinutes =
            (settings['grade_interval_minutes'] as num?)?.toInt() ?? 720;
        lastGradeCheck = (settings['last_grade_check'] ?? '').toString();
        lastGradeMessage = (settings['last_grade_message'] ?? '尚未检查')
            .toString();
      });
    } catch (_) {}
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      data = await NativeApi.call('getGrades');
    } catch (caught) {
      error = caught.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> printGradeDocument(String method) async {
    setState(() => printing = true);
    try {
      final document = await NativeApi.call(method);
      final result = await NativeApi.call('printDocument', {
        'name': (document['name'] ?? '郑大成绩文档').toString(),
        'mime_type': (document['mime_type'] ?? '').toString(),
        'content_base64': (document['content_base64'] ?? '').toString(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((result['message'] ?? '已打开打印服务').toString()),
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
    if (mounted) setState(() => printing = false);
  }

  String _intervalLabel(int minutes) {
    for (final option in _intervalOptions) {
      if (option.minutes == minutes) return option.label;
    }
    return '每 $minutes 分钟';
  }

  void _openMonitorSheet() {
    var localEnabled = gradeMonitorEnabled;
    var localMinutes = gradeIntervalMinutes;
    var saving = false;
    String? sheetNotice;

    showMiuixSheet<void>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) {
          final palette = sheetContext.palette;

          Future<void> saveSettings({bool? enabled, int? minutes}) async {
            update(() {
              if (enabled != null) localEnabled = enabled;
              if (minutes != null) localMinutes = minutes;
              saving = true;
              sheetNotice = null;
            });
            try {
              await NativeApi.call('saveMonitorSettings', {
                'grade_enabled': localEnabled,
                'grade_interval_minutes': localMinutes,
              });
              if (mounted) {
                setState(() {
                  gradeMonitorEnabled = localEnabled;
                  gradeIntervalMinutes = localMinutes;
                });
              }
            } catch (caught) {
              sheetNotice = caught.toString();
            }
            if (sheetContext.mounted) update(() => saving = false);
          }

          Future<void> checkNow() async {
            update(() {
              saving = true;
              sheetNotice = null;
            });
            try {
              final result = await NativeApi.call('checkGradesNow');
              await loadMonitorSettings();
              sheetNotice = (result['message'] ?? '检查完成').toString();
            } catch (caught) {
              sheetNotice = caught.toString();
            }
            if (sheetContext.mounted) update(() => saving = false);
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MiuixSheetHeader(
                title: '成绩自动监测',
                subtitle: '定时在后台比对成绩变化，发现新成绩时发送本地通知',
              ),
              const SizedBox(height: 16),
              MiuixCard(
                color: palette.cardSubtle,
                showShadow: false,
                radius: 16,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '开启定时监测',
                            style: TextStyle(
                              color: palette.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lastGradeCheck.isEmpty
                                ? lastGradeMessage
                                : '$lastGradeMessage · $lastGradeCheck',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.inkSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: localEnabled,
                      onChanged: saving
                          ? null
                          : (value) => saveSettings(enabled: value),
                    ),
                  ],
                ),
              ),
              if (localEnabled) ...[
                const SizedBox(height: 16),
                Text(
                  '检查频率',
                  style: TextStyle(
                    color: palette.inkSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in _intervalOptions)
                      ChoiceChip(
                        label: Text(option.label),
                        selected: localMinutes == option.minutes,
                        onSelected: saving
                            ? null
                            : (_) => saveSettings(minutes: option.minutes),
                      ),
                  ],
                ),
              ],
              if (sheetNotice != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: ShapeDecoration(
                    color: palette.primarySoft,
                    shape: miuixShape(12),
                  ),
                  child: Text(
                    sheetNotice!,
                    style: TextStyle(
                      color: palette.onPrimarySoft,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: saving ? null : checkNow,
                  icon: saving
                      ? const Loader(size: 16, color: Colors.white)
                      : const Icon(Icons.manage_search_rounded, size: 19),
                  label: Text(saving ? '正在检查…' : '立即检查一次'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Map> _filterGrades(List<Map> grades) {
    final keyword = searchQuery.trim().toLowerCase();
    if (keyword.isEmpty) return grades;
    return grades.where((grade) {
      final course = (grade['course'] ?? '').toString().toLowerCase();
      final code = (grade['code'] ?? '').toString().toLowerCase();
      return course.contains(keyword) || code.contains(keyword);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final allGrades = ((data?['grades'] as List?) ?? const []).cast<Map>();
    final filteredGrades = _filterGrades(allGrades);

    final groups = <String, List<Map>>{};
    for (final grade in filteredGrades) {
      final semester = (grade['semester'] ?? '未标注学期').toString();
      groups.putIfAbsent(semester, () => []).add(grade);
    }
    final semesters = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    if (semesterFilter != null && !groups.containsKey(semesterFilter)) {
      semesterFilter = null;
    }
    final visibleSemesters = semesterFilter == null
        ? semesters
        : <String>[semesterFilter!];

    final sortedFlatGrades = List<Map>.from(filteredGrades);
    if (sortMode == _GradeSortMode.gpDesc) {
      sortedFlatGrades.sort(
        (a, b) => ((b['gp'] as num?)?.toDouble() ?? -1).compareTo(
          (a['gp'] as num?)?.toDouble() ?? -1,
        ),
      );
    } else if (sortMode == _GradeSortMode.creditsDesc) {
      sortedFlatGrades.sort(
        (a, b) => ((b['credits'] as num?)?.toDouble() ?? 0).compareTo(
          (a['credits'] as num?)?.toDouble() ?? 0,
        ),
      );
    }

    return Column(
      children: [
        MiuixPageHeader(
          title: '学业成绩',
          subtitle: '来自本科教务 · 支持搜索、按绩点排序与打印',
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
          action: IconButton.filledTonal(
            tooltip: '刷新成绩',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: Loader())
              : error != null
              ? ErrorState(message: error!, retry: load)
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      MiuixHeroBanner(
                        child: Row(
                          children: [
                            Expanded(
                              child: MiuixMetric(
                                label: '累计参考绩点',
                                value: data?['gpa'] == null
                                    ? '--'
                                    : fixed4(data!['gpa']),
                                valueColor: Colors.white,
                                labelColor: Colors.white.withValues(alpha: 0.85),
                                fontSize: 28,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 44,
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            Expanded(
                              child: MiuixMetric(
                                label: '计入学分',
                                value: number(data?['credits'] ?? 0),
                                valueColor: Colors.white,
                                labelColor: Colors.white.withValues(alpha: 0.85),
                                fontSize: 26,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 44,
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            Expanded(
                              child: MiuixMetric(
                                label: '课程数',
                                value: '${allGrades.length}',
                                valueColor: Colors.white,
                                labelColor: Colors.white.withValues(alpha: 0.85),
                                fontSize: 26,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: printing
                                  ? null
                                  : () => printGradeDocument(
                                      'getTranscriptDocument',
                                    ),
                              icon: const Icon(Icons.print_rounded, size: 17),
                              label: const Text('成绩表'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: printing
                                  ? null
                                  : () => printGradeDocument(
                                      'getGradeRankDocument',
                                    ),
                              icon: const Icon(
                                Icons.leaderboard_rounded,
                                size: 17,
                              ),
                              label: const Text('排名'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _openMonitorSheet,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: gradeMonitorEnabled
                                    ? palette.successSoft
                                    : palette.card,
                                side: BorderSide(
                                  color: gradeMonitorEnabled
                                      ? palette.success.withValues(alpha: 0.4)
                                      : palette.border,
                                ),
                                foregroundColor: gradeMonitorEnabled
                                    ? palette.success
                                    : palette.ink,
                              ),
                              icon: Icon(
                                gradeMonitorEnabled
                                    ? Icons.notifications_active_rounded
                                    : Icons.notifications_none_rounded,
                                size: 17,
                              ),
                              label: Text(
                                gradeMonitorEnabled ? '监测中' : '监测',
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (gradeMonitorEnabled) ...[
                        const SizedBox(height: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _openMonitorSheet,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              '成绩监测：${_intervalLabel(gradeIntervalMinutes)} · '
                              '${lastGradeCheck.isEmpty ? lastGradeMessage : '$lastGradeMessage（$lastGradeCheck）'}',
                              style: TextStyle(
                                color: palette.inkMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _searchController,
                        onChanged: (value) =>
                            setState(() => searchQuery = value),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          hintText: '搜索课程名称或代码',
                          isDense: true,
                          suffixIcon: searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => searchQuery = '');
                                  },
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      MiuixSegmentedControl<_GradeSortMode>(
                        height: 36,
                        value: sortMode,
                        items: const [
                          (value: _GradeSortMode.semester, label: '按学期'),
                          (value: _GradeSortMode.gpDesc, label: '绩点降序'),
                          (value: _GradeSortMode.creditsDesc, label: '学分降序'),
                        ],
                        onChanged: (mode) => setState(() => sortMode = mode),
                      ),
                      if (sortMode == _GradeSortMode.semester &&
                          semesters.length > 1) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: const Text('全部学期'),
                                  selected: semesterFilter == null,
                                  onSelected: (_) =>
                                      setState(() => semesterFilter = null),
                                ),
                              ),
                              for (final semester in semesters)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(semester),
                                    selected: semesterFilter == semester,
                                    onSelected: (_) => setState(
                                      () => semesterFilter = semester,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      if (filteredGrades.isEmpty)
                        EmptyState(
                          Icons.school_outlined,
                          allGrades.isEmpty ? '暂未查询到成绩' : '没有匹配的课程',
                        )
                      else if (sortMode != _GradeSortMode.semester) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '共 ${sortedFlatGrades.length} 门课程',
                                  style: TextStyle(
                                    color: palette.ink,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (computeWeightedGpa(sortedFlatGrades) != null)
                                MiuixTag(
                                  '均绩 ${computeWeightedGpa(sortedFlatGrades)!.toStringAsFixed(2)}',
                                ),
                            ],
                          ),
                        ),
                        for (final grade in sortedFlatGrades) ...[
                          GradeCard(grade, showSemester: true),
                          const SizedBox(height: 10),
                        ],
                      ] else
                        for (final semester in visibleSemesters) ...[
                          _SemesterSectionHeader(
                            semester: semester,
                            grades: groups[semester]!,
                          ),
                          for (final grade in groups[semester]!) ...[
                            GradeCard(grade),
                            const SizedBox(height: 10),
                          ],
                        ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _SemesterSectionHeader extends StatelessWidget {
  const _SemesterSectionHeader({
    required this.semester,
    required this.grades,
  });

  final String semester;
  final List<Map> grades;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final semesterGpa = computeWeightedGpa(grades);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              semester,
              style: TextStyle(
                color: palette.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (semesterGpa != null) ...[
            MiuixTag('均绩 ${semesterGpa.toStringAsFixed(2)}'),
            const SizedBox(width: 6),
          ],
          MiuixTag(
            '${grades.length} 门',
            color: palette.inkSecondary,
            backgroundColor: palette.cardSubtle,
          ),
        ],
      ),
    );
  }
}

/// 单科成绩展开卡片。
class GradeCard extends StatefulWidget {
  const GradeCard(this.grade, {super.key, this.showSemester = false});
  final Map grade;
  final bool showSemester;

  @override
  State<GradeCard> createState() => _GradeCardState();
}

class _GradeCardState extends State<GradeCard> {
  bool expanded = false;

  ({Color fg, Color bg}) _scoreColors(AppPalette palette, Map grade) {
    final scoreText = (grade['score'] ?? '--').toString().trim();
    final numeric = double.tryParse(scoreText);
    final gp = (grade['gp'] as num?)?.toDouble();
    final passed = grade['passed'];

    final isFailed = passed == false ||
        (numeric != null && numeric < 60) ||
        scoreText.contains('不及格') ||
        scoreText.contains('未通过') ||
        scoreText == 'F';
    if (isFailed) {
      return (fg: palette.danger, bg: palette.dangerSoft);
    }

    final isExcellent = (numeric != null && numeric >= 85) ||
        (gp != null && gp >= 3.7) ||
        scoreText == '优' ||
        scoreText == '优秀' ||
        scoreText == 'A' ||
        scoreText == 'A+';
    if (isExcellent) {
      return (fg: palette.success, bg: palette.successSoft);
    }

    return (fg: palette.primary, bg: palette.primarySoft);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final grade = widget.grade;
    final components = ((grade['components'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    if (components.isEmpty) {
      components.addAll([
        {'label': '平时成绩', 'value': grade['usual_score']},
        {'label': '卷面成绩', 'value': grade['paper_score']},
        {'label': '最终成绩', 'value': grade['score']},
      ]);
    }
    final colors = _scoreColors(palette, grade);

    return MiuixCard(
      radius: 18,
      padding: const EdgeInsets.all(14),
      onTap: () => setState(() => expanded = !expanded),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: colors.bg,
                  shape: miuixShape(14),
                ),
                child: Text(
                  (grade['score'] ?? '--').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (grade['course'] ?? '未知课程').toString(),
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        '${number(grade['credits'] ?? 0)} 学分',
                        '绩点 ${grade['gp'] == null ? '--' : number(grade['gp'])}',
                        if (widget.showSemester &&
                            (grade['semester'] ?? '').toString().isNotEmpty)
                          grade['semester'].toString(),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.inkSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: palette.inkMuted,
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      Divider(height: 1, color: palette.divider),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final component in components)
                            Container(
                              constraints: const BoxConstraints(minWidth: 88),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: ShapeDecoration(
                                color: palette.cardSubtle,
                                shape: miuixShape(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (component['label'] ?? '成绩分项').toString(),
                                    style: TextStyle(
                                      color: palette.inkSecondary,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    fallback(component['value'], '--'),
                                    style: TextStyle(
                                      color: palette.ink,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
