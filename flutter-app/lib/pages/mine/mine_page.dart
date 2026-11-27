import 'package:flutter/material.dart';

import '../../core/ai_service.dart';
import '../../core/formatters.dart';
import '../../core/native_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_components.dart';
import '../ai/ai_config_sheet.dart';
import 'network_page.dart';

/// 「我的」页面：账号名片、校园网/AI 配置、主题模式切换、后台巡检总览、应用更新与退出登录。
class MinePage extends StatefulWidget {
  const MinePage({
    super.key,
    required this.account,
    required this.themeController,
    required this.onLogout,
    this.updateInfo,
    this.onUpdateInfoChanged,
    this.onAiConfigChanged,
  });

  final String account;
  final ThemeController themeController;
  final Future<void> Function() onLogout;
  final Map<String, dynamic>? updateInfo;
  final ValueChanged<Map<String, dynamic>>? onUpdateInfoChanged;
  final VoidCallback? onAiConfigChanged;

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  Map<String, dynamic>? _monitorSettings;
  AiConfig _aiConfig = const AiConfig();

  @override
  void initState() {
    super.initState();
    _loadMonitorSummary();
    _loadAiConfig();
  }

  Future<void> _loadAiConfig() async {
    try {
      final raw = await NativeApi.call('getAiConfig');
      if (mounted) setState(() => _aiConfig = AiConfig.fromJson(raw));
    } catch (_) {}
  }

  Future<void> _openAiConfigSheet() async {
    final updated = await showAiConfigSheet(context, initialConfig: _aiConfig);
    if (updated != null && mounted) {
      setState(() => _aiConfig = updated);
      widget.onAiConfigChanged?.call();
    }
  }

  Future<void> _loadMonitorSummary() async {
    try {
      final result = await NativeApi.call('getMonitorSettings');
      if (mounted) setState(() => _monitorSettings = result);
    } catch (_) {}
  }

  String _monitorSummaryText() {
    final settings = _monitorSettings;
    if (settings == null) return '查看后台成绩与电量巡检状态';
    final parts = <String>[
      if (settings['grade_enabled'] == true) '成绩监测已开',
      if (settings['energy_enabled'] == true) '电量预警已开',
      if (settings['energy_email_enabled'] == true) '邮件提醒已开',
    ];
    return parts.isEmpty ? '后台监测均未开启' : parts.join(' · ');
  }

  Future<void> _showMonitorSummarySheet() async {
    await _loadMonitorSummary();
    if (!mounted) return;
    final settings = _monitorSettings;

    showMiuixSheet<void>(
      context,
      builder: (sheetContext) {
        final palette = sheetContext.palette;
        final gradeOn = settings?['grade_enabled'] == true;
        final gradeMins =
            (settings?['grade_interval_minutes'] as num?)?.toInt() ?? 720;
        final lastGradeMsg =
            (settings?['last_grade_message'] ?? '尚未检查').toString();
        final lastGradeTime =
            (settings?['last_grade_check'] ?? '').toString();
        final energyOn = settings?['energy_enabled'] == true;
        final energyThreshold =
            (settings?['energy_threshold'] as num?)?.toDouble() ?? 2;
        final emailOn = settings?['energy_email_enabled'] == true;
        final emailStatus =
            (settings?['last_email_status'] ?? '尚未发信').toString();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MiuixSheetHeader(
              title: '后台巡检概览',
              subtitle: '如需修改阈值与频率，请前往「学习 → 成绩」或「电费」页调整',
            ),
            const SizedBox(height: 16),
            MiuixCard(
              color: palette.cardSubtle,
              showShadow: false,
              radius: 16,
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  ConfirmRow(
                    '成绩监测',
                    gradeOn ? '已开启（每 $gradeMins 分钟）' : '未开启',
                  ),
                  ConfirmRow(
                    '最近成绩检查',
                    lastGradeTime.isEmpty
                        ? lastGradeMsg
                        : '$lastGradeMsg · $lastGradeTime',
                  ),
                  Divider(height: 14, color: palette.divider),
                  ConfirmRow(
                    '电量预警',
                    energyOn ? '低于 ${number(energyThreshold)} 度通知' : '未开启',
                  ),
                  ConfirmRow(
                    '低电量邮件',
                    emailOn ? '已开启 · $emailStatus' : '未开启',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _openUpdateSheet() {
    showMiuixSheet<void>(
      context,
      builder: (_) => _UpdateSheetContent(
        initialRelease: widget.updateInfo,
        onReleaseChanged: widget.onUpdateInfoChanged,
      ),
    );
  }

  void _openWidgetGuideSheet() {
    showMiuixSheet<void>(
      context,
      builder: (sheetContext) {
        final palette = sheetContext.palette;
        String? statusMessage;
        bool isErrorStatus = false;

        return StatefulBuilder(
          builder: (stateContext, setSheetState) {
            Future<void> triggerPin(String type, String label) async {
              try {
                final result = await NativeApi.call('pinWidget', {
                  'type': type,
                });
                final supported = result['supported'] == true;
                final requested = result['requested'] == true;
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  isErrorStatus = !(supported && requested);
                  statusMessage = (supported && requested)
                      ? '已向系统桌面请求添加「$label」。若桌面未弹出确认窗，请点击下方「打开应用权限设置」开启「桌面快捷方式」后再试。'
                      : '当前系统桌面未响应快捷固定，请返回桌面双指捏合 → 添加小部件 → 底部「Android 小部件」中查找「郑大生活助手」。';
                });
              } catch (caught) {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  isErrorStatus = true;
                  statusMessage = '调用失败：$caught';
                });
              }
            }

            Future<void> openPermissionSettings() async {
              try {
                await NativeApi.call('openAppSettings');
              } catch (caught) {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  isErrorStatus = true;
                  statusMessage = '无法打开应用设置：$caught';
                });
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MiuixSheetHeader(
                  title: '桌面小组件',
                  subtitle: '点击下方任意卡片尝试一键固定到桌面，或查看 HyperOS 添加说明',
                ),
                const SizedBox(height: 14),
                MiuixGroupedCard(
                  children: [
                    MiuixTile(
                      icon: Icons.today_rounded,
                      iconColor: palette.primary,
                      title: '今日课表',
                      subtitle: '当日日程卡片 · 进行中/下一节状态高亮',
                      trailingText: '添加',
                      onTap: () => triggerPin('today', '今日课表'),
                    ),
                    MiuixTile(
                      icon: Icons.calendar_view_week_rounded,
                      iconColor: palette.info,
                      title: '整周课表',
                      subtitle: '七天彩色课程表 · 支持离线缓存零流量刷新',
                      trailingText: '添加',
                      onTap: () => triggerPin('week', '整周课表'),
                    ),
                    MiuixTile(
                      icon: Icons.electric_bolt_rounded,
                      iconColor: palette.warning,
                      title: '寝室电量',
                      subtitle: '照明与空调剩余度数 · 低电阈值红标提醒',
                      trailingText: '添加',
                      onTap: () => triggerPin('energy', '寝室电量'),
                    ),
                  ],
                ),
                if (statusMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: ShapeDecoration(
                      color: isErrorStatus
                          ? palette.warningSoft
                          : palette.primarySoft,
                      shape: miuixShape(14),
                    ),
                    child: Text(
                      statusMessage!,
                      style: TextStyle(
                        color: isErrorStatus
                            ? palette.warning
                            : palette.onPrimarySoft,
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                MiuixCard(
                  color: palette.cardSubtle,
                  showShadow: false,
                  radius: 16,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const InfoRow(
                        Icons.security_rounded,
                        '小米 / 澎湃 OS 若点击「添加」无弹窗，请到系统「权限管理」中允许本应用「桌面快捷方式」。',
                      ),
                      const SizedBox(height: 10),
                      const InfoRow(
                        Icons.touch_app_outlined,
                        '手动添加：桌面双指捏合 → 添加小部件 → 拉到底部进入「Android 小部件 / 全部小组件」→ 搜索「郑大生活助手」。',
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: openPermissionSettings,
                          icon: const Icon(Icons.settings_outlined, size: 17),
                          label: const Text('打开应用权限设置'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后将清除本机保存的登录令牌，下次使用需重新输入学号和密码。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasUpdate = widget.updateInfo?['has_update'] == true;
    final latest = (widget.updateInfo?['latest'] ?? '').toString();
    final current = (widget.updateInfo?['current'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const MiuixPageHeader(
          title: '我的',
          padding: EdgeInsets.fromLTRB(4, 4, 4, 14),
        ),
        MiuixCard(
          radius: 22,
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  shape: miuixShape(17),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4C95FF), Color(0xFF256BE8)],
                  ),
                ),
                child: const Text(
                  '郑',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.account,
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    MiuixTag(
                      '本机直连 · 加密会话',
                      color: palette.success,
                      backgroundColor: palette.successSoft,
                      icon: Icons.verified_user_outlined,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const MiuixSectionHeader(
          title: '校园服务',
          padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
        ),
        MiuixGroupedCard(
          children: [
            MiuixTile(
              icon: Icons.auto_awesome_outlined,
              iconColor: palette.primary,
              title: 'AI 助手配置',
              subtitle: _aiConfig.isConfigured
                  ? '已配置 · ${_aiConfig.model}'
                  : '配置自定义 OpenAI 兼容 API（DeepSeek / OpenAI 等）',
              onTap: _openAiConfigSheet,
            ),
            MiuixTile(
              icon: Icons.wifi_rounded,
              iconColor: palette.info,
              title: '校园网账户',
              subtitle: '余额、流量、在线设备（需在校园网内）',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const NetworkPage()),
              ),
            ),
            MiuixTile(
              icon: Icons.notifications_active_outlined,
              iconColor: palette.primary,
              title: '后台巡检概览',
              subtitle: _monitorSummaryText(),
              onTap: _showMonitorSummarySheet,
            ),
          ],
        ),
        const MiuixSectionHeader(
          title: '外观设置',
          padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
        ),
        MiuixCard(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '主题模式',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: widget.themeController,
                builder: (_, mode, _) => MiuixSegmentedControl<ThemeMode>(
                  value: mode,
                  items: const [
                    (value: ThemeMode.system, label: '跟随系统'),
                    (value: ThemeMode.light, label: '浅色'),
                    (value: ThemeMode.dark, label: '深色'),
                  ],
                  onChanged: widget.themeController.setMode,
                ),
              ),
            ],
          ),
        ),
        const MiuixSectionHeader(
          title: '应用与帮助',
          padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
        ),
        MiuixGroupedCard(
          children: [
            MiuixTile(
              icon: Icons.system_update_alt_rounded,
              iconColor: palette.success,
              title: '检查更新',
              subtitle: hasUpdate
                  ? '发现新版本 $latest，点击查看详情'
                  : '检查 GitHub Release 新版本',
              trailingText: hasUpdate
                  ? '新版本'
                  : (current.isNotEmpty ? 'v$current' : null),
              showBadgeDot: hasUpdate,
              onTap: _openUpdateSheet,
            ),
            MiuixTile(
              icon: Icons.widgets_outlined,
              iconColor: palette.warning,
              title: '桌面小组件',
              subtitle: '添加今日课表、周课表与电量小组件',
              onTap: _openWidgetGuideSheet,
            ),
          ],
        ),
        const SizedBox(height: 22),
        MiuixCard(
          radius: 18,
          padding: const EdgeInsets.symmetric(vertical: 15),
          color: palette.dangerSoft,
          borderColor: palette.danger.withValues(alpha: 0.25),
          showShadow: false,
          onTap: _confirmLogout,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: palette.danger, size: 19),
              const SizedBox(width: 8),
              Text(
                '退出登录',
                style: TextStyle(
                  color: palette.danger,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 应用内检查更新弹窗内容。
class _UpdateSheetContent extends StatefulWidget {
  const _UpdateSheetContent({
    this.initialRelease,
    this.onReleaseChanged,
  });

  final Map<String, dynamic>? initialRelease;
  final ValueChanged<Map<String, dynamic>>? onReleaseChanged;

  @override
  State<_UpdateSheetContent> createState() => _UpdateSheetContentState();
}

class _UpdateSheetContentState extends State<_UpdateSheetContent> {
  final prefixController = TextEditingController();
  bool checking = false;
  bool installing = false;
  bool showProxyConfig = false;
  String? status;
  late Map<String, dynamic>? release = widget.initialRelease;
  String autoError = '';

  @override
  void initState() {
    super.initState();
    _syncFromRelease(release);
    _loadPrefix();
    _loadAuto();
  }

  @override
  void dispose() {
    prefixController.dispose();
    super.dispose();
  }

  void _syncFromRelease(Map<String, dynamic>? payload) {
    if (payload == null) return;
    final error = (payload['error'] ?? '').toString();
    autoError = error;
    if (payload['has_update'] == true) {
      status = '发现新版本 ${payload['latest']}';
    } else if (error.isEmpty && (payload['current'] ?? '').toString().isNotEmpty) {
      status = '已是最新版本（${payload['current']}）';
    }
  }

  Future<void> _loadPrefix() async {
    try {
      final result = await NativeApi.call('getUpdateProxyPrefix');
      if (!mounted) return;
      final prefix = (result['prefix'] ?? '').toString();
      setState(() {
        prefixController.text = prefix;
        if (prefix.isNotEmpty) showProxyConfig = true;
      });
    } catch (_) {}
  }

  Future<void> _loadAuto() async {
    try {
      final result = await NativeApi.call('autoCheckUpdate');
      if (!mounted) return;
      setState(() {
        release = result;
        _syncFromRelease(result);
      });
      widget.onReleaseChanged?.call(result);
    } catch (_) {}
  }

  Future<void> _savePrefix() async {
    try {
      await NativeApi.call('saveUpdateProxyPrefix', {
        'prefix': prefixController.text.trim(),
      });
    } catch (caught) {
      if (mounted) setState(() => status = caught.toString());
    }
  }

  Future<void> _check() async {
    setState(() {
      checking = true;
      status = null;
    });
    try {
      await _savePrefix();
      final result = await NativeApi.call('checkUpdate');
      if (!mounted) return;
      setState(() {
        release = result;
        autoError = (result['error'] ?? '').toString();
        status = result['has_update'] == true
            ? '发现新版本 ${result['latest']}'
            : '已是最新版本（${result['current']}）';
      });
      widget.onReleaseChanged?.call(result);
    } catch (caught) {
      if (mounted) setState(() => status = caught.toString());
    }
    if (mounted) setState(() => checking = false);
  }

  Future<void> _install() async {
    final url = (release?['url'] ?? '').toString();
    final latest = (release?['latest'] ?? '').toString();
    if (url.isEmpty) {
      setState(() => status = '该版本没有可下载的 APK 附件');
      return;
    }
    setState(() {
      installing = true;
      status = '正在下载 $latest …';
    });
    try {
      await NativeApi.call('installUpdate', {'url': url, 'version': latest});
      if (mounted) setState(() => status = '已交给系统安装器，请按提示确认安装');
    } catch (caught) {
      if (mounted) setState(() => status = caught.toString());
    }
    if (mounted) setState(() => installing = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasUpdate = release?['has_update'] == true;
    final notes = (release?['notes'] ?? '').toString().trim();
    final size = (release?['size'] as num?)?.toDouble() ?? 0;
    final checkedAt = (release?['checked_at'] as num?)?.toInt() ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MiuixSheetHeader(
          title: '检查更新',
          subtitle: '来自 GitHub Release · 安装需系统界面确认',
          trailing: (checking || installing) ? const Loader(size: 18) : null,
        ),
        const SizedBox(height: 14),
        if (status != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: ShapeDecoration(
              color: hasUpdate ? palette.primarySoft : palette.cardSubtle,
              shape: miuixShape(14),
            ),
            child: Text(
              status!,
              style: TextStyle(
                color: hasUpdate ? palette.onPrimarySoft : palette.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (checkedAt > 0) ...[
          const SizedBox(height: 8),
          Text(
            '上次检查：${formatTimestamp(checkedAt)} · 自动检查每 48 小时一次',
            style: TextStyle(color: palette.inkMuted, fontSize: 11.5),
          ),
        ],
        if (autoError.isNotEmpty && !hasUpdate) ...[
          const SizedBox(height: 6),
          Text(
            '自动检查未成功：$autoError',
            style: TextStyle(color: palette.warning, fontSize: 11.5),
          ),
        ],
        if (hasUpdate && notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: ShapeDecoration(
              color: palette.cardSubtle,
              shape: miuixShape(14),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Text(
                  notes,
                  style: TextStyle(
                    color: palette.inkSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => showProxyConfig = !showProxyConfig),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text(
                  'GitHub 加速前缀设置（可选）',
                  style: TextStyle(
                    color: palette.inkSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  showProxyConfig
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: palette.inkMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (showProxyConfig) ...[
          const SizedBox(height: 6),
          TextField(
            controller: prefixController,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: '加速前缀（留空直连）',
              hintText: '例如 https://ghfast.top/',
              isDense: true,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: checking || installing ? null : _check,
                child: const Text('立即检查'),
              ),
            ),
            if (hasUpdate) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: installing ? null : _install,
                  child: Text(
                    size > 0
                        ? '下载安装（${(size / 1024 / 1024).toStringAsFixed(1)} MB）'
                        : '下载安装',
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
