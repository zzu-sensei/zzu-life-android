import 'package:flutter/material.dart';

import '../../core/native_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_components.dart';

/// 考试安排页面：底部弹窗选学期、待考倒计时、未考置顶与突出座位号展示。
class ExamPage extends StatefulWidget {
  const ExamPage({super.key});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  List<Map> semesters = [];
  String? semesterId;
  List<Map>? exams;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({String? semester}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await NativeApi.call('getExams', {
        'semester_id': semester ?? '',
      });
      if (!mounted) return;
      final target = result['semester'];
      setState(() {
        semesters = ((result['semesters'] as List?) ?? const [])
            .whereType<Map>()
            .toList();
        semesterId = target is Map ? target['id']?.toString() : null;
        exams = ((result['exams'] as List?) ?? const [])
            .whereType<Map>()
            .toList();
      });
    } catch (caught) {
      if (mounted) setState(() => error = caught.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _currentSemesterName() {
    for (final semester in semesters) {
      if (semester['id']?.toString() == semesterId) {
        return (semester['name'] ?? '未知学期').toString();
      }
    }
    return semesters.isNotEmpty
        ? (semesters.first['name'] ?? '选择学期').toString()
        : '选择学期';
  }

  Future<void> _pickSemester() async {
    if (semesters.isEmpty || loading) return;
    final picked = await showMiuixSheet<String>(
      context,
      builder: (sheetContext) {
        final palette = sheetContext.palette;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MiuixSheetHeader(
              title: '选择学期',
              subtitle: '查看对应学期的考试安排',
            ),
            const SizedBox(height: 14),
            MiuixGroupedCard(
              dividerIndent: 16,
              children: [
                for (final semester in semesters)
                  ListTile(
                    title: Text(
                      (semester['name'] ?? '未知学期').toString(),
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: semester['id']?.toString() == semesterId
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 14.5,
                      ),
                    ),
                    trailing: semester['id']?.toString() == semesterId
                        ? Icon(Icons.check_rounded, color: palette.primary)
                        : null,
                    onTap: () => Navigator.pop(
                      sheetContext,
                      semester['id']?.toString(),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
    if (picked != null && picked != semesterId) {
      setState(() => semesterId = picked);
      await load(semester: picked);
    }
  }

  int? _daysUntil(String dateStr) {
    final parsed = DateTime.tryParse(dateStr.trim());
    if (parsed == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final examDay = DateTime(parsed.year, parsed.month, parsed.day);
    return examDay.difference(today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MiuixPageHeader(
          title: '考试安排',
          subtitle: '考试时间、地点与座位号来自本科教务',
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
          action: IconButton.filledTonal(
            tooltip: '刷新考试安排',
            onPressed: loading ? null : () => load(semester: semesterId),
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ),
        if (semesters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: MiuixCard(
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              onTap: loading ? null : _pickSemester,
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 17,
                    color: context.palette.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _currentSemesterName(),
                      style: TextStyle(
                        color: context.palette.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: context.palette.inkMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: loading
              ? const Center(child: Loader())
              : error != null
              ? ErrorState(
                  message: error!,
                  retry: () => load(semester: semesterId),
                )
              : _examList(),
        ),
      ],
    );
  }

  Widget _examList() {
    final palette = context.palette;
    final raw = exams ?? const <Map>[];
    if (raw.isEmpty) {
      return const EmptyState(
        Icons.event_busy_outlined,
        '这个学期还没有考试安排',
      );
    }

    // 未考排在前面，已考排在后面，保持原有先后顺序。
    final upcoming = raw.where((e) => e['finished'] != true).toList();
    final finished = raw.where((e) => e['finished'] == true).toList();
    final ordered = [...upcoming, ...finished];

    String? nearestSummary;
    if (upcoming.isNotEmpty) {
      final first = upcoming.first;
      final days = _daysUntil((first['date'] ?? '').toString());
      final when = days == null
          ? '时间待定'
          : days < 0
          ? '近期'
          : days == 0
          ? '就在今天'
          : days == 1
          ? '就在明天'
          : '$days 天后';
      nearestSummary =
          '最近一场：${first['course_name'] ?? '未知课程'} · $when';
    }

    return RefreshIndicator(
      onRefresh: () => load(semester: semesterId),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (upcoming.isNotEmpty) ...[
            MiuixHeroBanner(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              radius: 20,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.event_note_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '待考 ${upcoming.length} 门',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (nearestSummary != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            nearestSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final exam in ordered) ...[
            _examCard(exam),
            const SizedBox(height: 10),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '考试信息由教务发布，如有调整以教务系统为准。',
              style: TextStyle(
                color: palette.inkMuted,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _examCard(Map exam) {
    final palette = context.palette;
    final finished = exam['finished'] == true;
    final status = (exam['status_label'] ?? '未知').toString();
    final date = (exam['date'] ?? '').toString();
    final start = (exam['start_time'] ?? '').toString();
    final end = (exam['end_time'] ?? '').toString();
    final timeText = date.isEmpty ? '时间待定' : '$date $start–$end';
    final place = (exam['place'] ?? '').toString();
    final seatNo = (exam['seat_no'] ?? '').toString();
    final examType = (exam['exam_type'] ?? '').toString();
    final daysLeft = finished ? null : _daysUntil(date);

    late final MiuixTag badge;
    if (finished) {
      badge = MiuixTag(
        '已考',
        color: palette.inkMuted,
        backgroundColor: palette.cardSubtle,
      );
    } else if (daysLeft == 0) {
      badge = MiuixTag(
        '今天',
        color: palette.danger,
        backgroundColor: palette.dangerSoft,
      );
    } else if (daysLeft == 1) {
      badge = MiuixTag(
        '明天',
        color: palette.warning,
        backgroundColor: palette.warningSoft,
      );
    } else if (daysLeft != null && daysLeft > 1) {
      badge = MiuixTag('$daysLeft 天后');
    } else {
      badge = MiuixTag(status);
    }

    return MiuixCard(
      radius: 18,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  (exam['course_name'] ?? '未知课程').toString(),
                  style: TextStyle(
                    color: finished ? palette.inkSecondary : palette.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              badge,
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(Icons.schedule_rounded, timeText),
          if (place.isNotEmpty) ...[
            const SizedBox(height: 6),
            InfoRow(Icons.place_outlined, place),
          ],
          if (seatNo.isNotEmpty || examType.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (seatNo.isNotEmpty)
                  MiuixTag(
                    '座位 $seatNo',
                    icon: Icons.event_seat_outlined,
                  ),
                if (examType.isNotEmpty)
                  MiuixTag(
                    examType,
                    color: palette.inkSecondary,
                    backgroundColor: palette.cardSubtle,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
