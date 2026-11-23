import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/native_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_components.dart';

/// 校园网账户查询页面（仅在校园网内可达；密码不持久化）。
class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  final accountController = TextEditingController();
  final passwordController = TextEditingController();
  final baseController = TextEditingController(text: 'http://10.2.7.16:8080');

  bool loading = false;
  bool withHistory = false;
  bool showPassword = false;
  bool showAdvanced = false;
  bool formExpanded = true;
  String? error;
  Map<String, dynamic>? account;
  List<Map> devices = [];
  List<Map> history = [];

  @override
  void initState() {
    super.initState();
    prefillAccount();
  }

  @override
  void dispose() {
    accountController.dispose();
    passwordController.dispose();
    baseController.dispose();
    super.dispose();
  }

  /// 用已登录的学号预填网络账号（使用已存在的 getSession 通道）。
  Future<void> prefillAccount() async {
    try {
      final session = await NativeApi.call('getSession');
      final value = (session['account'] ?? '').toString();
      if (mounted && value.isNotEmpty && accountController.text.isEmpty) {
        accountController.text = value;
      }
    } catch (_) {
      // 拿不到就留空，让用户自己填。
    }
  }

  Future<void> query() async {
    if (accountController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      setState(() => error = '请填写网络账号和密码');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await NativeApi.call('getNetwork', {
        'account': accountController.text.trim(),
        'password': passwordController.text,
        'base_url': baseController.text.trim(),
        'history': withHistory ? '1' : '',
      });
      if (!mounted) return;
      setState(() {
        account = (result['account'] as Map?)?.cast<String, dynamic>();
        devices = ((result['devices'] as List?) ?? const [])
            .whereType<Map>()
            .toList();
        history = ((result['history'] as List?) ?? const [])
            .whereType<Map>()
            .toList();
        formExpanded = false;
      });
    } catch (caught) {
      if (mounted) {
        setState(() {
          error = caught.toString();
          formExpanded = true;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        title: const Text('校园网账户'),
        actions: [
          if (account != null)
            IconButton(
              onPressed: loading ? null : query,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '重新查询',
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
          children: [
            if (formExpanded || account == null)
              _formCard()
            else
              _compactAccountBar(),
            if (error != null) ...[
              const SizedBox(height: 12),
              MiuixCard(
                radius: 16,
                padding: const EdgeInsets.all(14),
                color: palette.dangerSoft,
                borderColor: palette.danger.withValues(alpha: 0.35),
                showShadow: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: palette.danger,
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: palette.danger,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (loading) ...[
              const SizedBox(height: 36),
              const Center(child: Loader()),
            ] else if (account != null) ...[
              const SizedBox(height: 14),
              _accountCard(),
              const SizedBox(height: 14),
              _deviceSection(),
              if (withHistory) ...[
                const SizedBox(height: 14),
                _historySection(),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _compactAccountBar() {
    final palette = context.palette;
    return MiuixCard(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => setState(() => formExpanded = true),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: ShapeDecoration(
              color: palette.successSoft,
              shape: miuixShape(10),
            ),
            child: Icon(Icons.wifi_rounded, color: palette.success, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已连接账号 ${accountController.text.trim()}',
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '点击展开凭据或切换登录历史选项',
                  style: TextStyle(color: palette.inkMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            '编辑',
            style: TextStyle(
              color: palette.primary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard() {
    final palette = context.palette;
    return MiuixCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: accountController,
            enabled: !loading,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.badge_outlined),
              labelText: '网络账号',
              hintText: '学号 / 校园网账号',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            obscureText: !showPassword,
            enabled: !loading,
            onSubmitted: (_) => query(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              labelText: '网络密码',
              hintText: '校园网密码（不保存）',
              suffixIcon: IconButton(
                onPressed: () => setState(() => showPassword = !showPassword),
                icon: Icon(
                  showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '同时拉取登录历史（较慢）',
                  style: TextStyle(
                    color: palette.inkSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              Switch(
                value: withHistory,
                onChanged: loading
                    ? null
                    : (value) => setState(() => withHistory = value),
              ),
            ],
          ),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => showAdvanced = !showAdvanced),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(
                    '高级设置（自助服务地址）',
                    style: TextStyle(
                      color: palette.inkMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    showAdvanced
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: palette.inkMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (showAdvanced) ...[
            const SizedBox(height: 6),
            TextField(
              controller: baseController,
              enabled: !loading,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.link_rounded),
                hintText: 'http://10.2.7.16:8080',
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: loading ? null : query,
              icon: const Icon(Icons.wifi_find_rounded, size: 19),
              label: const Text('查询校园网状态'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountCard() {
    final palette = context.palette;
    final data = account!;
    final rows = <(String, String)>[
      ('累计上行', '${number(data['up_flow'])} MB'),
      ('累计下行', '${number(data['down_flow'])} MB'),
      ('已绑定 IP', '${number(data['ip_count'])}/${number(data['ip_max_count'])}'),
      if ((data['start_date'] ?? '').toString().isNotEmpty)
        ('计费周期', '${data['start_date']} ~ ${data['stop_date'] ?? '-'}'),
    ];

    return MiuixCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (data['user_name'] ?? '校园网').toString(),
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    if ((data['group_name'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '套餐：${data['group_name']}',
                        style: TextStyle(
                          color: palette.inkSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if ((data['service_name'] ?? '').toString().isNotEmpty)
                MiuixTag(data['service_name'].toString()),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.25,
            children: [
              _statTile(
                palette,
                '账户余额',
                '${number(data['left_money'])} 元',
                palette.primary,
              ),
              _statTile(
                palette,
                '剩余流量',
                '${number(data['left_flow'])} MB',
                palette.success,
              ),
              _statTile(
                palette,
                '已用流量',
                '${number(data['use_flow'])} MB',
                palette.ink,
              ),
              _statTile(
                palette,
                '在线上限',
                '${number(data['multi_login'])} 台',
                palette.ink,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: palette.divider),
          const SizedBox(height: 6),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      style: TextStyle(
                        color: palette.inkSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  Text(
                    row.$2,
                    style: TextStyle(
                      color: palette.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statTile(
    AppPalette palette,
    String label,
    String value,
    Color valueColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: ShapeDecoration(
        color: palette.cardSubtle,
        shape: miuixShape(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(color: palette.inkSecondary, fontSize: 11),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceSection() {
    final palette = context.palette;
    return MiuixCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前在线设备（${devices.length}）',
            style: TextStyle(
              color: palette.ink,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '没有在线设备。',
                style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
              ),
            )
          else
            for (var i = 0; i < devices.length; i++) ...[
              if (i > 0) Divider(height: 18, color: palette.divider),
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 10 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.devices_rounded,
                      size: 18,
                      color: palette.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (devices[i]['ip'] ?? '-').toString(),
                            style: TextStyle(
                              color: palette.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${devices[i]['mac'] ?? '-'} · '
                            '${(devices[i]['terminalType'] ?? '').toString().replaceFirst('#', '')}',
                            style: TextStyle(
                              color: palette.inkSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                          Text(
                            '登录于 ${devices[i]['loginTime'] ?? '-'}',
                            style: TextStyle(
                              color: palette.inkMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _historySection() {
    final palette = context.palette;
    return MiuixCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '登录历史（${history.length}）',
            style: TextStyle(
              color: palette.ink,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '没有登录记录。',
                style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
              ),
            )
          else
            for (var i = 0; i < history.length; i++) ...[
              if (i > 0) Divider(height: 16, color: palette.divider),
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 10 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${history[i]['start_time'] ?? '-'} ~ '
                      '${history[i]['end_time'] ?? '-'}',
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${history[i]['ip'] ?? '-'} · ${history[i]['mac'] ?? '-'} · '
                      '${history[i]['terminal_type'] ?? '-'}',
                      style: TextStyle(
                        color: palette.inkSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}
