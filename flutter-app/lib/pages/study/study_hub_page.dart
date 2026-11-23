import 'package:flutter/material.dart';

import '../../widgets/miuix_components.dart';
import 'exam_page.dart';
import 'grades_page.dart';
import 'program_plan_page.dart';

/// 「学习」入口的多标签容器：成绩 / 考试 / 培养计划。
///
/// 子页采用懒加载策略：首次切到对应标签时才挂载组件并发起网络请求，避免冷启动
/// 时同时冲击单线程原生通道。
class StudyHubPage extends StatefulWidget {
  const StudyHubPage({super.key});

  @override
  State<StudyHubPage> createState() => _StudyHubPageState();
}

class _StudyHubPageState extends State<StudyHubPage> {
  int _tab = 0;
  final Set<int> _mountedTabs = {0};

  void _selectTab(int next) {
    setState(() {
      _tab = next;
      _mountedTabs.add(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: MiuixSegmentedControl<int>(
            value: _tab,
            items: const [
              (value: 0, label: '成绩'),
              (value: 1, label: '考试'),
              (value: 2, label: '培养计划'),
            ],
            onChanged: _selectTab,
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _mountedTabs.contains(0)
                  ? const GradesPage()
                  : const SizedBox.shrink(),
              _mountedTabs.contains(1)
                  ? const ExamPage()
                  : const SizedBox.shrink(),
              _mountedTabs.contains(2)
                  ? const ProgramPlanPage()
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}
