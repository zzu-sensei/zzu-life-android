import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/drain_estimator.dart';
import '../../core/formatters.dart';
import '../../core/native_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_components.dart';
import 'drain_chart_page.dart';

/// 寝室电量与充值页面。
class EnergyPage extends StatefulWidget {
  const EnergyPage({super.key});

  @override
  State<EnergyPage> createState() => _EnergyPageState();
}

class _EnergyPageState extends State<EnergyPage> {
  Map<String, dynamic>? data;
  bool loading = true;
  bool recharging = false;
  bool alertSaving = false;
  bool energyAlertEnabled = false;
  double energyThreshold = 2;
  bool emailAlertEnabled = false;
  double emailThreshold = 2;
  bool emailSecretSet = false;
  String lastEmailStatus = '尚未发信';
  List<Map> drainSamples = const [];
  final TextEditingController emailEndpoint = TextEditingController();
  final TextEditingController emailSecret = TextEditingController();
  String? error;

  double? cardBalance;
  int? emailUnread;
  bool cardLoading = true;
  String? cardError;

  @override
  void initState() {
    super.initState();
    load();
    loadCardBalance();
    loadMonitorSettings();
    loadDrainSamples();
  }

  @override
  void dispose() {
    emailEndpoint.dispose();
    emailSecret.dispose();
    super.dispose();
  }

  Future<void> loadDrainSamples() async {
    try {
      final result = await NativeApi.call('getEnergySamples');
      if (!mounted) return;
      setState(() {
        drainSamples = ((result['samples'] as List?) ?? const [])
            .whereType<Map>()
            .toList();
      });
    } catch (_) {
      // 采样读取失败不影响电量展示。
    }
  }

  Future<void> loadMonitorSettings() async {
    try {
      final settings = await NativeApi.call('getMonitorSettings');
      if (!mounted) return;
      setState(() {
        energyAlertEnabled = settings['energy_enabled'] == true;
        energyThreshold =
            (settings['energy_threshold'] as num?)?.toDouble() ?? 2;
        emailAlertEnabled = settings['energy_email_enabled'] == true;
        emailThreshold =
            (settings['energy_email_threshold'] as num?)?.toDouble() ?? 2;
        emailSecretSet = settings['energy_email_secret_set'] == true;
        lastEmailStatus = settings['last_email_status']?.toString() ?? '尚未发信';
        emailEndpoint.text =
            settings['energy_email_endpoint']?.toString() ?? '';
      });
    } catch (_) {}
  }

  Future<bool> _saveMonitorSettings(Map<String, Object?> payload) async {
    if (mounted) setState(() => alertSaving = true);
    try {
      final result = await NativeApi.call('saveMonitorSettings', payload);
      if (mounted) {
        final status = result['last_email_status']?.toString();
        if (status != null) setState(() => lastEmailStatus = status);
      }
      return true;
    } catch (caught) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(caught.toString())),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => alertSaving = false);
    }
  }

  Future<void> loadCardBalance() async {
    if (mounted) {
      setState(() {
        cardLoading = true;
        cardError = null;
      });
    }
    try {
      final result = await NativeApi.call('getCardBalance');
      if (!mounted) return;
      setState(() {
        cardBalance = (result['balance'] as num?)?.toDouble();
        emailUnread = (result['email_unread'] as num?)?.toInt();
        cardError = null;
      });
    } catch (caught) {
      if (mounted) setState(() => cardError = caught.toString());
    } finally {
      if (mounted) setState(() => cardLoading = false);
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      data = await NativeApi.call('getEnergy');
    } catch (caught) {
      error = caught.toString();
    }
    // 原生侧在查询成功时会顺手记一次采样，这里重新读一下好让估算立刻刷新。
    await loadDrainSamples();
    if (mounted) setState(() => loading = false);
  }

  void _openEnergyAlertSheet() {
    var enabled = energyAlertEnabled;
    var threshold = energyThreshold.clamp(0.5, 50.0);
    var saving = false;

    showMiuixSheet<void>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) {
          final palette = sheetContext.palette;

          Future<void> commit({bool? nextEnabled, double? nextThreshold}) async {
            update(() {
              if (nextEnabled != null) enabled = nextEnabled;
              if (nextThreshold != null) threshold = nextThreshold;
              saving = true;
            });
            final ok = await _saveMonitorSettings({
              'energy_enabled': enabled,
              'energy_threshold': threshold,
            });
            if (mounted && ok) {
              setState(() {
                energyAlertEnabled = enabled;
                energyThreshold = threshold;
              });
            }
            if (sheetContext.mounted) update(() => saving = false);
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MiuixSheetHeader(
                title: '电量余额预警',
                subtitle: '定时在后台检测寝室余电，低于阈值时发送本地通知',
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
                      child: Text(
                        '开启低电量本地通知',
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Switch(
                      value: enabled,
                      onChanged: saving
                          ? null
                          : (value) => commit(nextEnabled: value),
                    ),
                  ],
                ),
              ),
              if (enabled) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      '预警额度',
                      style: TextStyle(
                        color: palette.inkSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${number(threshold)} 度',
                      style: TextStyle(
                        color: palette.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: threshold,
                  min: 0.5,
                  max: 50,
                  divisions: 99,
                  label: '${number(threshold)} 度',
                  onChanged: saving
                      ? null
                      : (value) => update(() => threshold = value),
                  onChangeEnd: saving
                      ? null
                      : (value) => commit(nextThreshold: value),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final preset in [2.0, 5.0, 10.0, 20.0])
                      ChoiceChip(
                        label: Text('${number(preset)} 度'),
                        selected: (threshold - preset).abs() < 0.1,
                        onSelected: saving
                            ? null
                            : (_) => commit(nextThreshold: preset),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _openEmailAlertSheet() {
    var enabled = emailAlertEnabled;
    var threshold = emailThreshold.clamp(0.5, 50.0);
    var saving = false;
    var showSecret = false;
    String? sheetError;

    showMiuixSheet<void>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) {
          final palette = sheetContext.palette;

          Future<void> commit({
            bool? nextEnabled,
            double? nextThreshold,
            bool includeCredentials = false,
          }) async {
            final endpoint = emailEndpoint.text.trim();
            final secret = emailSecret.text.trim();
            final targetEnabled = nextEnabled ?? enabled;

            if (includeCredentials &&
                targetEnabled &&
                (endpoint.isEmpty || (secret.isEmpty && !emailSecretSet))) {
              update(() => sheetError = '请填写发信接口地址与提醒密钥');
              return;
            }

            update(() {
              if (nextEnabled != null) enabled = nextEnabled;
              if (nextThreshold != null) threshold = nextThreshold;
              saving = true;
              sheetError = null;
            });

            final payload = <String, Object?>{
              'energy_email_enabled': enabled,
              'energy_email_threshold': threshold,
            };
            if (includeCredentials) {
              payload['energy_email_endpoint'] = endpoint;
              // 留空表示沿用已保存的密钥。
              if (secret.isNotEmpty) payload['energy_email_secret'] = secret;
            }

            final ok = await _saveMonitorSettings(payload);
            if (ok && mounted) {
              setState(() {
                emailAlertEnabled = enabled;
                emailThreshold = threshold;
                if (includeCredentials && secret.isNotEmpty) {
                  emailSecretSet = true;
                }
                if (includeCredentials) emailSecret.clear();
              });
              if (sheetContext.mounted && includeCredentials) {
                Navigator.of(sheetContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('邮件提醒配置已保存')),
                );
                return;
              }
            }
            if (sheetContext.mounted) update(() => saving = false);
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MiuixSheetHeader(
                title: '低电量邮件提醒',
                subtitle: '电量低于设定阈值时请求你的服务端发信接口发送邮件',
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
                            '开启邮件提醒',
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '上次发信：$lastEmailStatus',
                            style: TextStyle(
                              color: palette.inkSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: enabled,
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value &&
                                  (emailEndpoint.text.trim().isEmpty ||
                                      (emailSecret.text.trim().isEmpty &&
                                          !emailSecretSet))) {
                                update(() {
                                  enabled = true;
                                  sheetError = '请填写下方接口地址与密钥后点击保存';
                                });
                              } else {
                                commit(
                                  nextEnabled: value,
                                  includeCredentials: false,
                                );
                              }
                            },
                    ),
                  ],
                ),
              ),
              if (enabled) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      '发信阈值',
                      style: TextStyle(
                        color: palette.inkSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${number(threshold)} 度',
                      style: TextStyle(
                        color: palette.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: threshold,
                  min: 0.5,
                  max: 50,
                  divisions: 99,
                  label: '${number(threshold)} 度',
                  onChanged: saving
                      ? null
                      : (value) => update(() => threshold = value),
                  onChangeEnd: saving
                      ? null
                      : (value) => commit(nextThreshold: value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailEndpoint,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: '发信接口地址',
                    hintText: 'https://你的域名/api/energy-alert',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailSecret,
                  obscureText: !showSecret,
                  autocorrect: false,
                  enabled: !saving,
                  decoration: InputDecoration(
                    labelText: '提醒密钥',
                    hintText: emailSecretSet
                        ? '已保存，留空表示不修改'
                        : '与服务端 ZZU_ALERT_SECRET 一致',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          update(() => showSecret = !showSecret),
                      icon: Icon(
                        showSecret
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                if (sheetError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: ShapeDecoration(
                      color: palette.dangerSoft,
                      shape: miuixShape(12),
                    ),
                    child: Text(
                      sheetError!,
                      style: TextStyle(color: palette.danger, fontSize: 12.5),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: saving
                        ? null
                        : () => commit(includeCredentials: true),
                    child: saving
                        ? const Loader(size: 18, color: Colors.white)
                        : const Text('保存设置'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> recharge({String? initialMeterId}) async {
    final meters = ((data?['meter_list'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final available = <String, Map>{};
    for (final meter in meters) {
      final meterId = meter['meter_id']?.toString() ?? '';
      if (meterId.isNotEmpty && meter['error'] == null) {
        available[meterId] = meter;
      }
    }
    if (available.isEmpty) return;

    final amount = TextEditingController();
    final password = TextEditingController();
    var selected = (initialMeterId != null && available.containsKey(initialMeterId))
        ? initialMeterId
        : available.keys.first;
    var showPayPassword = false;
    String? validationError;

    Map<String, Object?>? form;
    try {
      form = await showMiuixSheet<Map<String, Object?>>(
        context,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, update) {
            final palette = sheetContext.palette;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MiuixSheetHeader(
                  title: '充值电费',
                  subtitle: '请选择目标电表并核对电表 ID',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.electric_meter_outlined),
                    labelText: '目标电表',
                  ),
                  items: [
                    for (final entry in available.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          (entry.value['label'] ?? '寝室电表').toString(),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) update(() => selected = value);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '电表 ID：$selected',
                  style: TextStyle(color: palette.inkSecondary, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.currency_yen_rounded),
                    hintText: '充值金额（正整数元）',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final preset in [10, 20, 50, 100])
                      ActionChip(
                        label: Text('¥$preset'),
                        onPressed: () {
                          amount.text = '$preset';
                          update(() => validationError = null);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: !showPayPassword,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.password_rounded),
                    hintText: '校园卡支付密码',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          update(() => showPayPassword = !showPayPassword),
                      icon: Icon(
                        showPayPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '支付密码仅参与本次本机加密请求，不会保存。',
                  style: TextStyle(color: palette.inkMuted, fontSize: 11.5),
                ),
                if (validationError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: ShapeDecoration(
                      color: palette.dangerSoft,
                      shape: miuixShape(12),
                    ),
                    child: Text(
                      validationError!,
                      style: TextStyle(color: palette.danger, fontSize: 12.5),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: () {
                      final value = int.tryParse(amount.text.trim());
                      if (value == null || value <= 0) {
                        update(() => validationError = '请输入正整数充值金额');
                        return;
                      }
                      if (password.text.isEmpty) {
                        update(() => validationError = '请输入校园卡支付密码');
                        return;
                      }
                      Navigator.pop(sheetContext, {
                        'type': (available[selected]!['label'] ?? '寝室电表')
                            .toString(),
                        'meter_id': selected,
                        'amount': value,
                        'password': password.text,
                      });
                    },
                    child: const Text('下一步：核对订单'),
                  ),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      amount.dispose();
      password.dispose();
    }

    if (form == null || !mounted) return;
    final type = form['type']! as String;
    final value = form['amount']! as int;
    final meterId = form['meter_id']! as String;
    final payPassword = form['password']! as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = dialogContext.palette;
        return AlertDialog(
          title: const Text('确认充值'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConfirmRow('电表类型', type),
              ConfirmRow('电表 ID', meterId),
              ConfirmRow('充值金额', '¥$value'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: ShapeDecoration(
                  color: palette.warningSoft,
                  shape: miuixShape(12),
                ),
                child: Text(
                  '提交后不能由本应用撤销，请再次核对。',
                  style: TextStyle(color: palette.warning, fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('返回检查'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认支付'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => recharging = true);
    try {
      final result = await NativeApi.call('rechargeEnergy', {
        'meter_id': meterId,
        'meter_type': type,
        'amount': value,
        'payment_password': payPassword,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message']?.toString() ?? '充值请求已提交')),
        );
      }
      await Future.wait([load(), loadCardBalance()]);
    } catch (caught) {
      // 保留电表卡片展示，以提示形式告知错误，不覆盖整页。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(caught.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => recharging = false);
    }
  }

  Future<void> _openDrainChart() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DrainChartPage(initialSamples: drainSamples),
      ),
    );
    if (mounted) await loadDrainSamples();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meters = ((data?['meter_list'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final remaining = meters
        .where((meter) => meter['error'] == null && meter['remaining'] is num)
        .map((meter) => (meter['remaining'] as num).toDouble())
        .toList();
    final isLow =
        energyAlertEnabled &&
        remaining.any((value) => value <= energyThreshold);
    final drain = estimateDrain(drainSamples);

    final hasValidMeter = meters.any(
      (meter) =>
          (meter['meter_id']?.toString() ?? '').isNotEmpty &&
          meter['error'] == null,
    );

    return Column(
      children: [
        MiuixPageHeader(
          title: '寝室电量',
          subtitle: data == null
              ? '读取一卡通默认房间与实际电表'
              : '寝室 ${data!['room'] ?? '--'}',
          action: IconButton.filledTonal(
            tooltip: '刷新电量与校园卡余额',
            onPressed: loading || recharging
                ? null
                : () {
                    load();
                    loadCardBalance();
                  },
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: Loader())
              : error != null
              ? ErrorState(
                  message: error!,
                  retry: () async {
                    loadCardBalance();
                    await load();
                  },
                )
              : RefreshIndicator(
                  onRefresh: () => Future.wait([load(), loadCardBalance()]),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    children: [
                      _CampusCardBanner(
                        balance: cardBalance,
                        emailUnread: emailUnread,
                        loading: cardLoading,
                        error: cardError,
                        onRefresh: cardLoading ? null : loadCardBalance,
                      ),
                      const SizedBox(height: 12),
                      for (var index = 0; index < meters.length; index++) ...[
                        MeterCard(
                          type: (meters[index]['label'] ?? '寝室电表').toString(),
                          icon: meterIcon(
                            (meters[index]['label'] ?? '').toString(),
                          ),
                          meter: meters[index],
                          threshold: energyAlertEnabled
                              ? energyThreshold
                              : null,
                          onRecharge: (meters[index]['error'] == null &&
                                  !recharging)
                              ? () => recharge(
                                    initialMeterId: meters[index]['meter_id']
                                        ?.toString(),
                                  )
                              : null,
                        ),
                        if (index < meters.length - 1)
                          const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 14),
                      _DrainPreviewCard(
                        drain: drain,
                        samples: drainSamples,
                        onTap: _openDrainChart,
                      ),
                      const MiuixSectionHeader(
                        title: '预警与通知',
                        padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
                      ),
                      MiuixGroupedCard(
                        children: [
                          MiuixTile(
                            icon: isLow
                                ? Icons.warning_amber_rounded
                                : Icons.notifications_none_rounded,
                            iconColor: isLow ? palette.danger : palette.primary,
                            title: '电量余额预警',
                            subtitle: isLow
                                ? '已有电表低于 ${number(energyThreshold)} 度'
                                : energyAlertEnabled
                                ? '低于 ${number(energyThreshold)} 度时通知'
                                : '定时后台检查并发送本地通知',
                            trailingText: energyAlertEnabled
                                ? '≤ ${number(energyThreshold)} 度'
                                : '未开启',
                            onTap: alertSaving ? null : _openEnergyAlertSheet,
                          ),
                          MiuixTile(
                            icon: emailAlertEnabled
                                ? Icons.mark_email_read_outlined
                                : Icons.mail_outline_rounded,
                            iconColor: palette.info,
                            title: '低电量邮件提醒',
                            subtitle: emailAlertEnabled
                                ? '低于 ${number(emailThreshold)} 度发信 · $lastEmailStatus'
                                : '连接自建发信接口发送邮件预警',
                            trailingText: emailAlertEnabled ? '已开启' : '未开启',
                            onTap: alertSaving ? null : _openEmailAlertSheet,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: hasValidMeter && !recharging
                              ? () => recharge()
                              : null,
                          icon: recharging
                              ? const Loader(size: 18, color: Colors.white)
                              : const Icon(
                                  Icons.account_balance_wallet_outlined,
                                ),
                          label: Text(recharging ? '正在提交充值…' : '充值电费'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '充值前会再次弹窗核对电表类型、完整 ID 与金额。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.inkMuted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// 单个电表卡片。
class MeterCard extends StatelessWidget {
  const MeterCard({
    super.key,
    required this.type,
    required this.icon,
    required this.meter,
    this.threshold,
    this.onRecharge,
  });

  final String type;
  final IconData icon;
  final Map? meter;
  final double? threshold;
  final VoidCallback? onRecharge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final failed = meter == null || meter!['error'] != null;
    final remaining = !failed && meter!['remaining'] is num
        ? (meter!['remaining'] as num).toDouble()
        : null;
    final isLow = threshold != null && remaining != null && remaining <= threshold!;
    final accent = failed
        ? palette.danger
        : isLow
        ? palette.warning
        : palette.primary;
    final wellBg = failed
        ? palette.dangerSoft
        : isLow
        ? palette.warningSoft
        : palette.primarySoft;

    return MiuixCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      borderColor: failed
          ? palette.danger.withValues(alpha: 0.35)
          : isLow
          ? palette.warning.withValues(alpha: 0.45)
          : palette.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: ShapeDecoration(
                  color: wellBg,
                  shape: miuixShape(15),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          type,
                          style: TextStyle(
                            color: palette.inkSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (failed)
                          MiuixTag(
                            '查询失败',
                            color: palette.danger,
                            backgroundColor: palette.dangerSoft,
                          )
                        else if (isLow)
                          MiuixTag(
                            '余额偏低',
                            color: palette.warning,
                            backgroundColor: palette.warningSoft,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      failed ? '--' : '${number(meter!['remaining'])} 度',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: failed ? palette.danger : palette.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              if (!failed && onRecharge != null)
                FilledButton.tonal(
                  onPressed: onRecharge,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.primarySoft,
                    foregroundColor: palette.onPrimarySoft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '充值',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  failed
                      ? (meter?['error'] ?? '未返回数据').toString()
                      : '电表 ID：${meter!['meter_id']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: failed ? palette.danger : palette.inkMuted,
                    fontSize: 11.5,
                  ),
                ),
              ),
              if (!failed)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: meter!['meter_id'].toString()),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('电表 ID 已复制')),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          color: palette.inkMuted,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '复制',
                          style: TextStyle(
                            color: palette.inkSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DrainPreviewCard extends StatelessWidget {
  const _DrainPreviewCard({
    required this.drain,
    required this.samples,
    required this.onTap,
  });

  final List<DrainEstimate> drain;
  final List<Map> samples;
  final VoidCallback onTap;

  List<double> _sparkValues() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - drainWindowDays * 86400 * 1000;
    final grouped = <String, List<Map>>{};
    for (final raw in samples) {
      final t = (raw['t'] as num?)?.toDouble();
      final q = (raw['q'] as num?)?.toDouble();
      if (t == null || q == null || t < cutoff) continue;
      grouped.putIfAbsent((raw['id'] ?? '').toString(), () => []).add(raw);
    }
    List<Map> best = const [];
    for (final list in grouped.values) {
      if (list.length > best.length) best = list;
    }
    if (best.length < 2) return const [];
    final sorted = List<Map>.from(best)
      ..sort((a, b) => (a['t'] as num).compareTo(b['t'] as num));
    return [for (final item in sorted) (item['q'] as num).toDouble()];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final spark = _sparkValues();

    return MiuixCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: ShapeDecoration(
                  color: palette.primarySoft,
                  shape: miuixShape(10),
                ),
                child: Icon(
                  Icons.speed_rounded,
                  color: palette.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '耗电速度与曲线',
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (spark.length >= 2) ...[
                SizedBox(
                  width: 58,
                  height: 24,
                  child: CustomPaint(
                    painter: _MiniSparkPainter(
                      values: spark,
                      color: palette.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                '详情',
                style: TextStyle(color: palette.inkMuted, fontSize: 12),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.inkMuted,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (drain.isEmpty)
            Text(
              '还没有采样数据。多查几次电量（或开启后台预警）即可估算还能用多久。',
              style: TextStyle(
                color: palette.inkSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            )
          else
            for (final item in drain)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  formatDrainLine(item),
                  style: TextStyle(
                    color: item.daysLeft == null
                        ? palette.inkSecondary
                        : palette.ink,
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _MiniSparkPainter extends CustomPainter {
  _MiniSparkPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var minV = values.first;
    var maxV = values.first;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final span = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = (1 - (values[i] - minV) / span) * (size.height - 4) + 2;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MiniSparkPainter old) =>
      old.values != values || old.color != color;
}

class _CampusCardBanner extends StatelessWidget {
  const _CampusCardBanner({
    required this.balance,
    required this.emailUnread,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  final double? balance;
  final int? emailUnread;
  final bool loading;
  final String? error;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasValue = balance != null;

    return MiuixCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onRefresh,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: ShapeDecoration(
              color: palette.primarySoft,
              shape: miuixShape(12),
            ),
            child: Icon(
              Icons.credit_card_rounded,
              color: palette.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '校园一卡通余额',
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (emailUnread != null && emailUnread! > 0) ...[
                      const SizedBox(width: 6),
                      MiuixTag(
                        '邮箱 $emailUnread 未读',
                        color: palette.info,
                        backgroundColor: palette.infoSoft,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  error != null && !hasValue
                      ? '获取失败 · 点按重试'
                      : '门户实时余额 · 点按刷新',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: error != null && !hasValue
                        ? palette.danger
                        : palette.inkMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (loading && !hasValue)
            const Loader(size: 18)
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '¥',
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 1),
                Text(
                  hasValue ? balance!.toStringAsFixed(2) : '--',
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (loading) ...[
                  const SizedBox(width: 8),
                  const Loader(size: 13),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
