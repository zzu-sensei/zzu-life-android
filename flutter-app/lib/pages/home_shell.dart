import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/native_api.dart';
import '../../theme/app_theme.dart';
import 'energy/energy_page.dart';
import 'mine/mine_page.dart';
import 'schedule/schedule_page.dart';
import 'study/study_hub_page.dart';

/// 主界面导航壳：底部 4 标签栏（课表 / 学习 / 电费 / 我的），页面按需懒加载。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.account,
    required this.themeController,
    required this.onLogout,
  });

  final String account;
  final ThemeController themeController;
  final Future<void> Function() onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final Set<int> _mountedTabs = {0};
  Map<String, dynamic>? _updateInfo;

  @override
  void initState() {
    super.initState();
    _checkUpdateInBackground();
  }

  /// 打开应用时静默检查一次更新（后端按 48 小时节流，失败也不打扰）。
  ///
  /// 只有当真的发现新版本、而通知又没发出去时才申请一次通知权限。
  Future<void> _checkUpdateInBackground() async {
    try {
      final result = await NativeApi.call('autoCheckUpdate');
      if (!mounted) return;
      setState(() => _updateInfo = result);
      if (result['has_update'] == true && result['notified'] != true) {
        await NativeApi.call('requestUpdateNotifyPermission');
      }
    } catch (_) {
      // 更新检查失败不打扰用户。
    }
  }

  void _selectTab(int next) {
    if (next == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = next;
      _mountedTabs.add(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasUpdate = _updateInfo?['has_update'] == true;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: [
            _mountedTabs.contains(0)
                ? const SchedulePage()
                : const SizedBox.shrink(),
            _mountedTabs.contains(1)
                ? const StudyHubPage()
                : const SizedBox.shrink(),
            _mountedTabs.contains(2)
                ? const EnergyPage()
                : const SizedBox.shrink(),
            _mountedTabs.contains(3)
                ? MinePage(
                    account: widget.account,
                    themeController: widget.themeController,
                    onLogout: widget.onLogout,
                    updateInfo: _updateInfo,
                    onUpdateInfoChanged: (info) {
                      if (mounted) setState(() => _updateInfo = info);
                    },
                  )
                : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.border, width: 0.7)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _selectTab,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.calendar_today_outlined),
              selectedIcon: Icon(Icons.calendar_today_rounded),
              label: '课表',
            ),
            const NavigationDestination(
              icon: Icon(Icons.school_outlined),
              selectedIcon: Icon(Icons.school_rounded),
              label: '学习',
            ),
            const NavigationDestination(
              icon: Icon(Icons.bolt_outlined),
              selectedIcon: Icon(Icons.bolt_rounded),
              label: '电费',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: hasUpdate,
                smallSize: 7,
                child: const Icon(Icons.person_outline_rounded),
              ),
              selectedIcon: Badge(
                isLabelVisible: hasUpdate,
                smallSize: 7,
                child: const Icon(Icons.person_rounded),
              ),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
