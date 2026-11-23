import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/native_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_components.dart';

enum _PlanStatusFilter { all, failed, taking, passed }

/// 培养计划完成情况页面：官方学分进度环、按学期/按模块切换、课程状态筛选。
class ProgramPlanPage extends StatefulWidget {
  const ProgramPlanPage({super.key});

  @override
  State<ProgramPlanPage> createState() => _ProgramPlanPageState();
}

class _ProgramPlanPageState extends State<ProgramPlanPage> {
  Map<String, dynamic>? plan;
  bool loading = true;
  String? error;

  /// 0 = 按学期，1 = 按学分模块。
  int viewMode = 0;

  _PlanStatusFilter statusFilter = _PlanStatusFilter.all;

  /// 展开的学期序号（默认展开第一个有未通过/在修的学期）。
  final Set<int> expandedSemesters = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await NativeApi.call('getProgramPlan');
      if (!mounted) return;
      setState(() {
        plan = result;
        expandedSemesters.clear();
        for (final semester in ((result['semesters'] as List?) ?? const [])
            .whereType<Map>()) {
          final pending =
              ((semester['failed_count'] as num?)?.toInt() ?? 0) +
              ((semester['taking_count'] as num?)?.toInt() ?? 0);
          if (pending > 0) {
            expandedSemesters.add((semester['semester'] as num?)?.toInt() ?? 0);
            break;
          }
        }
      });
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    }
    if (mounted) setState(() => loading = false);
  }

  List<Map> _filteredCourses(List<Map> courses) {
    switch (statusFilter) {
      case _PlanStatusFilter.all:
        return courses;
      case _PlanStatusFilter.failed:
        return courses.where((c) => c['status'] == 'failed').toList();
      case _PlanStatusFilter.taking:
        return courses.where((c) => c['status'] == 'taking').toList();
      case _PlanStatusFilter.passed:
        return courses
            .where((c) => c['status'] != 'failed' && c['status'] != 'taking')
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final modules = ((plan?['modules'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final semesters = ((plan?['semesters'] as List?) ?? const [])
        .whereType<Map>()
        .toList();

    return Column(
      children: [
        MiuixPageHeader(
          title: '培养计划',
          subtitle: plan == null
              ? '从教务读取官方学分要求与计划课程'
              : '已通过 ${number(plan!['passed_credits'])} / '
                    '${number(plan!['required_credits'])} 学分',
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
          action: IconButton.filledTonal(
            tooltip: '刷新培养计划',
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
                      _planSummaryCard(),
                      const SizedBox(height: 12),
                      MiuixSegmentedControl<int>(
                        value: viewMode,
                        items: const [
                          (value: 0, label: '按学期查看'),
                          (value: 1, label: '按学分模块'),
                        ],
                        onChanged: (value) => setState(() => viewMode = value),
                      ),
                      if (viewMode == 0 && semesters.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final option in const [
                                (_PlanStatusFilter.all, '全部'),
                                (_PlanStatusFilter.failed, '未通过'),
                                (_PlanStatusFilter.taking, '在修'),
                                (_PlanStatusFilter.passed, '已通过'),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(option.$2),
                                    selected: statusFilter == option.$1,
                                    onSelected: (_) => setState(
                                      () => statusFilter = option.$1,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (viewMode == 1) ...[
                        if (modules.isEmpty)
                          const EmptyState(
                            Icons.view_module_outlined,
                            '暂未获取到模块学分信息',
                          )
                        else
                          for (final module in modules) ...[
                            _moduleCard(module),
                            const SizedBox(height: 10),
                          ],
                      ] else if (semesters.isEmpty)
                        const EmptyState(
                          Icons.menu_book_outlined,
                          '教务没有返回带学期的课程信息',
                        )
                      else ...[
                        for (final semester in semesters)
                          if (_filteredCourses(
                            ((semester['courses'] as List?) ?? const [])
                                .whereType<Map>()
                                .toList(),
                          ).isNotEmpty) ...[
                            _semesterCard(semester),
                            const SizedBox(height: 10),
                          ],
                        if (semesters.every(
                          (s) => _filteredCourses(
                            ((s['courses'] as List?) ?? const [])
                                .whereType<Map>()
                                .toList(),
                          ).isEmpty,
                        ))
                          const EmptyState(
                            Icons.filter_alt_off_outlined,
                            '当前筛选条件下没有课程',
                          ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _planSummaryCard() {
    final palette = context.palette;
    final required = (plan?['required_credits'] as num?)?.toDouble() ?? 0;
    final passed = (plan?['passed_credits'] as num?)?.toDouble() ?? 0;
    final taking = (plan?['taking_credits'] as num?)?.toDouble() ?? 0;
    final failedCredits = (plan?['failed_credits'] as num?)?.toDouble() ?? 0;
    final missing = (plan?['missing'] as num?)?.toDouble() ?? 0;
    final ratio = required <= 0 ? 0.0 : (passed / required).clamp(0.0, 1.0);

    return MiuixCard(
      radius: 22,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            height: 86,
            child: CustomPaint(
              painter: _PlanRingPainter(
                progress: ratio,
                trackColor: palette.cardSubtle,
                progressColor: missing <= 0 ? palette.success : palette.primary,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(ratio * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      '完成度',
                      style: TextStyle(
                        color: palette.inkMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      number(passed),
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '/ ${number(required)} 学分',
                      style: TextStyle(
                        color: palette.inkSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  missing <= 0
                      ? '已满足培养方案最低学分要求'
                      : '还差 ${number(missing)} 学分',
                  style: TextStyle(
                    color: missing <= 0 ? palette.success : palette.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (taking > 0 || failedCredits > 0) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (taking > 0)
                        MiuixTag(
                          '在修 ${number(taking)} 学分',
                          color: palette.info,
                          backgroundColor: palette.infoSoft,
                        ),
                      if (failedCredits > 0)
                        MiuixTag(
                          '未通过 ${number(failedCredits)} 学分',
                          color: palette.danger,
                          backgroundColor: palette.dangerSoft,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _semesterCard(Map semester) {
    final palette = context.palette;
    final term = (semester['semester'] as num?)?.toInt() ?? 0;
    final allCourses = ((semester['courses'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final visibleCourses = _filteredCourses(allCourses);
    final forceExpand = statusFilter != _PlanStatusFilter.all;
    final expanded = forceExpand || expandedSemesters.contains(term);

    final averageGp = semester['average_gp'];
    final failedCount = (semester['failed_count'] as num?)?.toInt() ?? 0;
    final takingCount = (semester['taking_count'] as num?)?.toInt() ?? 0;
    final passedCount = (semester['passed_count'] as num?)?.toInt() ?? 0;

    return MiuixCard(
      radius: 18,
      padding: const EdgeInsets.all(14),
      borderColor: failedCount > 0
          ? palette.danger.withValues(alpha: 0.35)
          : takingCount > 0
          ? palette.info.withValues(alpha: 0.35)
          : palette.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: forceExpand
                ? null
                : () => setState(() {
                    if (expanded) {
                      expandedSemesters.remove(term);
                    } else {
                      expandedSemesters.add(term);
                    }
                  }),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (semester['label'] ?? '未标注学期').toString(),
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          '${visibleCourses.length} 门',
                          '已通过 ${number(semester['earned_credits'])} 学分',
                          if (failedCount > 0) '未通过 $failedCount',
                          if (takingCount > 0) '在修 $takingCount',
                        ].join(' · '),
                        style: TextStyle(
                          color: palette.inkSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (averageGp != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          number(averageGp),
                          style: TextStyle(
                            color: palette.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          '均绩 · ${number(semester['graded_credits'])}学分',
                          style: TextStyle(
                            color: palette.inkMuted,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!forceExpand)
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: palette.inkMuted,
                  ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 10),
            for (var i = 0; i < visibleCourses.length; i++) ...[
              if (i > 0) Divider(height: 14, color: palette.divider),
              _courseRow(visibleCourses[i]),
            ],
          ] else if (passedCount == allCourses.length && allCourses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '该学期课程已全部通过',
                style: TextStyle(color: palette.success, fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _courseRow(Map course) {
    final palette = context.palette;
    final status = (course['status'] ?? 'unknown').toString();
    final gp = course['gp'];
    final score = (course['score'] ?? '').toString();
    final accent = status == 'failed'
        ? palette.danger
        : status == 'taking'
        ? palette.info
        : palette.success;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 28,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (course['name'] ?? '未知课程').toString(),
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    '${number(course['credits'])} 学分',
                    if ((course['module'] ?? '').toString().isNotEmpty)
                      (course['module'] ?? '').toString(),
                    if (status == 'taking') '在修',
                    if (status == 'failed') '未通过',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.inkSecondary, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                score.isEmpty ? '--' : score,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: status == 'failed'
                      ? palette.danger
                      : status == 'taking'
                      ? palette.info
                      : palette.ink,
                ),
              ),
              Text(
                gp == null ? '绩点 --' : '绩点 ${number(gp)}',
                style: TextStyle(color: palette.inkMuted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _moduleCard(Map module) {
    final palette = context.palette;
    final required = (module['required_credits'] as num?)?.toDouble() ?? 0;
    final passed = (module['passed_credits'] as num?)?.toDouble() ?? 0;
    final taking = (module['taking_credits'] as num?)?.toDouble() ?? 0;
    final missing = (module['missing'] as num?)?.toDouble() ?? 0;
    final done = module['done'] == true;
    final ratio = required <= 0 ? 1.0 : (passed / required).clamp(0.0, 1.0);
    final note = (module['note'] ?? '').toString();

    return MiuixCard(
      radius: 18,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (module['name'] ?? '模块').toString(),
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              MiuixTag(
                done ? '已达标' : '还差 ${number(missing)}',
                color: done ? palette.success : palette.danger,
                backgroundColor: done
                    ? palette.successSoft
                    : palette.dangerSoft,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              color: done ? palette.success : palette.primary,
              backgroundColor: palette.cardSubtle,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${number(passed)} / ${number(required)} 学分',
                style: TextStyle(
                  color: palette.inkSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (taking > 0) ...[
                const SizedBox(width: 10),
                Text(
                  '在修 ${number(taking)} 学分',
                  style: TextStyle(color: palette.info, fontSize: 12),
                ),
              ],
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: TextStyle(color: palette.inkMuted, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanRingPainter extends CustomPainter {
  _PlanRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 8.5;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = progressColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_PlanRingPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.progressColor != progressColor;
}
